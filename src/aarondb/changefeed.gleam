//// # changefeed — bounded, resumable, ordered delivery over a durable source
////
//// The contract is deliberately at-least-once. Consumers persist their own
//// idempotent effect and advance their durable projection checkpoint in the
//// same storage transaction. A cursor identifies the last acknowledged offset.

import aarondb/durable_log

pub type Credit =
  Int

pub type Cursor =
  durable_log.Offset

pub type Changefeed {
  Changefeed(
    source: durable_log.DurableLog,
    cursor: Cursor,
    available_credit: Credit,
  )
}

pub type Bootstrap {
  Bootstrap(
    snapshot: durable_log.Snapshot,
    tail: List(durable_log.Entry),
    cursor: Cursor,
  )
}

pub type ChangefeedError {
  InvalidCredit(Credit)
  Source(durable_log.DurableLogError)
}

/// Open a resumable feed. `cursor` is the last durably acknowledged offset.
pub fn resume(
  source: durable_log.DurableLog,
  cursor: Cursor,
  credit: Credit,
) -> Result(Changefeed, ChangefeedError) {
  case credit < 0 {
    True -> Error(InvalidCredit(credit))
    False ->
      case durable_log.scan_after(source, cursor) {
        Ok(_) -> Ok(Changefeed(source, cursor, credit))
        Error(error) -> Error(Source(error))
      }
  }
}

/// Establish a consistent snapshot boundary before opening the tail feed.
/// The returned cursor is the snapshot position; callers must resume from it.
pub fn bootstrap(
  source: durable_log.DurableLog,
  through: Cursor,
) -> Result(Bootstrap, ChangefeedError) {
  case durable_log.snapshot_then_tail(source, through) {
    Ok(#(snapshot, tail)) -> Ok(Bootstrap(snapshot, tail, snapshot.offset))
    Error(error) -> Error(Source(error))
  }
}

/// Add bounded delivery credits. Zero is valid and deliberately changes nothing.
pub fn grant(
  feed: Changefeed,
  credit: Credit,
) -> Result(Changefeed, ChangefeedError) {
  case credit < 0 {
    True -> Error(InvalidCredit(credit))
    False ->
      Ok(Changefeed(..feed, available_credit: feed.available_credit + credit))
  }
}

/// Pull at most the currently granted credit. Delivery does not advance the
/// cursor: only `acknowledge` does, so an interrupted consumer can see a retry.
pub fn pull(
  feed: Changefeed,
) -> Result(#(Changefeed, List(durable_log.Entry)), ChangefeedError) {
  case durable_log.scan_after(feed.source, feed.cursor) {
    Error(error) -> Error(Source(error))
    Ok(entries) -> {
      let delivered = take(entries, feed.available_credit)
      Ok(#(Changefeed(..feed, available_credit: 0), delivered))
    }
  }
}

/// Advance only to an offset that was committed by the source. Acknowledge is
/// idempotent for older offsets and never makes an uncommitted event observable.
pub fn acknowledge(feed: Changefeed, offset: Cursor) -> Changefeed {
  case offset > feed.cursor && offset < feed.source.next_offset {
    True -> Changefeed(..feed, cursor: offset)
    False -> feed
  }
}

pub fn cursor(feed: Changefeed) -> Cursor {
  feed.cursor
}

pub fn credits(feed: Changefeed) -> Credit {
  feed.available_credit
}

fn take(
  entries: List(durable_log.Entry),
  count: Int,
) -> List(durable_log.Entry) {
  case entries, count > 0 {
    _, False -> []
    [], _ -> []
    [entry, ..rest], True -> [entry, ..take(rest, count - 1)]
  }
}
