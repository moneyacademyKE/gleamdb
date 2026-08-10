import aarondb/raft_runtime as raft
import gleam/option.{Some}
import gleeunit/should

fn cluster() -> raft.State {
  raft.new("a", [raft.Voter("a"), raft.Voter("b"), raft.Voter("c")])
}

pub fn election_requires_voter_and_persists_vote_test() {
  let candidate = raft.start_election(cluster())
  should.equal(candidate.role, raft.Candidate)
  should.equal(candidate.hard.term, 1)
  should.equal(candidate.hard.voted_for, Some("a"))
}

pub fn stale_term_is_rejected_test() {
  let state = raft.start_election(cluster())
  let #(_, reply) = raft.handle(state, raft.RequestVote(0, "b", -1, 0))
  should.equal(reply, raft.StaleTerm(1))
}

pub fn replication_repairs_divergent_suffix_test() {
  let state = raft.new("b", [raft.Voter("a"), raft.Voter("b")])
  let #(first, _) =
    raft.handle(
      state,
      raft.AppendEntries(1, "a", -1, 0, [raft.LogEntry(1, "one")], -1),
    )
  let #(repaired, reply) =
    raft.handle(
      first,
      raft.AppendEntries(2, "a", -1, 0, [raft.LogEntry(2, "two")], 0),
    )
  should.equal(reply, raft.AppendAccepted(2, 0))
  should.equal(raft.last_term(repaired), 2)
  should.equal(repaired.hard.commit_index, 0)
}

pub fn quorum_commit_requires_current_term_majority_test() {
  let leader = raft.bootstrap_leader(raft.new("a", [raft.Voter("a")]))
  let #(replicated, _) =
    raft.handle(
      leader,
      raft.AppendEntries(0, "a", -1, 0, [raft.LogEntry(0, "x")], -1),
    )
  let committed = raft.commit_quorum(replicated, 0, 1)
  should.equal(committed.hard.commit_index, 0)
  let denied = raft.commit_quorum(replicated, 0, 0)
  should.equal(denied.hard.commit_index, -1)
}

pub fn leader_failover_steps_down_on_newer_append_test() {
  let leader = raft.bootstrap_leader(raft.new("a", [raft.Voter("a")]))
  let #(follower, _) =
    raft.handle(leader, raft.AppendEntries(2, "b", -1, 0, [], -1))
  should.equal(follower.role, raft.Follower)
  should.equal(follower.leader, Some("b"))
}

pub fn snapshot_is_committed_and_monotonic_test() {
  let leader = raft.bootstrap_leader(raft.new("a", [raft.Voter("a")]))
  let #(logged, _) =
    raft.handle(
      leader,
      raft.AppendEntries(0, "a", -1, 0, [raft.LogEntry(0, "x")], -1),
    )
  let committed = raft.commit_quorum(logged, 0, 1)
  let assert Ok(compacted) = raft.compact(committed, 0, "state")
  should.equal(compacted.snapshot, Some(raft.Snapshot(0, 0, "state")))
}

pub fn read_index_never_exceeds_commit_test() {
  let state = raft.new("b", [raft.Voter("a"), raft.Voter("b")])
  let #(follower, _) =
    raft.handle(state, raft.AppendEntries(1, "a", -1, 0, [], -1))
  let #(_, reply) = raft.handle(follower, raft.ReadIndex(1, "a", 999))
  should.equal(reply, raft.ReadIndexAccepted(1, -1))
}

pub fn learner_promotion_is_explicit_test() {
  let state = raft.add_learner(cluster(), "d")
  should.equal(raft.quorum(state), 2)
  let promoted = raft.promote_voter(state, "d")
  should.equal(raft.quorum(promoted), 3)
}

pub fn installed_snapshot_recovers_commit_and_apply_test() {
  let state = raft.new("b", [raft.Voter("a"), raft.Voter("b")])
  let #(recovered, reply) =
    raft.handle(
      state,
      raft.InstallSnapshot(3, "a", raft.Snapshot(7, 3, "image")),
    )
  should.equal(reply, raft.SnapshotAccepted(3, 7))
  should.equal(recovered.hard.commit_index, 7)
  should.equal(recovered.last_applied, 7)
}

pub fn quorum_loss_cannot_commit_test() {
  let leader = raft.bootstrap_leader(raft.new("a", [raft.Voter("a")]))
  let #(logged, _) =
    raft.handle(
      leader,
      raft.AppendEntries(0, "a", -1, 0, [raft.LogEntry(0, "x")], -1),
    )
  should.equal(raft.commit_quorum(logged, 0, 0).hard.commit_index, -1)
}
