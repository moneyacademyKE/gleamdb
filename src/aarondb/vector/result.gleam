import aarondb/fact
import gleam/float
import gleam/int
import gleam/order.{type Order, Eq}

/// An entity ID paired with its cosine-similarity score.
pub type SearchResult {
  SearchResult(entity: fact.EntityId, score: Float)
}

/// Deterministic descending-score ordering for vector results.
///
/// Equal scores are resolved by ascending entity ID, so exact search, HNSW
/// traversal, benchmarks, and tests share one mechanically comparable order.
pub fn compare_search_results(a: SearchResult, b: SearchResult) -> Order {
  case float.compare(b.score, a.score) {
    Eq ->
      int.compare(fact.eid_to_integer(a.entity), fact.eid_to_integer(b.entity))
    other -> other
  }
}
