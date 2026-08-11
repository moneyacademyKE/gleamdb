import aarondb/cluster_runtime as cluster
import aarondb/cluster_transport as transport
import aarondb/identity
import aarondb/raft_runtime as raft
import gleam/option.{None}
import gleeunit/should

fn config(node: String) -> cluster.Config {
  let trust =
    identity.new("cluster-a", ["root-a"], ["a", "b", "c"])
    |> identity.put_certificate(identity.Certificate(
      "a",
      "fp-a",
      "root-a",
      identity.Active(1),
    ))
    |> identity.put_certificate(identity.Certificate(
      "b",
      "fp-b",
      "root-a",
      identity.Active(1),
    ))
    |> identity.put_certificate(identity.Certificate(
      "c",
      "fp-c",
      "root-a",
      identity.Active(1),
    ))
  cluster.Config(
    node,
    "cluster-a",
    [raft.Voter("a"), raft.Voter("b"), raft.Voter("c")],
    trust,
    identity.RpcLimits(1024, 3),
    100,
  )
}

pub fn three_nodes_join_elect_and_redirect_writes_test() {
  let assert Ok(a) = cluster.start(config("a"))
  let assert Ok(b) = cluster.start(config("b"))
  let assert Ok(c) = cluster.start(config("c"))
  let assert Ok(Nil) = cluster.join(a, cluster.Peer("b", "fp-b"), 100)
  let assert Ok(Nil) = cluster.join(a, cluster.Peer("c", "fp-c"), 100)
  let assert Ok(Nil) = cluster.elect(a, 2, 100)
  let assert Ok(0) = cluster.replicate(a, "put:k:v", 100)
  should.equal(
    cluster.replicate(b, "put:k:v", 100),
    Error(cluster.NotLeader(None)),
  )
  let assert Ok(_) = cluster.shutdown(a, 100)
  let assert Ok(_) = cluster.shutdown(b, 100)
  let assert Ok(_) = cluster.shutdown(c, 100)
  Nil
}

pub fn authenticated_frames_and_shutdown_fail_closed_test() {
  let assert Ok(a) = cluster.start(config("a"))
  let hostile =
    cluster.Frame(
      1,
      "cluster-a",
      cluster.Peer("b", "unknown"),
      1,
      raft.RequestVote(1, "b", -1, 0),
    )
  should.equal(
    cluster.receive(a, hostile, 100),
    Error(cluster.PeerRejected(identity.UnknownCertificate)),
  )
  let assert Ok(_) = cluster.shutdown(a, 100)
  should.equal(
    cluster.connect("cluster-a", "a"),
    Error(cluster.RuntimeNotFound("a")),
  )
}

pub fn protocol_and_cluster_versions_are_checked_before_raft_test() {
  let assert Ok(a) = cluster.start(config("a"))
  let old =
    cluster.Frame(
      0,
      "cluster-a",
      cluster.Peer("b", "fp-b"),
      1,
      raft.RequestVote(1, "b", -1, 0),
    )
  should.equal(cluster.receive(a, old, 100), Error(cluster.ProtocolMismatch(0)))
  let wrong_cluster =
    cluster.Frame(
      1,
      "wrong",
      cluster.Peer("b", "fp-b"),
      1,
      raft.RequestVote(1, "b", -1, 0),
    )
  should.equal(
    cluster.receive(a, wrong_cluster, 100),
    Error(cluster.ClusterMismatch("wrong")),
  )
  let assert Ok(_) = cluster.shutdown(a, 100)
}

pub fn remote_transport_uses_pid_bridge_without_forging_subjects_test() {
  let assert Ok(_a) = cluster.start(config("a"))
  let assert Ok(remote) = transport.connect("cluster-a", "a")
  let assert Ok(Nil) = transport.elect(remote, 2, 100)
  let assert Ok(0) = transport.replicate(remote, "put:k:v", 100)
  let assert Ok(snapshot) = transport.inspect(remote, 100)
  should.equal(snapshot.node, "a")
  let assert Ok(Nil) = transport.shutdown(remote, 100)
  should.equal(
    transport.connect("cluster-a", "a"),
    Error(cluster.RuntimeNotFound("a")),
  )
}
