import aarondb/shared/state.{type QueryContext}
import gleam/dict
import gleam/int
import gleam/list
import gleam/result

/// Analyzes the recent query history to identify the most heavily 
/// requested attributes that might benefit from predictive prefetching.
pub fn analyze_history(history: List(QueryContext)) -> List(String) {
  // Simple heuristic: Count attribute occurrences in the history buffer.
  let counts =
    list.fold(history, dict.new(), fn(acc, ctx) {
      list.fold(ctx.attributes, acc, fn(a, attr) {
        let count = dict.get(a, attr) |> result.unwrap(0)
        dict.insert(a, attr, count + 1)
      })
    })

  // Return attributes requested 2 or more times in the recent window, 
  // sorted by highest frequency first.
  dict.to_list(counts)
  |> list.sort(fn(a, b) { int.compare(b.1, a.1) })
  |> list.filter(fn(pair) { pair.1 >= 2 })
  |> list.map(fn(pair) { pair.0 })
}
