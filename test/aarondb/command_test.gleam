import aarondb/command
import gleam/option.{None, Some}
import gleeunit/should

pub fn identical_replay_produces_identical_hash_test() {
  let request =
    command.CommandRequest("request-1", command.Put("colour", "blue"))
  let assert Ok(#(first, _)) = command.apply(0, request, command.new())
  let assert Ok(#(second, _)) = command.apply(0, request, command.new())
  should.equal(command.replay_hash(first), command.replay_hash(second))
}

pub fn duplicate_returns_original_result_without_reapplying_test() {
  let request =
    command.CommandRequest("request-1", command.IssueFence("writer"))
  let assert Ok(#(state, first)) = command.apply(0, request, command.new())
  let assert Ok(#(replayed, retry)) = command.apply(99, request, state)
  should.equal(first, command.FenceIssued("writer", 1))
  should.equal(retry, first)
  should.equal(command.last_applied(replayed), 0)
}

pub fn same_idempotency_key_with_different_payload_is_rejected_test() {
  let first = command.CommandRequest("request-1", command.Put("colour", "blue"))
  let changed =
    command.CommandRequest("request-1", command.Put("colour", "green"))
  let assert Ok(#(state, _)) = command.apply(0, first, command.new())
  should.equal(
    command.apply(1, changed, state),
    Error(command.IdempotencyPayloadMismatch("request-1")),
  )
}

pub fn cas_is_decided_at_its_committed_position_test() {
  let write = command.CommandRequest("put", command.Put("mode", "open"))
  let first_cas =
    command.CommandRequest(
      "cas-1",
      command.CompareAndSet("mode", Some("open"), "closed"),
    )
  let stale_cas =
    command.CommandRequest(
      "cas-2",
      command.CompareAndSet("mode", Some("open"), "locked"),
    )
  let assert Ok(#(state, _)) = command.apply(0, write, command.new())
  let assert Ok(#(state, first)) = command.apply(1, first_cas, state)
  let assert Ok(#(_state, second)) = command.apply(2, stale_cas, state)
  should.equal(first, command.CasApplied("mode", Some("open"), "closed"))
  should.equal(second, command.CasRejected("mode", Some("closed")))
}

pub fn reads_keep_the_requested_consistency_mode_explicit_test() {
  let request = command.CommandRequest("put", command.Put("colour", "blue"))
  let assert Ok(#(state, _)) = command.apply(0, request, command.new())
  should.equal(command.read(state, "colour", command.Local), #(
    command.Local,
    Some("blue"),
  ))
  should.equal(command.read(state, "colour", command.LeaseRead), #(
    command.LeaseRead,
    Some("blue"),
  ))
  should.equal(command.read(state, "colour", command.Linearizable), #(
    command.Linearizable,
    Some("blue"),
  ))
}

pub fn persisted_state_preserves_results_and_fencing_across_recovery_test() {
  let issue = command.CommandRequest("lease-1", command.IssueFence("writer"))
  let assert Ok(#(recovered, first)) = command.apply(0, issue, command.new())
  let assert Ok(#(recovered, replayed)) = command.apply(0, issue, recovered)
  let next = command.CommandRequest("lease-2", command.IssueFence("writer"))
  let assert Ok(#(_recovered, second)) = command.apply(1, next, recovered)
  should.equal(first, command.FenceIssued("writer", 1))
  should.equal(replayed, first)
  should.equal(second, command.FenceIssued("writer", 2))
}

pub fn committed_indices_must_be_contiguous_test() {
  let request = command.CommandRequest("put", command.Put("colour", "blue"))
  should.equal(
    command.apply(2, request, command.new()),
    Error(command.InvalidCommittedIndex(2, -1)),
  )
}

pub fn absent_values_are_explicit_test() {
  should.equal(command.read(command.new(), "missing", command.Local), #(
    command.Local,
    None,
  ))
}
