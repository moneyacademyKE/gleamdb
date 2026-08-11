import aarondb/durable_log
import aarondb/projection as projections
import gleam/int
import gleam/option.{Some}
import gleeunit/should

pub fn applies_entries_and_atomically_advances_checkpoint_test() {
  let source = source_with(2)
  let projection = projections.new("search", 2, 1)
  let assert Ok(#(applied, committed)) =
    projections.catch_up(projection, source)
  should.equal(projections.values(applied), ["event-0", "event-1"])
  should.equal(applied.last_applied_offset, 1)
  should.equal(
    durable_log.checkpoint(committed, "search"),
    Some(durable_log.ProjectionCheckpoint("search", 1)),
  )
}

pub fn pressure_is_bounded_without_advancing_checkpoint_test() {
  let source = source_with(2)
  let projection = projections.new("search", 1, 1)
  should.equal(
    projections.catch_up(projection, source),
    Error(projections.BoundedPressure(1)),
  )
}

pub fn restart_is_bounded_and_permanent_failure_remains_observable_test() {
  let projection = projections.new("search", 1, 1)
  let retrying = projections.restart(projection, "temporary")
  should.equal(
    projections.status(retrying, source_with(0)).state,
    projections.Replaying,
  )
  let failed = projections.restart(retrying, "still broken")
  should.equal(
    projections.status(failed, source_with(0)).state,
    projections.Failed,
  )
  should.equal(
    projections.status(failed, source_with(0)).failure,
    Some(projections.Permanent("still broken")),
  )
  should.equal(
    projections.catch_up(failed, source_with(0)),
    Error(projections.PermanentlyFailed(projections.Permanent("still broken"))),
  )
}

pub fn retryable_restart_replays_from_durable_checkpoint_test() {
  let source = source_with(2)
  let projection = projections.new("search", 2, 2)
  let assert Ok(#(applied, _)) = projections.catch_up(projection, source)
  let restarted = projections.restart(applied, "crash") |> projections.resume
  let assert Ok(#(replayed, _)) = projections.catch_up(restarted, source)
  should.equal(projections.values(replayed), ["event-0", "event-1"])
  should.equal(replayed.metrics.applied, 2)
}

pub fn rebuild_swaps_to_next_generation_from_snapshot_and_tail_test() {
  let source = source_with(3)
  let assert Ok(source) = durable_log.snapshot(source, 1, "state through 1")
  let projection = projections.new("search", 2, 1)
  let snapshot =
    durable_log.Snapshot(1, "state through 1", "19:state through 1")
  let assert Ok(#(rebuilt, committed)) =
    projections.rebuild(projection, source, snapshot)
  should.equal(rebuilt.generation, 1)
  should.equal(projections.values(rebuilt), ["event-2"])
  should.equal(rebuilt.metrics.rebuilds, 1)
  should.equal(
    durable_log.checkpoint(committed, "search"),
    Some(durable_log.ProjectionCheckpoint("search", 2)),
  )
}

pub fn status_reports_lag_and_metrics_test() {
  let source = source_with(3)
  let projection = projections.new("search", 1, 1)
  let status = projections.status(projection, source)
  should.equal(status.lag, 3)
  should.equal(status.metrics.applied, 0)
  should.equal(status.state, projections.Running)
}

fn source_with(count: Int) -> durable_log.DurableLog {
  add(durable_log.new("orders"), 0, count)
}

fn add(
  source: durable_log.DurableLog,
  current: Int,
  count: Int,
) -> durable_log.DurableLog {
  case current == count {
    True -> source
    False -> {
      let #(next, _) =
        durable_log.append(
          source,
          "event-" <> int.to_string(current),
          int.to_string(current),
        )
      add(next, current + 1, count)
    }
  }
}
