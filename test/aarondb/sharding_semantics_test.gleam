import aarondb/fact.{EntityId, Int, Uid}
import aarondb/sharding/semantics
import aarondb/shared/query_types
import gleam/dict
import gleam/option.{None, Some}
import gleeunit/should

pub fn routing_fails_explicitly_without_virtual_nodes_test() {
  semantics.group_facts([#(Uid(EntityId(1)), "status", Int(1))], dict.new(), [])
  |> should.equal(Error("cannot route fact: shard map has no virtual nodes"))
}

pub fn partial_reduction_preserves_failure_data_test() {
  let result =
    query_types.QueryResult(
      rows: [],
      metadata: query_types.QueryMetadata(
        tx_id: Some(4),
        valid_time: None,
        execution_time_ms: 12,
        index_hits: 3,
        plan: "scan",
        shard_id: None,
        aggregates: dict.new(),
      ),
      updated_columnar_store: None,
    )

  semantics.reduce_query_replies([
    semantics.QuerySucceeded(1, result),
    semantics.QueryUnavailable(2),
    semantics.QueryTimedOut(3, 15_000),
  ])
  |> should.equal(semantics.Partial(result, [2], [#(3, 15_000)]))
}

pub fn retry_and_deadline_decisions_are_explicit_test() {
  semantics.retry_decision(0, 2, False, 5000)
  |> should.equal(semantics.RetryNow(1))
  semantics.retry_decision(2, 2, False, 5000)
  |> should.equal(semantics.RetryExhausted(2))
  semantics.retry_decision(0, 2, True, 5000)
  |> should.equal(semantics.DeadlineElapsed(5000))
}
