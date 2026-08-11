import aarondb/fact
import aarondb/vector
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/list
import gleam/order.{type Order, Eq}

/// A deterministic ordering for scored entities: score descending, then entity
/// ID ascending. This makes ties mechanically comparable.
pub fn compare_scored_entities(
  a: #(fact.EntityId, Float),
  b: #(fact.EntityId, Float),
) -> Order {
  case float.compare(b.1, a.1) {
    Eq -> int.compare(fact.eid_to_integer(a.0), fact.eid_to_integer(b.0))
    other -> other
  }
}

/// Score every vector in a finite corpus and return the deterministic top-k.
/// Inputs must already be validated and dimension-compatible by the caller.
pub fn search(
  nodes: Dict(fact.EntityId, List(Float)),
  query: List(Float),
  threshold: Float,
  k: Int,
) -> List(#(fact.EntityId, Float)) {
  let query = vector.normalize(query)
  nodes
  |> dict.to_list()
  |> list.map(fn(entry) { #(entry.0, vector.dot_product(query, entry.1)) })
  |> list.filter(fn(result) { result.1 >=. threshold })
  |> list.sort(compare_scored_entities)
  |> list.take(k)
}
