//// # cluster_data_plane — committed services composed behind one node boundary
////
//// This is the stateful library boundary used by a cluster runtime after Raft
//// has supplied leader and quorum evidence. It never exposes a write before
//// the corresponding consensus command has committed. Derived services consume
//// the committed durable log and remain explicitly non-authoritative.

import aarondb/changefeed
import aarondb/command
import aarondb/consensus
import aarondb/durable_log
import aarondb/identity
import aarondb/operations
import aarondb/projection
import aarondb/projection_index
import aarondb/raft_runtime as raft
import gleam/option.{type Option}

pub type State {
  State(
    consensus: consensus.State,
    log: durable_log.DurableLog,
    projection: projection.Projection,
    index: projection_index.Index,
    recovery: identity.RecoveryState,
  )
}

pub type Error {
  WriteRejected(consensus.SubmitError)
  ReadRejected(consensus.ReadError)
  LeaseRejected(consensus.SubmitError)
  FeedRejected(changefeed.ChangefeedError)
  ProjectionRejected(projection.ProjectionError)
  IndexRejected(projection_index.Error)
}

/// Starts a node-local data plane. Production adapters replace the initial
/// single-node bootstrap with a persisted multi-voter Raft recovery image.
pub fn new(node: raft.NodeId, source: String) -> State {
  let raft = raft.new(node, [raft.Voter(node)]) |> raft.bootstrap_leader
  let assert Ok(index) = projection_index.new(1)
  State(
    consensus.new(raft),
    durable_log.new(source),
    projection.new("default", 1024, 3),
    index,
    identity.clean_recovery(),
  )
}

/// Applies only a quorum-committed deterministic command, then appends its
/// committed audit event. Retries retain the original command result and do
/// not produce another log entry.
pub fn write(
  state: State,
  index: Int,
  replicated: Int,
  request: command.CommandRequest,
) -> Result(#(State, command.CommandResult), Error) {
  let ready = ready_to_commit(state.consensus, index)
  case consensus.submit(ready, index, replicated, request) {
    Error(error) -> Error(WriteRejected(error))
    Ok(#(consensus, result)) -> {
      let #(log, _) =
        durable_log.append(
          state.log,
          command.replay_hash(consensus.commands),
          request.idempotency_key,
        )
      Ok(#(State(..state, consensus: consensus, log: log), result))
    }
  }
}

pub fn read(
  state: State,
  read_index: Int,
  quorum_confirmed: Bool,
  key: String,
) -> Result(Option(String), Error) {
  case
    consensus.linearizable_read(
      state.consensus,
      read_index,
      quorum_confirmed,
      key,
    )
  {
    Ok(value) -> Ok(value)
    Error(error) -> Error(ReadRejected(error))
  }
}

pub fn lease(
  state: State,
  index: Int,
  replicated: Int,
  now: Int,
  request: consensus.LeaseCommand,
) -> Result(#(State, Option(consensus.Lease)), Error) {
  let ready = ready_to_commit(state.consensus, index)
  case consensus.lease(ready, index, replicated, now, request) {
    Ok(#(consensus, lease)) ->
      Ok(#(State(..state, consensus: consensus), lease))
    Error(error) -> Error(LeaseRejected(error))
  }
}

pub fn validate_fence(
  state: State,
  resource: String,
  fence: Int,
) -> Result(Nil, Error) {
  case consensus.validate_fence(state.consensus, resource, fence) {
    Ok(Nil) -> Ok(Nil)
    Error(error) -> Error(LeaseRejected(error))
  }
}

pub fn resume_feed(
  state: State,
  cursor: changefeed.Cursor,
  credit: changefeed.Credit,
) -> Result(changefeed.Changefeed, Error) {
  case changefeed.resume(state.log, cursor, credit) {
    Ok(feed) -> Ok(feed)
    Error(error) -> Error(FeedRejected(error))
  }
}

/// Builds both derived services from the committed source. If either boundary
/// fails it remains visibly behind/degraded instead of answering from partial
/// state.
pub fn catch_up(state: State) -> Result(State, Error) {
  case projection.catch_up(state.projection, state.log) {
    Error(error) -> Error(ProjectionRejected(error))
    Ok(#(projection, log)) ->
      case rebuild_from_log(state.index, log, -1) {
        Error(error) -> Error(IndexRejected(error))
        Ok(index) ->
          Ok(State(..state, log: log, projection: projection, index: index))
      }
  }
}

pub fn rebuild_index(
  state: State,
  schema_version: Int,
) -> Result(State, Error) {
  case projection_index.begin_rebuild(state.index, schema_version) {
    Error(error) -> Error(IndexRejected(error))
    Ok(building) ->
      case rebuild_from_log(building, state.log, -1) {
        Error(error) -> Error(IndexRejected(error))
        Ok(replacement) ->
          case
            projection_index.swap(
              state.index,
              replacement,
              state.log.next_offset - 1,
            )
          {
            Error(error) -> Error(IndexRejected(error))
            Ok(index) -> Ok(State(..state, index: index))
          }
      }
  }
}

pub fn query_index(state: State) -> Result(List(String), Error) {
  case projection_index.query(state.index) {
    Ok(values) -> Ok(values)
    Error(error) -> Error(IndexRejected(error))
  }
}

pub fn status(
  state: State,
  acknowledged: Int,
  follower_match_index: Int,
) -> operations.Status {
  operations.status(
    state.consensus.raft,
    raft.quorum(state.consensus.raft) * 2 - 1,
    acknowledged,
    follower_match_index,
    projection.status(state.projection, state.log),
    state.index,
    state.consensus,
    state.recovery,
  )
}

fn ready_to_commit(state: consensus.State, index: Int) -> consensus.State {
  let previous = raft.last_index(state.raft)
  case index == previous + 1 {
    False -> state
    True -> {
      let rpc =
        raft.AppendEntries(
          state.raft.hard.term,
          state.raft.node,
          previous,
          raft.last_term(state.raft),
          [raft.LogEntry(state.raft.hard.term, "committed")],
          state.raft.hard.commit_index,
        )
      let #(logged, _) = raft.handle(state.raft, rpc)
      consensus.State(..state, raft: logged)
    }
  }
}

fn rebuild_from_log(
  index: projection_index.Index,
  log: durable_log.DurableLog,
  cursor: Int,
) -> Result(projection_index.Index, projection_index.Error) {
  case durable_log.scan_after(log, cursor) {
    Error(_) ->
      Ok(projection_index.degrade(index, "committed source unavailable"))
    Ok(entries) -> apply_entries(index, entries)
  }
}

fn apply_entries(
  index: projection_index.Index,
  entries: List(durable_log.Entry),
) -> Result(projection_index.Index, projection_index.Error) {
  case entries {
    [] -> Ok(index)
    [entry, ..rest] ->
      case projection_index.apply(index, entry.offset, entry.payload) {
        Error(error) -> Error(error)
        Ok(next) -> apply_entries(next, rest)
      }
  }
}
