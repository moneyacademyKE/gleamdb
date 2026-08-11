import aarondb/changefeed
import aarondb/cluster_data_plane as plane
import aarondb/command
import aarondb/consensus
import aarondb/operations
import aarondb/projection_index
import gleam/list
import gleam/option.{Some}
import gleeunit/should

pub fn committed_writes_are_visible_once_and_linearizable_test() {
  let state = plane.new("a", "events")
  let request = command.CommandRequest("write-1", command.Put("k", "v"))
  let assert Ok(#(state, command.Written("k", "v"))) =
    plane.write(state, 0, 1, request)
  let assert Ok(#(state, command.Written("k", "v"))) =
    plane.write(state, 0, 1, request)
  should.equal(plane.read(state, 0, True, "k"), Ok(Some("v")))
  should.equal(
    plane.read(state, 0, False, "k"),
    Error(plane.ReadRejected(consensus.ReadQuorumUnavailable)),
  )
}

pub fn failed_quorum_does_not_publish_events_test() {
  let state = plane.new("a", "events")
  let request = command.CommandRequest("write-1", command.Put("k", "v"))
  should.equal(
    plane.write(state, 0, 0, request),
    Error(plane.WriteRejected(consensus.QuorumUnavailable)),
  )
  let assert Ok(feed) = plane.resume_feed(state, -1, 1)
  let assert Ok(#(_, entries)) = changefeed.pull(feed)
  should.equal(entries, [])
}

pub fn stale_fences_are_rejected_after_reacquire_test() {
  let state = plane.new("a", "events")
  let assert Ok(#(state, Some(consensus.Lease("db", "one", 1, 5)))) =
    plane.lease(state, 0, 1, 0, consensus.Acquire("db", "one", 5))
  let assert Ok(#(state, Some(consensus.Lease("db", "two", 2, 16)))) =
    plane.lease(state, 1, 1, 6, consensus.Acquire("db", "two", 10))
  should.equal(
    plane.validate_fence(state, "db", 1),
    Error(plane.LeaseRejected(consensus.StaleFence("db", 2, 1))),
  )
  should.equal(plane.validate_fence(state, "db", 2), Ok(Nil))
}

pub fn feeds_resume_and_indexes_rebuild_only_from_committed_events_test() {
  let state = plane.new("a", "events")
  let assert Ok(#(state, _)) =
    plane.write(
      state,
      0,
      1,
      command.CommandRequest("one", command.Put("a", "1")),
    )
  let assert Ok(#(state, _)) =
    plane.write(
      state,
      1,
      1,
      command.CommandRequest("two", command.Put("b", "2")),
    )
  let assert Ok(feed) = plane.resume_feed(state, -1, 1)
  let assert Ok(#(feed, first)) = changefeed.pull(feed)
  should.equal(list.length(first), 1)
  let acknowledged = changefeed.acknowledge(feed, 0)
  let assert Ok(resumed) =
    plane.resume_feed(state, changefeed.cursor(acknowledged), 1)
  let assert Ok(#(_, tail)) = changefeed.pull(resumed)
  should.equal(list.length(tail), 1)
  let assert Ok(caught_up) = plane.catch_up(state)
  let assert Ok(_) = plane.query_index(caught_up)
  let assert Ok(rebuilt) = plane.rebuild_index(caught_up, 2)
  should.equal(rebuilt.index.schema_version, 2)
}

pub fn degraded_status_and_indexes_refuse_to_lie_test() {
  let state = plane.new("a", "events")
  let report = plane.status(state, 0, -1)
  should.equal(report.quorum, operations.Unavailable)
  let degraded =
    plane.State(
      ..state,
      index: projection_index.degrade(state.index, "rebuild stalled"),
    )
  should.equal(
    plane.query_index(degraded),
    Error(
      plane.IndexRejected(
        projection_index.NotQueryable(projection_index.Degraded(
          "rebuild stalled",
        )),
      ),
    ),
  )
}
