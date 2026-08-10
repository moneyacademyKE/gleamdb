//// # command — deterministic replicated command-state-machine reference
////
//// This module deliberately has no transport, leader election, or local DB
//// integration. A future consensus runtime supplies the committed index; this
//// module deterministically applies the same command on every member.

import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub type Consistency {
  Local
  LeaseRead
  Linearizable
}

pub type Command {
  Put(key: String, value: String)
  CompareAndSet(key: String, expected: Option(String), replacement: String)
  IssueFence(resource: String)
}

pub type CommandRequest {
  CommandRequest(idempotency_key: String, command: Command)
}

pub type CommandResult {
  Written(key: String, value: String)
  CasApplied(key: String, previous: Option(String), value: String)
  CasRejected(key: String, actual: Option(String))
  FenceIssued(resource: String, token: Int)
}

pub type CommandError {
  IdempotencyPayloadMismatch(key: String)
  InvalidCommittedIndex(index: Int, last_applied: Int)
}

pub type Value {
  Value(key: String, value: String)
}

pub type Applied {
  Applied(idempotency_key: String, fingerprint: String, result: CommandResult)
}

pub type State {
  State(
    values: List(Value),
    fences: List(#(String, Int)),
    applied: List(Applied),
    last_applied: Int,
  )
}

pub fn new() -> State {
  State([], [], [], -1)
}

/// The committed index must advance exactly once. Retried idempotency requests
/// return their original result without applying another mutation.
pub fn apply(
  index: Int,
  request: CommandRequest,
  state: State,
) -> Result(#(State, CommandResult), CommandError) {
  case find_applied(state.applied, request.idempotency_key) {
    Some(Applied(_, saved_fingerprint, result)) ->
      case saved_fingerprint == fingerprint(request.command) {
        True -> Ok(#(state, result))
        False -> Error(IdempotencyPayloadMismatch(request.idempotency_key))
      }
    None ->
      case index == state.last_applied + 1 {
        False -> Error(InvalidCommittedIndex(index, state.last_applied))
        True -> apply_new(index, request, state)
      }
  }
}

/// The hash is intentionally constructed from closed, ordered data. It is an
/// audit/replay fingerprint, not a cryptographic signature.
pub fn replay_hash(state: State) -> String {
  "state|"
  <> int_string(state.last_applied)
  <> "|values|"
  <> values_fingerprint(state.values)
  <> "|fences|"
  <> fences_fingerprint(state.fences)
  <> "|applied|"
  <> applied_fingerprint(state.applied)
}

pub fn read(
  state: State,
  key: String,
  mode: Consistency,
) -> #(Consistency, Option(String)) {
  #(mode, get_value(state.values, key))
}

pub fn last_applied(state: State) -> Int {
  state.last_applied
}

fn apply_new(
  index: Int,
  request: CommandRequest,
  state: State,
) -> Result(#(State, CommandResult), CommandError) {
  let #(values, fences, result) =
    execute(request.command, state.values, state.fences)
  let updated =
    State(
      values: values,
      fences: fences,
      applied: list.append(state.applied, [
        Applied(request.idempotency_key, fingerprint(request.command), result),
      ]),
      last_applied: index,
    )
  Ok(#(updated, result))
}

fn execute(
  command: Command,
  values: List(Value),
  fences: List(#(String, Int)),
) -> #(List(Value), List(#(String, Int)), CommandResult) {
  case command {
    Put(key, value) -> #(
      put_value(values, key, value),
      fences,
      Written(key, value),
    )
    CompareAndSet(key, expected, replacement) -> {
      let actual = get_value(values, key)
      case actual == expected {
        True -> #(
          put_value(values, key, replacement),
          fences,
          CasApplied(key, actual, replacement),
        )
        False -> #(values, fences, CasRejected(key, actual))
      }
    }
    IssueFence(resource) -> {
      let token = fence_for(fences, resource) + 1
      #(
        values,
        put_fence(fences, resource, token),
        FenceIssued(resource, token),
      )
    }
  }
}

fn fingerprint(command: Command) -> String {
  case command {
    Put(key, value) -> "put:" <> frame(key) <> frame(value)
    CompareAndSet(key, expected, replacement) ->
      "cas:" <> frame(key) <> option_fingerprint(expected) <> frame(replacement)
    IssueFence(resource) -> "fence:" <> frame(resource)
  }
}

fn frame(value: String) -> String {
  int_string(string.length(value)) <> ":" <> value
}

fn option_fingerprint(value: Option(String)) -> String {
  case value {
    None -> "none"
    Some(content) -> "some:" <> frame(content)
  }
}

fn get_value(values: List(Value), wanted: String) -> Option(String) {
  case values {
    [] -> None
    [Value(key, value), ..rest] ->
      case key == wanted {
        True -> Some(value)
        False -> get_value(rest, wanted)
      }
  }
}

fn put_value(
  values: List(Value),
  wanted: String,
  replacement: String,
) -> List(Value) {
  case values {
    [] -> [Value(wanted, replacement)]
    [Value(key, value), ..rest] ->
      case key == wanted {
        True -> [Value(wanted, replacement), ..rest]
        False -> [Value(key, value), ..put_value(rest, wanted, replacement)]
      }
  }
}

fn find_applied(applied: List(Applied), key: String) -> Option(Applied) {
  case applied {
    [] -> None
    [Applied(saved_key, saved_fingerprint, saved_result), ..rest] ->
      case saved_key == key {
        True -> Some(Applied(saved_key, saved_fingerprint, saved_result))
        False -> find_applied(rest, key)
      }
  }
}

fn fence_for(fences: List(#(String, Int)), resource: String) -> Int {
  case fences {
    [] -> 0
    [#(saved_resource, token), ..rest] ->
      case saved_resource == resource {
        True -> token
        False -> fence_for(rest, resource)
      }
  }
}

fn put_fence(
  fences: List(#(String, Int)),
  resource: String,
  token: Int,
) -> List(#(String, Int)) {
  case fences {
    [] -> [#(resource, token)]
    [#(saved_resource, saved_token), ..rest] ->
      case saved_resource == resource {
        True -> [#(resource, token), ..rest]
        False -> [
          #(saved_resource, saved_token),
          ..put_fence(rest, resource, token)
        ]
      }
  }
}

fn values_fingerprint(values: List(Value)) -> String {
  case values {
    [] -> ""
    [Value(key, value), ..rest] ->
      frame(key) <> frame(value) <> values_fingerprint(rest)
  }
}

fn fences_fingerprint(fences: List(#(String, Int))) -> String {
  case fences {
    [] -> ""
    [#(resource, token), ..rest] ->
      frame(resource) <> int_string(token) <> fences_fingerprint(rest)
  }
}

fn applied_fingerprint(applied: List(Applied)) -> String {
  case applied {
    [] -> ""
    [Applied(key, hash, result), ..rest] ->
      frame(key)
      <> frame(hash)
      <> result_fingerprint(result)
      <> applied_fingerprint(rest)
  }
}

fn result_fingerprint(result: CommandResult) -> String {
  case result {
    Written(key, value) -> "written" <> frame(key) <> frame(value)
    CasApplied(key, previous, value) ->
      "cas-applied"
      <> frame(key)
      <> option_fingerprint(previous)
      <> frame(value)
    CasRejected(key, actual) ->
      "cas-rejected" <> frame(key) <> option_fingerprint(actual)
    FenceIssued(resource, token) ->
      "fence" <> frame(resource) <> int_string(token)
  }
}

fn int_string(value: Int) -> String {
  string.inspect(value)
}
