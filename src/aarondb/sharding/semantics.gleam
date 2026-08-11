import aarondb/fact
import aarondb/shared/query_types
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

/// A shard outcome is data: callers must decide whether a partial response is
/// acceptable instead of silently treating a timeout as an empty result.
pub type QueryReply {
  QuerySucceeded(shard_id: Int, result: query_types.QueryResult)
  QueryUnavailable(shard_id: Int)
  QueryTimedOut(shard_id: Int, deadline_ms: Int)
}

pub type QueryReduction {
  Complete(query_types.QueryResult)
  Partial(
    result: query_types.QueryResult,
    unavailable: List(Int),
    timed_out: List(#(Int, Int)),
  )
}

pub type RetryDecision {
  RetryNow(attempt: Int)
  RetryExhausted(attempt: Int)
  DeadlineElapsed(deadline_ms: Int)
}

pub fn route(
  eid: fact.Eid,
  vnodes: Dict(Int, Int),
  sorted_hashes: List(Int),
) -> Option(Int) {
  let hash = case eid {
    fact.Uid(fact.EntityId(id)) -> fact.phash2(fact.Int(id))
    fact.Lookup(#(_, value)) -> fact.phash2(value)
  }
  let target =
    list.find(sorted_hashes, fn(vnode_hash) { vnode_hash >= hash })
    |> result.lazy_unwrap(fn() { list.first(sorted_hashes) |> result.unwrap(0) })
  case dict.get(vnodes, target) {
    Ok(shard_id) -> Some(shard_id)
    Error(_) -> None
  }
}

pub fn group_facts(
  facts: List(fact.Fact),
  vnodes: Dict(Int, Int),
  sorted_hashes: List(Int),
) -> Result(Dict(Int, List(fact.Fact)), String) {
  list.fold(facts, Ok(dict.new()), fn(grouped, item) {
    use grouped <- result.try(grouped)
    case route(item.0, vnodes, sorted_hashes) {
      Some(shard_id) -> {
        let assigned = dict.get(grouped, shard_id) |> result.unwrap([])
        Ok(dict.insert(grouped, shard_id, [item, ..assigned]))
      }
      None -> Error("cannot route fact: shard map has no virtual nodes")
    }
  })
}

pub fn reduce_query_replies(replies: List(QueryReply)) -> QueryReduction {
  let initial = empty_result()
  let #(result, unavailable, timed_out) =
    list.fold(replies, #(initial, [], []), fn(acc, reply) {
      let #(current, missing, expired) = acc
      case reply {
        QuerySucceeded(_, next) -> #(merge(current, next), missing, expired)
        QueryUnavailable(shard_id) -> #(current, [shard_id, ..missing], expired)
        QueryTimedOut(shard_id, deadline_ms) -> #(current, missing, [
          #(shard_id, deadline_ms),
          ..expired
        ])
      }
    })
  case unavailable, timed_out {
    [], [] -> Complete(result)
    _, _ -> Partial(result, list.reverse(unavailable), list.reverse(timed_out))
  }
}

pub fn retry_decision(
  attempt: Int,
  max_attempts: Int,
  deadline_elapsed: Bool,
  deadline_ms: Int,
) -> RetryDecision {
  case deadline_elapsed {
    True -> DeadlineElapsed(deadline_ms)
    False ->
      case attempt < max_attempts {
        True -> RetryNow(attempt + 1)
        False -> RetryExhausted(attempt)
      }
  }
}

fn empty_result() -> query_types.QueryResult {
  query_types.QueryResult(
    rows: [],
    metadata: query_types.QueryMetadata(
      tx_id: None,
      valid_time: None,
      execution_time_ms: 0,
      index_hits: 0,
      plan: "",
      shard_id: None,
      aggregates: dict.new(),
    ),
    updated_columnar_store: None,
  )
}

fn merge(
  left: query_types.QueryResult,
  right: query_types.QueryResult,
) -> query_types.QueryResult {
  query_types.QueryResult(
    rows: list.append(left.rows, right.rows),
    metadata: query_types.QueryMetadata(
      tx_id: maximum(left.metadata.tx_id, right.metadata.tx_id),
      valid_time: maximum(left.metadata.valid_time, right.metadata.valid_time),
      execution_time_ms: left.metadata.execution_time_ms
        + right.metadata.execution_time_ms,
      index_hits: left.metadata.index_hits + right.metadata.index_hits,
      plan: case left.metadata.plan {
        "" -> right.metadata.plan
        plan -> plan
      },
      shard_id: None,
      aggregates: dict.merge(
        left.metadata.aggregates,
        right.metadata.aggregates,
      ),
    ),
    updated_columnar_store: None,
  )
}

fn maximum(left: Option(Int), right: Option(Int)) -> Option(Int) {
  case left, right {
    Some(a), Some(b) -> Some(int.max(a, b))
    Some(_), None -> left
    None, Some(_) -> right
    None, None -> None
  }
}
