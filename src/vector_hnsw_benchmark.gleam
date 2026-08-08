import aarondb/fact
import aarondb/vec_index
import gleam/int
import gleam/io
import gleam/list

/// Reproducible local evidence harness for the in-memory HNSW index.
///
/// Run with `gleam run -m vector_hnsw_benchmark`. It reports a machine-local
/// sample rather than claiming a portable latency SLA.
pub fn main() {
  let corpus_size = 1000
  let query_count = 100
  let corpus = corpus(corpus_size)
  let start_build = now()
  let index =
    list.fold(
      corpus,
      vec_index.new_with_config(vec_index.HnswConfig(
        max_neighbors: 32,
        search_budget: 1000,
        level_source: vec_index.DeterministicLevels([]),
      )),
      insert_point,
    )
  let build_ns = now() - start_build
  let query_ids =
    list.repeat(Nil, query_count)
    |> list.index_map(fn(_, offset) { offset + 1 })
  let hnsw_times =
    list.map(query_ids, fn(id) {
      let start = now()
      let _ = vec_index.search(index, vector_for(id * 7), -1.0, 10)
      nanoseconds_to_milliseconds(now() - start)
    })
  let exact_times =
    list.map(query_ids, fn(id) {
      let start = now()
      let assert Ok(_) =
        vec_index.exact_search(index, vector_for(id * 7), -1.0, 10)
      nanoseconds_to_milliseconds(now() - start)
    })

  io.println("corpus_size=" <> int.to_string(corpus_size))
  io.println("dimensions=8")
  io.println("query_count=" <> int.to_string(query_count))
  io.println(
    "build_ms=" <> int.to_string(nanoseconds_to_milliseconds(build_ns)),
  )
  print_latency("hnsw", hnsw_times)
  print_latency("exact", exact_times)
  io.println("recall_at_10=" <> recall_at_ten(index, query_ids))
}

fn corpus(size: Int) -> List(#(fact.EntityId, List(Float))) {
  list.repeat(Nil, size)
  |> list.index_map(fn(_, offset) {
    let id = offset + 1
    #(fact.EntityId(id), vector_for(id))
  })
}

fn insert_point(
  index: vec_index.VecIndex,
  point: #(fact.EntityId, List(Float)),
) -> vec_index.VecIndex {
  vec_index.insert(index, point.0, point.1)
}

fn vector_for(id: Int) -> List(Float) {
  [
    int.to_float({ id % 97 } + 1),
    int.to_float({ { id * 7 } % 89 } + 1),
    int.to_float({ { id * 11 } % 83 } + 1),
    int.to_float({ { id * 13 } % 79 } + 1),
    int.to_float({ { id * 17 } % 73 } + 1),
    int.to_float({ { id * 19 } % 71 } + 1),
    int.to_float({ { id * 23 } % 67 } + 1),
    int.to_float({ { id * 29 } % 61 } + 1),
  ]
}

fn recall_at_ten(index: vec_index.VecIndex, query_ids: List(Int)) -> String {
  let matching_results =
    list.fold(query_ids, 0, fn(matches, id) {
      let query = vector_for(id * 7)
      let approximate = vec_index.search(index, query, -1.0, 10)
      let assert Ok(exact) = vec_index.exact_search(index, query, -1.0, 10)
      let expected = list.map(exact, fn(item) { item.entity })
      let found = list.map(approximate, fn(item) { item.entity })
      matches
      + list.length(
        list.filter(expected, fn(entity) { list.contains(found, entity) }),
      )
    })
  case matching_results == list.length(query_ids) * 10 {
    True -> "1.00"
    False -> "<1.00"
  }
}

fn print_latency(label: String, samples: List(Int)) {
  let sorted = list.sort(samples, int.compare)
  let count = list.length(sorted)
  let total = list.fold(samples, 0, fn(sum, sample) { sum + sample })
  let assert Ok(p50) =
    list.drop(sorted, percentile_index(count, 50)) |> list.first()
  let assert Ok(p95) =
    list.drop(sorted, percentile_index(count, 95)) |> list.first()
  io.println(label <> "_total_ms=" <> int.to_string(total))
  io.println(label <> "_p50_ms=" <> int.to_string(p50))
  io.println(label <> "_p95_ms=" <> int.to_string(p95))
}

fn nanoseconds_to_milliseconds(value: Int) -> Int {
  value / 1_000_000
}

fn percentile_index(count: Int, percentile: Int) -> Int {
  let percentage = count * percentile / 100
  int.max(0, percentage - 1)
}

@external(erlang, "erlang", "system_time")
fn now() -> Int
