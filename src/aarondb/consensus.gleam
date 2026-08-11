//// # consensus — leader-gated command and lease reference surface
////
//// This module composes committed Raft positions with the deterministic command
//// state machine. It is deliberately transport-free: callers supply quorum
//// evidence and a monotonic clock reading. No wall-clock conversion is trusted.

import aarondb/command
import aarondb/raft_runtime as raft
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub type Lease {
  Lease(resource: String, holder: String, fence: Int, expires_at: Int)
}

pub type LeaseCommand {
  Acquire(resource: String, holder: String, ttl: Int)
  Renew(resource: String, holder: String, fence: Int, ttl: Int)
  Revoke(resource: String, holder: String, fence: Int)
}

pub type SubmitError {
  Redirect(leader: Option(raft.NodeId))
  QuorumUnavailable
  NotCommitted
  CommandFailed(error: command.CommandError)
  InvalidClock(now: Int, last_now: Int)
  InvalidTtl
  LeaseHeld(resource: String, fence: Int, expires_at: Int)
  StaleFence(resource: String, expected: Int, received: Int)
  LeaseHolderMismatch(resource: String)
}

pub type ReadError {
  ReadRedirect(leader: Option(raft.NodeId))
  ReadQuorumUnavailable
  ReadIndexUnavailable
}

pub type State {
  State(
    raft: raft.State,
    commands: command.State,
    leases: List(Lease),
    last_now: Int,
  )
}

pub fn new(raft_state: raft.State) -> State {
  State(raft_state, command.new(), [], -1)
}

/// Submission is accepted only on the elected leader after current-term quorum
/// replication has committed the supplied index.
pub fn submit(
  state: State,
  index: Int,
  replicated: Int,
  request: command.CommandRequest,
) -> Result(#(State, command.CommandResult), SubmitError) {
  case leader(state.raft) {
    False -> Error(Redirect(state.raft.leader))
    True -> {
      let committed = raft.commit_quorum(state.raft, index, replicated)
      case committed.hard.commit_index < index {
        True -> Error(QuorumUnavailable)
        False ->
          case command.apply(index, request, state.commands) {
            Ok(#(commands, result)) ->
              Ok(#(State(..state, raft: committed, commands: commands), result))
            Error(error) -> Error(CommandFailed(error))
          }
      }
    }
  }
}

/// Linearizable reads require leader confirmation and a ReadIndex at least as
/// recent as the command state. LeaseRead is intentionally not provided here:
/// callers must use a validated lease instead of relabelling a local read.
pub fn linearizable_read(
  state: State,
  read_index: Int,
  quorum_confirmed: Bool,
  key: String,
) -> Result(Option(String), ReadError) {
  case leader(state.raft) {
    False -> Error(ReadRedirect(state.raft.leader))
    True ->
      case quorum_confirmed {
        False -> Error(ReadQuorumUnavailable)
        True ->
          case read_index < command.last_applied(state.commands) {
            True -> Error(ReadIndexUnavailable)
            False -> {
              let #(_, value) =
                command.read(state.commands, key, command.Linearizable)
              Ok(value)
            }
          }
      }
  }
}

/// Uses a caller-supplied monotonic time domain. Regressing clock values are
/// rejected, so expiry cannot be extended by a local wall-clock rollback.
pub fn lease(
  state: State,
  index: Int,
  replicated: Int,
  now: Int,
  request: LeaseCommand,
) -> Result(#(State, Option(Lease)), SubmitError) {
  case now < state.last_now {
    True -> Error(InvalidClock(now, state.last_now))
    False -> lease_at_monotonic_time(state, index, replicated, now, request)
  }
}

pub fn validate_fence(
  state: State,
  resource: String,
  fence: Int,
) -> Result(Nil, SubmitError) {
  case find_lease(state.leases, resource) {
    Some(Lease(_, _, expected, _)) if expected == fence -> Ok(Nil)
    Some(Lease(_, _, expected, _)) ->
      Error(StaleFence(resource, expected, fence))
    None -> Error(StaleFence(resource, 0, fence))
  }
}

fn lease_at_monotonic_time(
  state: State,
  index: Int,
  replicated: Int,
  now: Int,
  request: LeaseCommand,
) -> Result(#(State, Option(Lease)), SubmitError) {
  case request {
    Acquire(resource, holder, ttl) ->
      acquire(state, index, replicated, now, resource, holder, ttl)
    Renew(resource, holder, fence, ttl) ->
      renew(state, index, replicated, now, resource, holder, fence, ttl)
    Revoke(resource, holder, fence) ->
      revoke(state, index, replicated, now, resource, holder, fence)
  }
}

fn acquire(
  state: State,
  index: Int,
  replicated: Int,
  now: Int,
  resource: String,
  holder: String,
  ttl: Int,
) -> Result(#(State, Option(Lease)), SubmitError) {
  case ttl > 0 {
    False -> Error(InvalidTtl)
    True ->
      case find_lease(state.leases, resource) {
        Some(Lease(_, _, fence, expiry)) if expiry > now ->
          Error(LeaseHeld(resource, fence, expiry))
        _ ->
          case
            submit(
              state,
              index,
              replicated,
              command.CommandRequest(
                "lease:"
                  <> resource
                  <> ":"
                  <> holder
                  <> ":"
                  <> int_string(index),
                command.IssueFence(resource),
              ),
            )
          {
            Error(error) -> Error(error)
            Ok(#(advanced, command.FenceIssued(_, fence))) -> {
              let granted = Lease(resource, holder, fence, now + ttl)
              Ok(#(
                State(
                  ..advanced,
                  leases: put_lease(advanced.leases, granted),
                  last_now: now,
                ),
                Some(granted),
              ))
            }
            Ok(_) -> Error(NotCommitted)
          }
      }
  }
}

fn renew(
  state: State,
  index: Int,
  replicated: Int,
  now: Int,
  resource: String,
  holder: String,
  fence: Int,
  ttl: Int,
) -> Result(#(State, Option(Lease)), SubmitError) {
  case ttl > 0 {
    False -> Error(InvalidTtl)
    True ->
      case find_lease(state.leases, resource) {
        None -> Error(StaleFence(resource, 0, fence))
        Some(Lease(_, _saved_holder, expected, _)) if expected != fence ->
          Error(StaleFence(resource, expected, fence))
        Some(Lease(_, saved_holder, _, _)) if saved_holder != holder ->
          Error(LeaseHolderMismatch(resource))
        Some(Lease(_, _, _, expiry)) if expiry <= now ->
          Error(StaleFence(resource, 0, fence))
        Some(_) ->
          case
            submit(
              state,
              index,
              replicated,
              command.CommandRequest(
                "renew:" <> resource <> ":" <> int_string(index),
                command.Put("lease-renew:" <> resource, int_string(now)),
              ),
            )
          {
            Error(error) -> Error(error)
            Ok(#(advanced, _)) -> {
              let renewed = Lease(resource, holder, fence, now + ttl)
              Ok(#(
                State(
                  ..advanced,
                  leases: put_lease(advanced.leases, renewed),
                  last_now: now,
                ),
                Some(renewed),
              ))
            }
          }
      }
  }
}

