//// # projection — supervised, checkpointed derived-state reference
////
//// This pure module models the durable projection contract. Delivery is
//// at-least-once; `apply` deduplicates offsets and commits its checkpoint only
//// after the derived state has accepted the entry.

import aarondb/durable_log
import gleam/list
import gleam/option.{type Option, None, Some}

pub type ProjectionState {
  Running
  Paused
  Replaying
  Failed
  Rebuilding
  Stale
}

pub type Failure {
  Retryable(reason: String)
  Permanent(reason: String)
  SourceUnavailable(reason: String)
  CorruptSource(offset: Int)
  PressureExceeded(limit: Int)
}

pub type Metrics {
  Metrics(applied: Int, duplicates: Int, restarts: Int, rebuilds: Int)
}

pub type Status {
  Status(
    state: ProjectionState,
    last_applied_offset: Int,
    lag: Int,
    failure: Option(Failure),
    generation: Int,
    metrics: Metrics,
  )
}

pub type Projection {
  Projection(
    name: String,
    generation: Int,
    max_batch: Int,
    max_restarts: Int,
    state: ProjectionState,
    last_applied_offset: Int,
    applied_offsets: List(Int),
    values: List(String),
    failure: Option(Failure),
    metrics: Metrics,
  )
}

pub type ProjectionError {
  BoundedPressure(limit: Int)
  PermanentlyFailed(Failure)
  Source(durable_log.DurableLogError)
  Checkpoint(durable_log.DurableLogError)
}

pub fn new(name: String, max_batch: Int, max_restarts: Int) -> Projection {
  Projection(
    name,
    0,
    max_batch,
    max_restarts,
    Running,
    -1,
    [],
    [],
    None,
    Metrics(0, 0, 0, 0),
  )
}

pub fn status(
  projection: Projection,
  source: durable_log.DurableLog,
) -> Status {
  Status(
    projection.state,
    projection.last_applied_offset,
    max(0, source.next_offset - projection.last_applied_offset - 1),
    projection.failure,
    projection.generation,
    projection.metrics,
  )
}

/// Apply a bounded source tail, preserving atomic state/checkpoint ordering.
pub fn catch_up(
  projection: Projection,
  source: durable_log.DurableLog,
) -> Result(#(Projection, durable_log.DurableLog), ProjectionError) {
  case projection.state {
    Failed -> failed(projection)
    Rebuilding -> failed(projection)
    Paused -> Ok(#(projection, source))
    _ ->
      case durable_log.scan_after(source, projection.last_applied_offset) {
        Error(error) -> Error(Source(error))
        Ok(entries) ->
          case list.length(entries) > projection.max_batch {
            True -> Error(BoundedPressure(projection.max_batch))
            False -> apply_all(projection, source, entries)
          }
      }
  }
}

/// A retryable crash increments supervision state; exhaustion is permanent and visible.
pub fn restart(projection: Projection, reason: String) -> Projection {
  let Metrics(applied, duplicates, restarts, rebuilds) = projection.metrics
  let next_restarts = restarts + 1
  case next_restarts > projection.max_restarts {
    True ->
      Projection(
        ..projection,
        state: Failed,
        failure: Some(Permanent(reason)),
        metrics: Metrics(applied, duplicates, next_restarts, rebuilds),
      )
    False ->
      Projection(
        ..projection,
        state: Replaying,
        failure: Some(Retryable(reason)),
        metrics: Metrics(applied, duplicates, next_restarts, rebuilds),
      )
  }
}

pub fn resume(projection: Projection) -> Projection {
  case projection.failure {
    Some(Retryable(_)) ->
      Projection(..projection, state: Running, failure: None)
    _ -> projection
  }
}

/// Rebuild creates an isolated next generation from a snapshot boundary then swaps it.
pub fn rebuild(
  projection: Projection,
  source: durable_log.DurableLog,
  snapshot: durable_log.Snapshot,
) -> Result(#(Projection, durable_log.DurableLog), ProjectionError) {
  let rebuilding = Projection(..projection, state: Rebuilding, failure: None)
  case durable_log.snapshot_then_tail(source, snapshot.offset) {
    Error(error) -> Error(Source(error))
    Ok(#(_verified, tail)) -> {
      let fresh =
        Projection(
          ..rebuilding,
          generation: projection.generation + 1,
          last_applied_offset: snapshot.offset,
          applied_offsets: [],
          values: [],
        )
      case apply_all(fresh, source, tail) {
        Ok(#(rebuilt, log)) -> {
          let Metrics(applied, duplicates, restarts, rebuilds) = rebuilt.metrics
          Ok(#(
            Projection(
              ..rebuilt,
              state: Running,
              metrics: Metrics(applied, duplicates, restarts, rebuilds + 1),
            ),
            log,
          ))
        }
        Error(error) -> Error(error)
      }
    }
  }
}

pub fn values(projection: Projection) -> List(String) {
  projection.values
}

fn apply_all(
  projection: Projection,
  source: durable_log.DurableLog,
  entries: List(durable_log.Entry),
) -> Result(#(Projection, durable_log.DurableLog), ProjectionError) {
  case entries {
    [] -> Ok(#(Projection(..projection, state: Running, failure: None), source))
    [entry, ..rest] -> {
      let next = apply(projection, entry)
      let checkpoint =
        durable_log.ProjectionCheckpoint(
          projection.name,
          next.last_applied_offset,
        )
      case
        durable_log.commit_checkpoint(source, checkpoint, durable_log.NoFault)
      {
        Error(error) -> Error(Checkpoint(error))
        Ok(committed) -> apply_all(next, committed, rest)
      }
    }
  }
}

fn apply(projection: Projection, entry: durable_log.Entry) -> Projection {
  let Metrics(applied, duplicates, restarts, rebuilds) = projection.metrics
  case contains(projection.applied_offsets, entry.offset) {
    True ->
      Projection(
        ..projection,
        metrics: Metrics(applied, duplicates + 1, restarts, rebuilds),
      )
    False ->
      Projection(
        ..projection,
        last_applied_offset: entry.offset,
        applied_offsets: list.append(projection.applied_offsets, [entry.offset]),
        values: list.append(projection.values, [entry.payload]),
        metrics: Metrics(applied + 1, duplicates, restarts, rebuilds),
      )
  }
}

fn failed(
  projection: Projection,
) -> Result(#(Projection, durable_log.DurableLog), ProjectionError) {
  case projection.failure {
    Some(failure) -> Error(PermanentlyFailed(failure))
    None -> Error(PermanentlyFailed(Permanent("failed without reason")))
  }
}

fn contains(offsets: List(Int), needle: Int) -> Bool {
  list.any(offsets, fn(offset) { offset == needle })
}

fn max(left: Int, right: Int) -> Int {
  case left > right {
    True -> left
    False -> right
  }
}
