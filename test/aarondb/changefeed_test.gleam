import aarondb/changefeed
import aarondb/durable_log
import gleeunit/should

pub fn resume_delivers_ordered_entries_only_after_a_durable_ack_test() {
  let log = log_with_three_entries()
  let assert Ok(feed) = changefeed.resume(log, -1, 2)
  let assert Ok(#(after_pull, first_batch)) = changefeed.pull(feed)
  should.equal(offsets(first_batch), [0, 1])
  should.equal(changefeed.cursor(after_pull), -1)

  let assert Ok(retry_ready) = changefeed.grant(after_pull, 2)
  let assert Ok(#(_retry_feed, retry_batch)) = changefeed.pull(retry_ready)
  should.equal(offsets(retry_batch), [0, 1])
}

pub fn acknowledged_cursor_resumes_after_restart_test() {
  let log = log_with_three_entries()
  let assert Ok(feed) = changefeed.resume(log, -1, 3)
  let acknowledged = changefeed.acknowledge(feed, 1)
  let assert Ok(restarted) =
    changefeed.resume(log, changefeed.cursor(acknowledged), 1)
  let assert Ok(#(_feed, entries)) = changefeed.pull(restarted)
  should.equal(offsets(entries), [2])
}

pub fn slow_consumer_credit_bounds_delivery_test() {
  let log = log_with_three_entries()
  let assert Ok(feed) = changefeed.resume(log, -1, 0)
  let assert Ok(#(feed, none)) = changefeed.pull(feed)
  should.equal(none, [])
  let assert Ok(feed) = changefeed.grant(feed, 1)
  let assert Ok(#(_feed, one)) = changefeed.pull(feed)
  should.equal(offsets(one), [0])
}

pub fn expired_resume_cursor_fails_test() {
  let log = log_with_three_entries()
  let assert Ok(log) = durable_log.snapshot(log, 1, "state")
  let assert Ok(retained) = durable_log.retain_after(log, 1)
  should.equal(
    changefeed.resume(retained, 0, 1),
    Error(changefeed.Source(durable_log.CursorExpired(0, 2))),
  )
}

pub fn snapshot_then_tail_has_a_single_replay_boundary_test() {
  let log = log_with_three_entries()
  let assert Ok(log) = durable_log.snapshot(log, 1, "state through offset 1")
  let assert Ok(bootstrap) = changefeed.bootstrap(log, 2)
  should.equal(bootstrap.snapshot.offset, 1)
  should.equal(offsets(bootstrap.tail), [2])
  let assert Ok(feed) = changefeed.resume(log, bootstrap.cursor, 1)
  let assert Ok(#(_feed, live)) = changefeed.pull(feed)
  should.equal(offsets(live), [2])
}

pub fn invalid_credit_is_rejected_test() {
  should.equal(
    changefeed.resume(durable_log.new("orders"), -1, -1),
    Error(changefeed.InvalidCredit(-1)),
  )
}

fn log_with_three_entries() -> durable_log.DurableLog {
  let log = durable_log.new("orders")
  let #(log, _) = durable_log.append(log, "one", "1")
  let #(log, _) = durable_log.append(log, "two", "2")
  let #(log, _) = durable_log.append(log, "three", "3")
  log
}

fn offsets(entries: List(durable_log.Entry)) -> List(Int) {
  case entries {
    [] -> []
    [entry, ..rest] -> [entry.offset, ..offsets(rest)]
  }
}
