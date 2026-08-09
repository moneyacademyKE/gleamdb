import aarondb/fact
import aarondb/index/bm25
import gleam/int
import gleam/io
import gleam/list

/// Reproducible local evidence harness for the caller-owned BM25 primitive.
///
/// Run with `gleam run -m bm25_benchmark`. This measures one BEAM process,
/// one immutable in-memory index, and sequential operations. It does not
/// claim persistence, transaction integration, or concurrent mutation safety.
pub fn main() {
  let document_count = 1000
  let query_count = 100
  let documents = documents(document_count)

  let build_start = now()
  let index =
    list.fold(documents, bm25.empty("body"), fn(index, document) {
      let #(entity, text) = document
      bm25.add(index, entity, text)
    })
  let build_ns = now() - build_start

  let query_times =
    list.repeat(Nil, query_count)
    |> list.map(fn(_) {
      let start = now()
      let _ = bm25.search(index, "gleam database retrieval", 1.2, 0.75, 10)
      nanoseconds_to_milliseconds(now() - start)
    })

  let update_start = now()
  let _ =
    list.fold(documents, index, fn(current, document) {
      let #(entity, _) = document
      bm25.add(current, entity, "gleam updated document retrieval")
    })
  let update_ns = now() - update_start

  io.println("document_count=" <> int.to_string(document_count))
  io.println("query_count=" <> int.to_string(query_count))
  io.println(
    "build_ms=" <> int.to_string(nanoseconds_to_milliseconds(build_ns)),
  )
  io.println(
    "replace_all_ms=" <> int.to_string(nanoseconds_to_milliseconds(update_ns)),
  )
  print_latency("search", query_times)
}

fn documents(count: Int) -> List(#(fact.EntityId, String)) {
  list.repeat(Nil, count)
  |> list.index_map(fn(_, offset) {
    let id = offset + 1
    #(
      fact.EntityId(id),
      "gleam database retrieval document " <> int.to_string(id),
    )
  })
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