fn revoke(
  state: State,
  index: Int,
  replicated: Int,
  now: Int,
  resource: String,
  holder: String,
  fence: Int,
) -> Result(#(State, Option(Lease)), SubmitError) {
  case find_lease(state.leases, resource) {
    None -> Error(StaleFence(resource, 0, fence))
    Some(Lease(_, _saved_holder, expected, _)) if expected != fence ->
      Error(StaleFence(resource, expected, fence))
    Some(Lease(_, saved_holder, _, _)) if saved_holder != holder ->
      Error(LeaseHolderMismatch(resource))
    Some(_) ->
      case
        submit(
          state,
          index,
          replicated,
          command.CommandRequest(
            "revoke:" <> resource <> ":" <> int_string(index),
            command.Put("lease-revoke:" <> resource, int_string(now)),
          ),
        )
      {
        Error(error) -> Error(error)
        Ok(#(advanced, _)) ->
          Ok(#(
            State(
              ..advanced,
              leases: remove_lease(advanced.leases, resource),
              last_now: now,
            ),
            None,
          ))
      }
  }
}

fn leader(state: raft.State) -> Bool {
  state.role == raft.Leader && state.leader == Some(state.node)
}

fn find_lease(leases: List(Lease), resource: String) -> Option(Lease) {
  case leases {
    [] -> None
    [lease, ..rest] -> {
      let Lease(saved, _, _, _) = lease
      case saved == resource {
        True -> Some(lease)
        False -> find_lease(rest, resource)
      }
    }
  }
}

fn put_lease(leases: List(Lease), replacement: Lease) -> List(Lease) {
  let Lease(resource, _, _, _) = replacement
  case leases {
    [] -> [replacement]
    [lease, ..rest] -> {
      let Lease(saved, _, _, _) = lease
      case saved == resource {
        True -> [replacement, ..rest]
        False -> [lease, ..put_lease(rest, replacement)]
      }
    }
  }
}

fn remove_lease(leases: List(Lease), resource: String) -> List(Lease) {
  list.filter(leases, fn(lease) {
    let Lease(saved, _, _, _) = lease
    saved != resource
  })
}

fn int_string(value: Int) -> String {
  string.inspect(value)
}
