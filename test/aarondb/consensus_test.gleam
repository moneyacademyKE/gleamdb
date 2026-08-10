import aarondb/command
import aarondb/consensus
import aarondb/raft_runtime as raft
import gleam/option.{None, Some}
import gleeunit/should

fn leader() -> consensus.State {
  let raft = raft.bootstrap_leader(raft.new("a", [raft.Voter("a")]))
  let #(logged, _) =
    raft.handle(
      raft,
      raft.AppendEntries(0, "a", -1, 0, [raft.LogEntry(0, "command")], -1),
    )
  consensus.new(logged)
}

fn follower() -> consensus.State {
  consensus.new(raft.new("b", [raft.Voter("a"), raft.Voter("b")]))
}

pub fn follower_submission_redirects_to_known_leader_test() {
  let state = follower()
  should.equal(
    consensus.submit(
      state,
      0,
      2,
      command.CommandRequest("write", command.Put("k", "v")),
    ),
    Error(consensus.Redirect(None)),
  )
}

pub fn quorum_committed_submission_is_idempotent_test() {
  let request = command.CommandRequest("write", command.Put("k", "v"))
  let assert Ok(#(written, command.Written("k", "v"))) =
    consensus.submit(leader(), 0, 1, request)
  let assert Ok(#(_, command.Written("k", "v"))) =
    consensus.submit(written, 0, 1, request)
  Nil
}

pub fn quorum_loss_does_not_apply_command_test() {
  let request = command.CommandRequest("write", command.Put("k", "v"))
  should.equal(
    consensus.submit(leader(), 0, 0, request),
    Error(consensus.QuorumUnavailable),
  )
}

pub fn linearizable_read_requires_current_quorum_test() {
  let request = command.CommandRequest("write", command.Put("k", "v"))
  let assert Ok(#(written, _)) = consensus.submit(leader(), 0, 1, request)
  should.equal(
    consensus.linearizable_read(written, 0, False, "k"),
    Error(consensus.ReadQuorumUnavailable),
  )
  should.equal(
    consensus.linearizable_read(written, 0, True, "k"),
    Ok(Some("v")),
  )
}

pub fn stale_read_index_is_rejected_test() {
  let request = command.CommandRequest("write", command.Put("k", "v"))
  let assert Ok(#(written, _)) = consensus.submit(leader(), 0, 1, request)
  should.equal(
    consensus.linearizable_read(written, -1, True, "k"),
    Error(consensus.ReadIndexUnavailable),
  )
}

pub fn lease_fences_old_holder_after_expiry_test() {
  let assert Ok(#(first, Some(consensus.Lease("db", "one", 1, 15)))) =
    consensus.lease(leader(), 0, 1, 10, consensus.Acquire("db", "one", 5))
  let #(logged, _) =
    raft.handle(
      first.raft,
      raft.AppendEntries(0, "a", 0, 0, [raft.LogEntry(0, "lease")], 0),
    )
  let advanced = consensus.State(..first, raft: logged)
  let assert Ok(#(second, Some(consensus.Lease("db", "two", 2, 26)))) =
    consensus.lease(advanced, 1, 1, 16, consensus.Acquire("db", "two", 10))
  should.equal(
    consensus.validate_fence(second, "db", 1),
    Error(consensus.StaleFence("db", 2, 1)),
  )
  should.equal(consensus.validate_fence(second, "db", 2), Ok(Nil))
}

pub fn lease_rejects_clock_regression_and_holder_races_test() {
  let assert Ok(#(held, Some(consensus.Lease("db", "one", 1, 15)))) =
    consensus.lease(leader(), 0, 1, 10, consensus.Acquire("db", "one", 5))
  should.equal(
    consensus.lease(held, 1, 1, 9, consensus.Renew("db", "one", 1, 5)),
    Error(consensus.InvalidClock(9, 10)),
  )
  should.equal(
    consensus.lease(held, 1, 1, 11, consensus.Renew("db", "two", 1, 5)),
    Error(consensus.LeaseHolderMismatch("db")),
  )
}

pub fn lease_acquire_requires_positive_ttl_test() {
  should.equal(
    consensus.lease(leader(), 0, 1, 0, consensus.Acquire("db", "one", 0)),
    Error(consensus.InvalidTtl),
  )
}
