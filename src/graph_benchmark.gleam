import aarondb/algo/graph
import aarondb/fact
import aarondb/index
import aarondb/index/art
import aarondb/shared/state
import aarondb/storage
import aarondb/vec_index
import gleam/dict
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{None}

/// Reproducible local graph-algorithm evidence harness.
///
/// Run with `gleam run -m graph_benchmark`. It exercises representative sparse,
/// dense, cyclic, disconnected, chain, and hub fixtures in one BEAM process.
/// It reports machine-local samples only; it is not a portable latency SLA.
pub fn main() {
  let fixtures = [
    #("sparse", sparse_edges()),
    #("dense", dense_edges()),
    #("cyclic", cyclic_edges()),
    #("disconnected", disconnected_edges()),
    #("chain", chain_edges(100)),
    #("hub", hub_edges(100)),
  ]

  list.each(fixtures, fn(fixture) {
    let #(name, edges) = fixture
    let db = graph_state(edges)
    let start = now()
    let _ = graph.reachable(db, fact.EntityId(1), "edge")
    let _ = graph.pagerank(db, "edge", 0.85, 20)
    let _ = graph.cycle_detect(db, "edge")
    let _ = graph.strongly_connected_components(db, "edge")
    let elapsed = now() - start
    io.println(
      name
      <> "_edges="
      <> int.to_string(list.length(edges))
      <> " total_ms="
      <> int.to_string(nanoseconds_to_milliseconds(elapsed)),
    )
  })
}

fn sparse_edges() -> List(#(Int, Int)) {
  [#(1, 2), #(2, 3), #(3, 4), #(4, 5)]
}

fn dense_edges() -> List(#(Int, Int)) {
  list.flat_map([1, 2, 3, 4, 5], fn(source) {
    list.filter_map([1, 2, 3, 4, 5], fn(target) {
      case source == target {
        True -> Error(Nil)
        False -> Ok(#(source, target))
      }
    })
  })
}

fn cyclic_edges() -> List(#(Int, Int)) {
  [#(1, 2), #(2, 3), #(3, 1), #(3, 4)]
}

fn disconnected_edges() -> List(#(Int, Int)) {
  [#(1, 2), #(3, 4), #(5, 6)]
}

fn chain_edges(size: Int) -> List(#(Int, Int)) {
  int.range(from: 1, to: size - 1, with: [], run: fn(edges, source) {
    [#(source, source + 1), ..edges]
  })
}

fn hub_edges(size: Int) -> List(#(Int, Int)) {
  int.range(from: 2, to: size, with: [], run: fn(edges, target) {
    [#(1, target), ..edges]
  })
}

fn graph_state(edges: List(#(Int, Int))) -> state.DbState {
  let facts =
    list.map(edges, fn(edge) {
      fact.Datom(
        entity: fact.EntityId(edge.0),
        attribute: "edge",
        value: fact.Ref(fact.EntityId(edge.1)),
        tx: 1,
        tx_index: 0,
        valid_time: 0,
        operation: fact.Assert,
      )
    })
  let eavt =
    list.fold(facts, dict.new(), fn(index, datom) {
      index.insert_eavt(index, datom, fact.All)
    })
  let aevt =
    list.fold(facts, dict.new(), fn(index, datom) {
      index.insert_aevt(index, datom, fact.All)
    })
  state.DbState(
    adapter: storage.ephemeral(),
    eavt: eavt,
    aevt: aevt,
    avet: dict.new(),
    bm25_indices: dict.new(),
    latest_tx: 0,
    subscribers: [],
    schema: dict.new(),
    functions: dict.new(),
    composites: [],
    reactive_actor: process.new_subject(),
    followers: [],
    is_distributed: False,
    ets_name: None,
    vec_index: vec_index.new(),
    art_index: art.new(),
    registry: dict.new(),
    extensions: dict.new(),
    predicates: dict.new(),
    stored_rules: [],
    virtual_predicates: dict.new(),
    columnar_store: dict.new(),
    config: state.Config(
      parallel_threshold: 500,
      batch_size: 100,
      prefetch_enabled: False,
      zero_copy_threshold: 10_000,
    ),
    query_history: [],
  )
}

fn nanoseconds_to_milliseconds(value: Int) -> Int {
  value / 1_000_000
}

@external(erlang, "erlang", "system_time")
fn now() -> Int
