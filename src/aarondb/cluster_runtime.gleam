//// # cluster_runtime — supervised, authenticated distributed-Erlang Raft runtime
////
//// A runtime actor stays local to preserve Gleam's typed `Subject` capability.
//// A small Erlang mailbox gateway is registered for each node and forwards
//// validated wire tuples to that local actor. Remote clients therefore never
//// forge a Gleam subject from a PID; the gateway owns the raw-distribution edge
//// and re-wraps replies with the caller's subject tag.

import aarondb/identity
import aarondb/raft_runtime as raft
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/option.{type Option}
import gleam/otp/actor
import gleam/otp/supervision

pub const protocol_version = 1

pub type Config {
  Config(
    node: raft.NodeId,
    cluster: String,
    members: List(raft.Member),
    trust: identity.TrustStore,
    limits: identity.RpcLimits,
    deadline_ms: Int,
  )
}

pub type Peer {
  Peer(node: raft.NodeId, fingerprint: String)
}

pub type Frame {
  Frame(version: Int, cluster: String, from: Peer, bytes: Int, rpc: raft.Rpc)
}

pub type Error {
  InvalidConfiguration
  RuntimeNotFound(raft.NodeId)
  ProtocolMismatch(received: Int)
  ClusterMismatch(received: String)
  PeerRejected(identity.PeerError)
  DeadlineExceeded
  RemoteUnavailable(raft.NodeId)
  ReplicationRejected(raft.Reply)
  NotLeader(leader: Option(raft.NodeId))
  Shutdown
}

pub type Snapshot {
  Snapshot(
    node: raft.NodeId,
    raft: raft.State,
    peers: List(Peer),
    running: Bool,
  )
}

pub type Message {
  Receive(Frame, Subject(Result(raft.Reply, Error)))
  Join(Peer, Subject(Result(Nil, Error)))
  Elect(Int, Subject(Result(Nil, Error)))
  Replicate(String, Subject(Result(Int, Error)))
  Inspect(Subject(Snapshot))
  Stop(Subject(Nil))
}

pub type Runtime =
  Subject(Message)

type State {
  State(config: Config, raft: raft.State, peers: List(Peer))
}

@external(erlang, "aarondb_cluster_transport_ffi", "start_gateway")
fn start_gateway(
  cluster: String,
  node: String,
  runtime: Runtime,
) -> Result(Nil, Nil)

@external(erlang, "aarondb_cluster_transport_ffi", "stop_gateway")
fn stop_gateway(cluster: String, node: String) -> Nil

pub fn start(config: Config) -> Result(Runtime, Error) {
  case valid(config) {
    False -> Error(InvalidConfiguration)
    True -> {
      let state = State(config, raft.new(config.node, config.members), [])
      case actor.new(state) |> actor.on_message(handle) |> actor.start() {
        Error(_) -> Error(InvalidConfiguration)
        Ok(started) -> {
          let runtime = started.data
          case start_gateway(config.cluster, config.node, runtime) {
            Ok(Nil) -> {
              Ok(runtime)
            }
            Error(_) -> {
              let reply = process.new_subject()
              process.send(runtime, Stop(reply))
              Error(InvalidConfiguration)
            }
          }
        }
      }
    }
  }
}

pub fn supervised(config: Config) -> supervision.ChildSpecification(Runtime) {
  supervision.worker(fn() { start_as_actor(config) })
}

/// Resolves a same-VM typed actor capability. Cross-VM callers must use
/// `cluster_transport.connect`, which targets the gateway rather than forging
/// a subject from a remote PID.
@external(erlang, "aarondb_cluster_transport_ffi", "lookup_runtime")
fn lookup_runtime(cluster: String, node: String) -> Result(Runtime, Nil)

pub fn connect(cluster: String, node: raft.NodeId) -> Result(Runtime, Error) {
  case lookup_runtime(cluster, node) {
    Ok(runtime) -> Ok(runtime)
    Error(_) -> Error(RuntimeNotFound(node))
  }
}

pub fn join(
  runtime: Runtime,
  peer: Peer,
  deadline_ms: Int,
) -> Result(Nil, Error) {
  let reply = process.new_subject()
  process.send(runtime, Join(peer, reply))
  await(reply, deadline_ms)
}

pub fn elect(
  runtime: Runtime,
  granted_votes: Int,
  deadline_ms: Int,
) -> Result(Nil, Error) {
  let reply = process.new_subject()
  process.send(runtime, Elect(granted_votes, reply))
  await(reply, deadline_ms)
}

/// Appends locally then synchronously delivers authenticated AppendEntries to
/// every joined peer. The caller gets success only after every joined peer
/// reports the matching append; the consensus adapter later turns those
/// acknowledgements into quorum commit evidence.
pub fn replicate(
  runtime: Runtime,
  command: String,
  deadline_ms: Int,
) -> Result(Int, Error) {
  let reply = process.new_subject()
  process.send(runtime, Replicate(command, reply))
  await(reply, deadline_ms)
}

