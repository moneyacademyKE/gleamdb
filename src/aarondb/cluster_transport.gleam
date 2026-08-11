//// # cluster_transport — correlation-safe remote bridge for cluster runtimes
////
//// `cluster_runtime.Runtime` is a local Gleam actor capability. It cannot be
//// reconstructed from a remote BEAM PID because Gleam deliberately tags
//// subjects. This module keeps that capability boundary intact: it exposes a
//// separate remote handle and sends each request with a reply `Subject` created
//// by the caller, preserving Gleam's actor capability tag across the wire.
////
//// The bridge has no TCP fallback. Cross-node calls require an already connected
//// BEAM distribution channel; operators must configure authenticated TLS
//// distribution before a remote handle is admitted.

import aarondb/cluster_runtime as runtime
import aarondb/global
import aarondb/raft_runtime as raft
import gleam/erlang/process.{type Pid, type Subject}

pub opaque type RemoteRuntime {
  RemoteRuntime(pid: Pid)
}

pub fn connect(
  cluster: String,
  node: raft.NodeId,
) -> Result(RemoteRuntime, runtime.Error) {
  case global.whereis(registry_name(cluster, node)) {
    Ok(pid) -> Ok(RemoteRuntime(pid))
    Error(_) -> Error(runtime.RuntimeNotFound(node))
  }
}

pub fn receive(
  runtime: RemoteRuntime,
  frame: runtime.Frame,
  deadline_ms: Int,
) -> Result(raft.Reply, runtime.Error) {
  let RemoteRuntime(pid) = runtime
  let reply = process.new_subject()
  receive_frame(pid, frame, reply)
  await(reply, deadline_ms)
}

pub fn join(
  runtime: RemoteRuntime,
  peer: runtime.Peer,
  deadline_ms: Int,
) -> Result(Nil, runtime.Error) {
  let RemoteRuntime(pid) = runtime
  let reply = process.new_subject()
  join_peer(pid, peer, reply)
  await(reply, deadline_ms)
}

pub fn elect(
  runtime: RemoteRuntime,
  granted_votes: Int,
  deadline_ms: Int,
) -> Result(Nil, runtime.Error) {
  let RemoteRuntime(pid) = runtime
  let reply = process.new_subject()
  elect_leader(pid, granted_votes, reply)
  await(reply, deadline_ms)
}

pub fn replicate(
  runtime: RemoteRuntime,
  command: String,
  deadline_ms: Int,
) -> Result(Int, runtime.Error) {
  let RemoteRuntime(pid) = runtime
  let reply = process.new_subject()
  replicate_command(pid, command, reply)
  await(reply, deadline_ms)
}

pub fn inspect(
  runtime: RemoteRuntime,
  deadline_ms: Int,
) -> Result(runtime.Snapshot, runtime.Error) {
  let RemoteRuntime(pid) = runtime
  let reply = process.new_subject()
  inspect_runtime(pid, reply)
  case process.receive(reply, deadline_ms) {
    Ok(snapshot) -> Ok(snapshot)
    Error(_) -> Error(runtime.DeadlineExceeded)
  }
}

pub fn shutdown(
  runtime: RemoteRuntime,
  deadline_ms: Int,
) -> Result(Nil, runtime.Error) {
  let RemoteRuntime(pid) = runtime
  let reply = process.new_subject()
  stop_runtime(pid, reply)
  case process.receive(reply, deadline_ms) {
    Ok(Nil) -> Ok(Nil)
    Error(_) -> Error(runtime.DeadlineExceeded)
  }
}

@external(erlang, "aarondb_cluster_transport_ffi", "receive_frame")
fn receive_frame(
  pid: Pid,
  frame: runtime.Frame,
  reply: Subject(Result(raft.Reply, runtime.Error)),
) -> Nil

@external(erlang, "aarondb_cluster_transport_ffi", "join_peer")
fn join_peer(
  pid: Pid,
  peer: runtime.Peer,
  reply: Subject(Result(Nil, runtime.Error)),
) -> Nil

@external(erlang, "aarondb_cluster_transport_ffi", "elect_leader")
fn elect_leader(
  pid: Pid,
  granted_votes: Int,
  reply: Subject(Result(Nil, runtime.Error)),
) -> Nil

@external(erlang, "aarondb_cluster_transport_ffi", "replicate_command")
fn replicate_command(
  pid: Pid,
  command: String,
  reply: Subject(Result(Int, runtime.Error)),
) -> Nil

@external(erlang, "aarondb_cluster_transport_ffi", "inspect_runtime")
fn inspect_runtime(pid: Pid, reply: Subject(runtime.Snapshot)) -> Nil

@external(erlang, "aarondb_cluster_transport_ffi", "stop_runtime")
fn stop_runtime(pid: Pid, reply: Subject(Nil)) -> Nil

fn await(
  reply: Subject(Result(value, runtime.Error)),
  deadline_ms: Int,
) -> Result(value, runtime.Error) {
  case deadline_ms > 0 {
    False -> Error(runtime.DeadlineExceeded)
    True ->
      case process.receive(reply, deadline_ms) {
        Ok(result) -> result
        Error(_) -> Error(runtime.DeadlineExceeded)
      }
  }
}

fn registry_name(cluster: String, node: String) -> String {
  "aarondb.cluster." <> cluster <> "." <> node
}
