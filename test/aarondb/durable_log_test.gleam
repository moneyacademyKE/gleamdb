import aarondb/durable_log
import gleam/option.{None, Some}
import gleeunit/should

pub fn offsets_are_monotonic_and_append_retries_are_idempotent_test() {
  let log = durable_log.new("orders")
  let #(log, first) = durable_log.append(log, "first", "request-1")
  let #(_log, retry) =
    durable_log.append(log, "different retry payload", "request-1")
  should.equal(first.offset, 0)
  should.equal(retry, first)
}

pub fn scan_returns_only_entries_after_cursor_in_offset_order_test() {
  let log = durable_log.new("orders")
  let #(log, _) = durable_log.append(log, "one", "1")
  let #(log, _) = durable_log.append(log, "two", "2")
  let #(log, _) = durable_log.append(log, "three", "3")
  case durable_log.scan_after(log, 0) {
    Ok(entries) -> should.equal(offsets(entries), [1, 2])
    Error(_) -> should.fail()
  }
}

pub fn retention_expires_old_cursors_only_after_verified_snapshot_test() {
  let log = durable_log.new("orders")
  let #(log, _) = durable_log.append(log, "one", "1")
  let #(log, _) = durable_log.append(log, "two", "2")
  let assert Ok(log) = durable_log.snapshot(log, 1, "projection state")
  let assert Ok(log) = durable_log.retain_after(log, 1)
  should.equal(
    durable_log.scan_after(log, 0),
    Error(durable_log.CursorExpired(0, 2)),
  )
  should.equal(result_offsets(durable_log.scan_after(log, 1)), Ok([]))
}

pub fn snapshot_then_tail_bootstrap_uses_verified_snapshot_and_tail_test() {
  let log = durable_log.new("orders")
  let #(log, _) = durable_log.append(log, "one", "1")
  let #(log, _) = durable_log.append(log, "two", "2")
  let assert Ok(log) = durable_log.snapshot(log, 1, "state through two")
  let #(log, _) = durable_log.append(log, "three", "3")
  case durable_log.snapshot_then_tail(log, 2) {
    Ok(#(snapshot, tail)) -> {
      should.equal(snapshot.offset, 1)
      should.equal(offsets(tail), [2])
    }
    Error(_) -> should.fail()
  }
}

pub fn corruption_fails_the_scan_instead_of_silently_skipping_test() {
  let log = durable_log.new("orders")
  let #(log, _) = durable_log.append(log, "one", "1")
  let corrupted = durable_log.corrupt_entry(log, 0)
  should.equal(
    durable_log.scan_after(corrupted, -1),
    Error(durable_log.CorruptEntry(0)),
  )
}

pub fn fault_injected_checkpoint_does_not_advance_then_successfully_commits_test() {
  let log = durable_log.new("orders")
  let checkpoint = durable_log.ProjectionCheckpoint("search", 4)
  should.equal(
    durable_log.commit_checkpoint(log, checkpoint, durable_log.FailBeforeCommit),
    Error(durable_log.CheckpointFaultInjected),
  )
  should.equal(durable_log.checkpoint(log, "search"), None)
  let assert Ok(committed) =
    durable_log.commit_checkpoint(log, checkpoint, durable_log.NoFault)
  should.equal(durable_log.checkpoint(committed, "search"), Some(checkpoint))
}

fn offsets(entries: List(durable_log.Entry)) -> List(Int) {
  case entries {
    [] -> []
    [entry, ..rest] -> [entry.offset, ..offsets(rest)]
  }
}

fn result_offsets(
  result: Result(List(durable_log.Entry), durable_log.DurableLogError),
) -> Result(List(Int), durable_log.DurableLogError) {
  case result {
    Ok(entries) -> Ok(offsets(entries))
    Error(error) -> Error(error)
  }
}
