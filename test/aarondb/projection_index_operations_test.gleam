import aarondb/consensus
import aarondb/durable_log
import aarondb/identity
import aarondb/operations
import aarondb/projection
import aarondb/projection_index
import aarondb/raft_runtime as raft
import gleam/option.{Some}
import gleeunit/should

pub fn snapshot_tail_equivalence_and_safe_swap_test() {
  let assert Ok(index) = projection_index.new(1)
  let assert Ok(index) = projection_index.apply(index, 0, "a")
  let assert Ok(index) = projection_index.apply(index, 1, "b")
  let assert Ok(rebuilt) = projection_index.begin_rebuild(index, 2)
  let assert Ok(rebuilt) = projection_index.apply(rebuilt, 0, "a")
  let assert Ok(rebuilt) = projection_index.apply(rebuilt, 1, "b")
  let assert Ok(swapped) = projection_index.swap(index, rebuilt, 1)
  should.equal(projection_index.query(swapped), Ok(["a", "b"]))
  should.equal(swapped.schema_version, 2)
}

pub fn partial_rebuild_is_not_queryable_test() {
  let assert Ok(index) = projection_index.new(1)
  let assert Ok(rebuilt) = projection_index.begin_rebuild(index, 2)
  let assert Ok(rebuilt) = projection_index.apply(rebuilt, 0, "a")
  should.equal(
    projection_index.swap(index, rebuilt, 1),
    Error(projection_index.OffsetGap(1, 0)),
  )
  should.equal(
    projection_index.query(rebuilt),
    Error(projection_index.NotQueryable(projection_index.Rebuilding)),
  )
}

pub fn index_gap_and_degradation_are_visible_test() {
  let assert Ok(index) = projection_index.new(1)
  should.equal(
    projection_index.apply(index, 1, "missing-zero"),
    Error(projection_index.OffsetGap(0, 1)),
  )
  let degraded = projection_index.degrade(index, "source stalled")
  should.equal(
    projection_index.failure_reason(degraded),
    Some("source stalled"),
  )
  should.equal(
    projection_index.query(degraded),
    Error(
      projection_index.NotQueryable(projection_index.Degraded("source stalled")),
    ),
  )
}

pub fn operations_status_reports_health_lag_and_alarms_test() {
  let raft_state =
    raft.new("a", [raft.Voter("a"), raft.Voter("b"), raft.Voter("c")])
  let source = durable_log.new("events")
  let projection = projection.new("search", 1, 1)
  let projection_status = projection.status(projection, source)
  let assert Ok(index) = projection_index.new(1)
  let recovery =
    identity.clean_recovery() |> identity.force_recovery("lost disk")
  let report =
    operations.status(
      raft_state,
      3,
      0,
      -1,
      projection_status,
      projection_index.degrade(index, "rebuilding"),
      consensus.new(raft_state),
      recovery,
    )
  should.equal(report.quorum, operations.Unavailable)
  should.equal(report.replication_lag, 0)
  should.equal(report.alarms, [
    operations.QuorumLost,
    operations.IndexUnavailable(projection_index.Degraded("rebuilding")),
    operations.UnsafeRecovery(identity.UnsafeRecoveryAcknowledged("lost disk")),
  ])
}

pub fn operations_status_tracks_projection_failure_test() {
  let raft_state = raft.new("a", [raft.Voter("a")])
  let projection =
    projection.new("search", 1, 0) |> projection.restart("bad payload")
  let assert Ok(index) = projection_index.new(1)
  let assert Ok(index) = projection_index.apply(index, 0, "seed")
  let report =
    operations.status(
      raft_state,
      1,
      1,
      -1,
      projection.status(projection, durable_log.new("events")),
      index,
      consensus.new(raft_state),
      identity.clean_recovery(),
    )
  should.equal(report.alarms, [
    operations.ProjectionFailed(projection.Permanent("bad payload")),
  ])
}