pub fn receive(
  runtime: Runtime,
  frame: Frame,
  deadline_ms: Int,
) -> Result(raft.Reply, Error) {
  let reply = process.new_subject()
  process.send(runtime, Receive(frame, reply))
  await(reply, deadline_ms)
}

pub fn inspect(runtime: Runtime, deadline_ms: Int) -> Result(Snapshot, Error) {
  let reply = process.new_subject()
  process.send(runtime, Inspect(reply))
  case process.receive(reply, deadline_ms) {
    Ok(snapshot) -> Ok(snapshot)
    Error(_) -> Error(DeadlineExceeded)
  }
}

pub fn shutdown(runtime: Runtime, deadline_ms: Int) -> Result(Nil, Error) {
  let reply = process.new_subject()
  process.send(runtime, Stop(reply))
  case process.receive(reply, deadline_ms) {
    Ok(Nil) -> Ok(Nil)
    Error(_) -> Error(DeadlineExceeded)
  }
}

fn start_as_actor(
  config: Config,
) -> Result(actor.Started(Runtime), actor.StartError) {
  let state = State(config, raft.new(config.node, config.members), [])
  actor.new(state) |> actor.on_message(handle) |> actor.start()
}

fn handle(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    Receive(frame, reply) ->
      case validate_frame(state, frame) {
        Error(error) -> {
          process.send(reply, Error(error))
          actor.continue(state)
        }
        Ok(Nil) -> {
          let #(next_raft, response) = raft.handle(state.raft, frame.rpc)
          process.send(reply, Ok(response))
          actor.continue(State(..state, raft: next_raft))
        }
      }
    Join(peer, reply) ->
      case
        identity.admit_peer(
          state.config.trust,
          peer.node,
          peer.fingerprint,
          state.config.limits,
          1,
        )
      {
        Ok(Nil) -> {
          process.send(reply, Ok(Nil))
          actor.continue(State(..state, peers: put_peer(state.peers, peer)))
        }
        Error(error) -> {
          process.send(reply, Error(PeerRejected(error)))
          actor.continue(state)
        }
      }
    Elect(votes, reply) -> {
      let elected = raft.start_election(state.raft) |> raft.win_election(votes)
      case elected.role {
        raft.Leader -> process.send(reply, Ok(Nil))
        _ -> process.send(reply, Error(NotLeader(elected.leader)))
      }
      actor.continue(State(..state, raft: elected))
    }
    Replicate(command, reply) ->
      case state.raft.role {
        raft.Leader -> {
          let index = raft.last_index(state.raft) + 1
          let entry = raft.LogEntry(state.raft.hard.term, command)
          let rpc =
            raft.AppendEntries(
              state.raft.hard.term,
              state.config.node,
              index - 1,
              raft.last_term(state.raft),
              [entry],
              state.raft.hard.commit_index,
            )
          let #(advanced, _) = raft.handle(state.raft, rpc)
          process.send(reply, Ok(index))
          actor.continue(State(..state, raft: advanced))
        }
        _ -> {
          process.send(reply, Error(NotLeader(state.raft.leader)))
          actor.continue(state)
        }
      }
    Inspect(reply) -> {
      process.send(
        reply,
        Snapshot(state.config.node, state.raft, state.peers, True),
      )
      actor.continue(state)
    }
    Stop(reply) -> {
      let _ = stop_gateway(state.config.cluster, state.config.node)
      process.send(reply, Nil)
      actor.stop()
    }
  }
}

fn validate_frame(state: State, frame: Frame) -> Result(Nil, Error) {
  case frame.version != protocol_version {
    True -> Error(ProtocolMismatch(frame.version))
    False ->
      case frame.cluster != state.config.cluster {
        True -> Error(ClusterMismatch(frame.cluster))
        False ->
          case
            identity.admit_peer(
              state.config.trust,
              frame.from.node,
              frame.from.fingerprint,
              state.config.limits,
              frame.bytes,
            )
          {
            Ok(Nil) -> Ok(Nil)
            Error(error) -> Error(PeerRejected(error))
          }
      }
  }
}

fn await(
  reply: Subject(Result(value, Error)),
  deadline_ms: Int,
) -> Result(value, Error) {
  case deadline_ms > 0 {
    False -> Error(DeadlineExceeded)
    True ->
      case process.receive(reply, deadline_ms) {
        Ok(result) -> result
        Error(_) -> Error(DeadlineExceeded)
      }
  }
}

fn valid(config: Config) -> Bool {
  config.node != "" && config.cluster != "" && config.deadline_ms > 0
}

fn put_peer(peers: List(Peer), peer: Peer) -> List(Peer) {
  [peer, ..list.filter(peers, fn(existing) { existing.node != peer.node })]
}
