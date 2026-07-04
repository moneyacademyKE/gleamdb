import aarondb
import aarondb/algo/graph
import aarondb/engine
import aarondb/fact.{EntityId, Ref, Str}
import aarondb/index
import aarondb/index/art
import aarondb/q
import aarondb/raft
import aarondb/shared/state as types
import aarondb/storage
import aarondb/vec_index
import gleam/dict
import gleam/erlang/process
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleeunit/should

pub fn shortest_path_test() {
  let db_state =
    types.DbState(
      adapter: storage.ephemeral(),
      eavt: dict.new(),
      aevt: dict.new(),
      avet: dict.new(),
      bm25_indices: dict.new(),
      latest_tx: 0,
      subscribers: [],
      schema: dict.new(),
      functions: dict.new(),
      composites: [],
      reactive_actor: process.new_subject(),
      // Placeholder
      followers: [],
      is_distributed: False,
      ets_name: None,
      raft_state: raft.new([]),
      vec_index: vec_index.new(),
      art_index: art.new(),
      registry: dict.new(),
      extensions: dict.new(),
      predicates: dict.new(),
      stored_rules: [],
      virtual_predicates: dict.new(),
      columnar_store: dict.new(),
      config: types.Config(
        parallel_threshold: 500,
        batch_size: 100,
        prefetch_enabled: False,
        zero_copy_threshold: 10_000,
      ),
      query_history: [],
    )

  // A -> B -> C
  let a = EntityId(1)
  let b = EntityId(2)
  let c = EntityId(3)

  let facts = [
    fact.Datom(
      entity: a,
      attribute: "connected",
      value: Ref(b),
      tx: 1,
      tx_index: 0,
      valid_time: 0,
      operation: fact.Assert,
    ),
    fact.Datom(
      entity: b,
      attribute: "connected",
      value: Ref(c),
      tx: 1,
      tx_index: 0,
      valid_time: 0,
      operation: fact.Assert,
    ),
  ]

  // Populate index manually for unit test
  let eavt =
    list.fold(facts, dict.new(), fn(idx, d) {
      index.insert_eavt(idx, d, fact.All)
    })
  let db_state = types.DbState(..db_state, eavt: eavt)

  // Test shortest_path
  let path = graph.shortest_path(db_state, a, c, "connected", None)
  should.equal(path, Some([a, b, c]))

  let no_path = graph.shortest_path(db_state, c, a, "connected", None)
  should.equal(no_path, None)
}

pub fn pagerank_test() {
  let db_state =
    types.DbState(
      adapter: storage.ephemeral(),
      eavt: dict.new(),
      aevt: dict.new(),
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
      raft_state: raft.new([]),
      vec_index: vec_index.new(),
      art_index: art.new(),
      registry: dict.new(),
      extensions: dict.new(),
      predicates: dict.new(),
      stored_rules: [],
      virtual_predicates: dict.new(),
      columnar_store: dict.new(),
      config: types.Config(
        parallel_threshold: 500,
        batch_size: 100,
        prefetch_enabled: False,
        zero_copy_threshold: 10_000,
      ),
      query_history: [],
    )

  // A -> B
  // B -> A
  // C -> A
  let a = EntityId(1)
  let b = EntityId(2)
  let c = EntityId(3)

  let facts = [
    fact.Datom(
      entity: a,
      attribute: "link",
      value: Ref(b),
      tx: 1,
      tx_index: 0,
      valid_time: 0,
      operation: fact.Assert,
    ),
    fact.Datom(
      entity: b,
      attribute: "link",
      value: Ref(a),
      tx: 1,
      tx_index: 0,
      valid_time: 0,
      operation: fact.Assert,
    ),
    fact.Datom(
      entity: c,
      attribute: "link",
      value: Ref(a),
      tx: 1,
      tx_index: 0,
      valid_time: 0,
      operation: fact.Assert,
    ),
  ]

  // Populate AEVT index (required by PageRank)
  let aevt =
    list.fold(facts, dict.new(), fn(idx, d) {
      index.insert_aevt(idx, d, fact.All)
    })
  let eavt =
    list.fold(facts, dict.new(), fn(idx, d) {
      index.insert_eavt(idx, d, fact.All)
    })

  let db_state = types.DbState(..db_state, aevt: aevt, eavt: eavt)

  // Test pagerank
  let ranks = graph.pagerank(db_state, "link", 0.85, 20)

  // A should have highest rank (in-degree 2)
  let rank_a = dict.get(ranks, a) |> result.unwrap(0.0)
  let rank_b = dict.get(ranks, b) |> result.unwrap(0.0)
  let rank_c = dict.get(ranks, c) |> result.unwrap(0.0)

  should.be_true(rank_a >. rank_b)
  should.be_true(rank_a >. rank_c)
}

pub fn graph_query_test() {
  let db_actor = aarondb.new()

  // Create graph in DB
  // A -> B -> C
  // B -> D
  let assert Ok(state) =
    aarondb.transact(db_actor, [
      #(fact.Uid(fact.EntityId(1)), "name", Str("A")),
      #(fact.Uid(fact.EntityId(1)), "link", Ref(EntityId(2))),
      #(fact.Uid(fact.EntityId(2)), "name", Str("B")),
      #(fact.Uid(fact.EntityId(2)), "link", Ref(EntityId(3))),
      #(fact.Uid(fact.EntityId(2)), "link", Ref(EntityId(4))),
      #(fact.Uid(fact.EntityId(3)), "name", Str("C")),
      #(fact.Uid(fact.EntityId(4)), "name", Str("D")),
    ])

  // 1. Shortest Path Query
  let clauses =
    q.new()
    |> q.where(q.v("a"), "name", q.s("A"))
    |> q.where(q.v("c"), "name", q.s("C"))
    |> q.shortest_path(q.v("a"), q.v("c"), "link", "p", None, None)
    |> q.to_query()

  let results = engine.run(state, clauses, [], None, None)
  should.equal(list.length(results.rows), 1)
  let assert [row] = results.rows
  let assert Ok(fact.List(path)) = dict.get(row, "p")
  should.equal(list.length(path), 3)

  // 2. PageRank Query
  let clauses =
    q.new()
    |> q.pagerank("node", "link", "rank", 0.85, 20)
    |> q.to_query()

  let results = engine.run(state, clauses, [], None, None)
  should.equal(list.length(results.rows), 4)

  // 3. Reachable Query — all nodes reachable from A
  let clauses =
    q.new()
    |> q.where(q.v("start"), "name", q.s("A"))
    |> q.reachable(q.v("start"), "link", "reached")
    |> q.to_query()

  let results = engine.run(state, clauses, [], None, None)
  // A can reach B, C, D (plus itself) — at least 3 non-self
  should.be_true(list.length(results.rows) >= 3)

  // 4. Connected Components Query — all nodes labeled
  let clauses =
    q.new()
    |> q.connected_components("link", "entity", "component")
    |> q.to_query()

  let results = engine.run(state, clauses, [], None, None)
  should.equal(list.length(results.rows), 4)

  // 5. Neighbors Query — 1-hop from B
  let clauses =
    q.new()
    |> q.where(q.v("origin"), "name", q.s("B"))
    |> q.neighbors(q.v("origin"), "link", 1, "neighbor")
    |> q.to_query()

  let results = engine.run(state, clauses, [], None, None)
  // B's 1-hop neighbors: C, D
  should.equal(list.length(results.rows), 2)
}

pub fn reachable_test() {
  let db_state =
    types.DbState(
      adapter: storage.ephemeral(),
      eavt: dict.new(),
      aevt: dict.new(),
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
      raft_state: raft.new([]),
      vec_index: vec_index.new(),
      art_index: art.new(),
      registry: dict.new(),
      extensions: dict.new(),
      predicates: dict.new(),
      stored_rules: [],
      virtual_predicates: dict.new(),
      columnar_store: dict.new(),
      config: types.Config(
        parallel_threshold: 500,
        batch_size: 100,
        prefetch_enabled: False,
        zero_copy_threshold: 10_000,
      ),
      query_history: [],
    )

  // A -> B -> C, A -> D (D is a dead end)
  let a = EntityId(1)
  let b = EntityId(2)
  let c = EntityId(3)
  let d = EntityId(4)

  let facts = [
    fact.Datom(
      entity: a,
      attribute: "edge",
      value: Ref(b),
      tx: 1,
      tx_index: 0,
      valid_time: 0,
      operation: fact.Assert,
    ),
    fact.Datom(
      entity: b,
      attribute: "edge",
      value: Ref(c),
      tx: 1,
      tx_index: 0,
      valid_time: 0,
      operation: fact.Assert,
    ),
    fact.Datom(
      entity: a,
      attribute: "edge",
      value: Ref(d),
      tx: 1,
      tx_index: 0,
      valid_time: 0,
      operation: fact.Assert,
    ),
  ]

  let eavt =
    list.fold(facts, dict.new(), fn(idx, datom) {
      index.insert_eavt(idx, datom, fact.All)
    })
  let db_state = types.DbState(..db_state, eavt: eavt)

  // From A, we should reach A, B, C, D
  let reached = graph.reachable(db_state, a, "edge")
  should.equal(list.length(reached), 4)

  // From C, we reach only C (dead end)
  let reached_c = graph.reachable(db_state, c, "edge")
  should.equal(list.length(reached_c), 1)
}

pub fn connected_components_test() {
  let db_state =
    types.DbState(
      adapter: storage.ephemeral(),
      eavt: dict.new(),
      aevt: dict.new(),
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
      raft_state: raft.new([]),
      vec_index: vec_index.new(),
      art_index: art.new(),
      registry: dict.new(),
      extensions: dict.new(),
      predicates: dict.new(),
      stored_rules: [],
      virtual_predicates: dict.new(),
      columnar_store: dict.new(),
      config: types.Config(
        parallel_threshold: 500,
        batch_size: 100,
        prefetch_enabled: False,
        zero_copy_threshold: 10_000,
      ),
      query_history: [],
    )

  // Component 1: A -> B
  // Component 2: C -> D  (disconnected from A,B)
  let a = EntityId(1)
  let b = EntityId(2)
  let c = EntityId(3)
  let d = EntityId(4)

  let facts = [
    fact.Datom(
      entity: a,
      attribute: "edge",
      value: Ref(b),
      tx: 1,
      tx_index: 0,
      valid_time: 0,
      operation: fact.Assert,
    ),
    fact.Datom(
      entity: c,
      attribute: "edge",
      value: Ref(d),
      tx: 1,
      tx_index: 0,
      valid_time: 0,
      operation: fact.Assert,
    ),
  ]

  let aevt =
    list.fold(facts, dict.new(), fn(idx, datom) {
      index.insert_aevt(idx, datom, fact.All)
    })
  let eavt =
    list.fold(facts, dict.new(), fn(idx, datom) {
      index.insert_eavt(idx, datom, fact.All)
    })
  let db_state = types.DbState(..db_state, eavt: eavt, aevt: aevt)

  let components = graph.connected_components(db_state, "edge")

  // Should have 4 nodes labeled
  should.equal(dict.size(components), 4)

  // A and B should be in the same component
  let assert Ok(comp_a) = dict.get(components, a)
  let assert Ok(comp_b) = dict.get(components, b)
  should.equal(comp_a, comp_b)

  // C and D should be in the same component
  let assert Ok(comp_c) = dict.get(components, c)
  let assert Ok(comp_d) = dict.get(components, d)
  should.equal(comp_c, comp_d)

  // But A's component != C's component
  should.be_true(comp_a != comp_c)
}

pub fn neighbors_khop_test() {
  let db_state =
    types.DbState(
      adapter: storage.ephemeral(),
      eavt: dict.new(),
      aevt: dict.new(),
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
      raft_state: raft.new([]),
      vec_index: vec_index.new(),
      art_index: art.new(),
      registry: dict.new(),
      extensions: dict.new(),
      predicates: dict.new(),
      stored_rules: [],
      virtual_predicates: dict.new(),
      columnar_store: dict.new(),
      config: types.Config(
        parallel_threshold: 500,
        batch_size: 100,
        prefetch_enabled: False,
        zero_copy_threshold: 10_000,
      ),
      query_history: [],
    )

  // A -> B -> C -> D
  let a = EntityId(1)
  let b = EntityId(2)
  let c = EntityId(3)
  let d = EntityId(4)

  let facts = [
    fact.Datom(
      entity: a,
      attribute: "edge",
      value: Ref(b),
      tx: 1,
      tx_index: 0,
      valid_time: 0,
      operation: fact.Assert,
    ),
    fact.Datom(
      entity: b,
      attribute: "edge",
      value: Ref(c),
      tx: 1,
      tx_index: 0,
      valid_time: 0,
      operation: fact.Assert,
    ),
    fact.Datom(
      entity: c,
      attribute: "edge",
      value: Ref(d),
      tx: 1,
      tx_index: 0,
      valid_time: 0,
      operation: fact.Assert,
    ),
  ]

  let eavt =
    list.fold(facts, dict.new(), fn(idx, datom) {
      index.insert_eavt(idx, datom, fact.All)
    })
  let db_state = types.DbState(..db_state, eavt: eavt)

  // 1-hop from A: just B
  let n1 = graph.neighbors_khop(db_state, a, "edge", 1)
  should.equal(list.length(n1), 1)

  // 2-hop from A: B and C
  let n2 = graph.neighbors_khop(db_state, a, "edge", 2)
  should.equal(list.length(n2), 2)

  // 3-hop from A: B, C, D
  let n3 = graph.neighbors_khop(db_state, a, "edge", 3)
  should.equal(list.length(n3), 3)

  // 0-hop from A: nothing (exclude self)
  let n0 = graph.neighbors_khop(db_state, a, "edge", 0)
  should.equal(list.length(n0), 0)
}

pub fn cycle_detect_test() {
  let db_state =
    types.DbState(
      adapter: storage.ephemeral(),
      eavt: dict.new(),
      aevt: dict.new(),
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
      raft_state: raft.new([]),
      vec_index: vec_index.new(),
      art_index: art.new(),
      registry: dict.new(),
      extensions: dict.new(),
      predicates: dict.new(),
      stored_rules: [],
      virtual_predicates: dict.new(),
      columnar_store: dict.new(),
      config: types.Config(
        parallel_threshold: 500,
        batch_size: 100,
        prefetch_enabled: False,
        zero_copy_threshold: 10_000,
      ),
      query_history: [],
    )

  // A -> B -> C -> A (cycle), D -> E (no cycle)
  let a = EntityId(1)
  let b = EntityId(2)
  let c = EntityId(3)
  let d = EntityId(4)
  let e = EntityId(5)

  let facts = [
    fact.Datom(
      entity: a,
      attribute: "edge",
      value: Ref(b),
      tx: 1,
      tx_index: 0,
      valid_time: 0,
      operation: fact.Assert,
    ),
    fact.Datom(
      entity: b,
      attribute: "edge",
      value: Ref(c),
      tx: 1,
      tx_index: 0,
      valid_time: 0,
      operation: fact.Assert,
    ),
    fact.Datom(
      entity: c,
      attribute: "edge",
      value: Ref(a),
      tx: 1,
      tx_index: 0,
      valid_time: 0,
      operation: fact.Assert,
    ),
    fact.Datom(
      entity: d,
      attribute: "edge",
      value: Ref(e),
      tx: 1,
      tx_index: 0,
      valid_time: 0,
      operation: fact.Assert,
    ),
  ]

  let aevt =
    list.fold(facts, dict.new(), fn(idx, datom) {
      index.insert_aevt(idx, datom, fact.All)
    })
  let db_state = types.DbState(..db_state, aevt: aevt)

  let cycles = graph.cycle_detect(db_state, "edge")
  // Should find at least 1 cycle
  should.be_true(list.length(cycles) >= 1)

  // Each cycle should contain A (cycles through A->B->C->A)
  let assert [first_cycle, ..] = cycles
  should.be_true(list.length(first_cycle) >= 2)
}

pub fn betweenness_centrality_test() {
  let db_state =
    types.DbState(
      adapter: storage.ephemeral(),
      eavt: dict.new(),
      aevt: dict.new(),
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
      raft_state: raft.new([]),
      vec_index: vec_index.new(),
      art_index: art.new(),
      registry: dict.new(),
      extensions: dict.new(),
      predicates: dict.new(),
      stored_rules: [],
      virtual_predicates: dict.new(),
      columnar_store: dict.new(),
      config: types.Config(
        parallel_threshold: 500,
        batch_size: 100,
        prefetch_enabled: False,
        zero_copy_threshold: 10_000,
      ),
      query_history: [],
    )

  // Star topology: A -> B, C -> B, D -> B, B -> E
  // B is the gatekeeper — should have highest betweenness
  let a = EntityId(1)
  let b = EntityId(2)
  let c = EntityId(3)
  let d = EntityId(4)
  let e = EntityId(5)

  let facts = [
    fact.Datom(
      entity: a,
      attribute: "edge",
      value: Ref(b),
      tx: 1,
      tx_index: 0,
      valid_time: 0,
      operation: fact.Assert,
    ),
    fact.Datom(
      entity: c,
      attribute: "edge",
      value: Ref(b),
      tx: 1,
      tx_index: 0,
      valid_time: 0,
      operation: fact.Assert,
    ),
    fact.Datom(
      entity: d,
      attribute: "edge",
      value: Ref(b),
      tx: 1,
      tx_index: 0,
      valid_time: 0,
      operation: fact.Assert,
    ),
    fact.Datom(
      entity: b,
      attribute: "edge",
      value: Ref(e),
      tx: 1,
      tx_index: 0,
      valid_time: 0,
      operation: fact.Assert,
    ),
  ]

  let aevt =
    list.fold(facts, dict.new(), fn(idx, datom) {
      index.insert_aevt(idx, datom, fact.All)
    })
  let db_state = types.DbState(..db_state, aevt: aevt)

  let scores = graph.betweenness_centrality(db_state, "edge")

  // B should have the highest betweenness centrality
  let score_b = dict.get(scores, b) |> result.unwrap(0.0)
  let score_a = dict.get(scores, a) |> result.unwrap(0.0)
  let score_e = dict.get(scores, e) |> result.unwrap(0.0)

  should.be_true(score_b >. score_a)
  should.be_true(score_b >. score_e)
}

pub fn topological_sort_test() {
  let db_state =
    types.DbState(
      adapter: storage.ephemeral(),
      eavt: dict.new(),
      aevt: dict.new(),
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
      raft_state: raft.new([]),
      vec_index: vec_index.new(),
      art_index: art.new(),
      registry: dict.new(),
      extensions: dict.new(),
      predicates: dict.new(),
      stored_rules: [],
      virtual_predicates: dict.new(),
      columnar_store: dict.new(),
      config: types.Config(
        parallel_threshold: 500,
        batch_size: 100,
        prefetch_enabled: False,
        zero_copy_threshold: 10_000,
      ),
      query_history: [],
    )

  // DAG: A -> B -> D, A -> C -> D
  let a = EntityId(1)
  let b = EntityId(2)
  let c = EntityId(3)
  let d = EntityId(4)

  let facts = [
    fact.Datom(
      entity: a,
      attribute: "dep",
      value: Ref(b),
      tx: 1,
      tx_index: 0,
      valid_time: 0,
      operation: fact.Assert,
    ),
    fact.Datom(
      entity: a,
      attribute: "dep",
      value: Ref(c),
      tx: 1,
      tx_index: 0,
      valid_time: 0,
      operation: fact.Assert,
    ),
    fact.Datom(
      entity: b,
      attribute: "dep",
      value: Ref(d),
      tx: 1,
      tx_index: 0,
      valid_time: 0,
      operation: fact.Assert,
    ),
    fact.Datom(
      entity: c,
      attribute: "dep",
      value: Ref(d),
      tx: 1,
      tx_index: 0,
      valid_time: 0,
      operation: fact.Assert,
    ),
  ]

  let aevt =
    list.fold(facts, dict.new(), fn(idx, datom) {
      index.insert_aevt(idx, datom, fact.All)
    })
  let db_state = types.DbState(..db_state, aevt: aevt)

  // Should succeed (DAG)
  let assert Ok(sorted) = graph.topological_sort(db_state, "dep")
  should.equal(list.length(sorted), 4)

  // A must come before B, C; B and C must come before D
  let assert Ok(pos_a) = list_index(sorted, a, 0)
  let assert Ok(pos_d) = list_index(sorted, d, 0)
  should.be_true(pos_a < pos_d)

  // Now test with a cycle: add D -> A
  let cycle_facts = [
    fact.Datom(
      entity: d,
      attribute: "dep",
      value: Ref(a),
      tx: 2,
      tx_index: 0,
      valid_time: 0,
      operation: fact.Assert,
    ),
    ..facts
  ]
  let aevt2 =
    list.fold(cycle_facts, dict.new(), fn(idx, datom) {
      index.insert_aevt(idx, datom, fact.All)
    })
  let db_state2 = types.DbState(..db_state, aevt: aevt2)

  // Should fail (cycle)
  let assert Error(cycle_nodes) = graph.topological_sort(db_state2, "dep")
  should.be_true(cycle_nodes != [])
}

pub fn strongly_connected_components_test() {
  let db_state =
    types.DbState(
      adapter: storage.ephemeral(),
      eavt: dict.new(),
      aevt: dict.new(),
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
      raft_state: raft.new([]),
      vec_index: vec_index.new(),
      art_index: art.new(),
      registry: dict.new(),
      extensions: dict.new(),
      predicates: dict.new(),
      stored_rules: [],
      virtual_predicates: dict.new(),
      columnar_store: dict.new(),
      config: types.Config(
        parallel_threshold: 500,
        batch_size: 100,
        prefetch_enabled: False,
        zero_copy_threshold: 10_000,
      ),
      query_history: [],
    )

  // Cycle: A -> B -> C -> A  (one SCC)
  // Chain: D -> E  (two separate SCCs)
  let a = EntityId(1)
  let b = EntityId(2)
  let c = EntityId(3)
  let d = EntityId(4)
  let e = EntityId(5)

  let facts = [
    fact.Datom(
      entity: a,
      attribute: "edge",
      value: Ref(b),
      tx: 1,
      tx_index: 0,
      valid_time: 0,
      operation: fact.Assert,
    ),
    fact.Datom(
      entity: b,
      attribute: "edge",
      value: Ref(c),
      tx: 1,
      tx_index: 0,
      valid_time: 0,
      operation: fact.Assert,
    ),
    fact.Datom(
      entity: c,
      attribute: "edge",
      value: Ref(a),
      tx: 1,
      tx_index: 0,
      valid_time: 0,
      operation: fact.Assert,
    ),
    fact.Datom(
      entity: d,
      attribute: "edge",
      value: Ref(e),
      tx: 1,
      tx_index: 0,
      valid_time: 0,
      operation: fact.Assert,
    ),
  ]

  let aevt =
    list.fold(facts, dict.new(), fn(idx, datom) {
      index.insert_aevt(idx, datom, fact.All)
    })
  let db_state = types.DbState(..db_state, aevt: aevt)

  let sccs = graph.strongly_connected_components(db_state, "edge")

  // All 5 nodes should be labeled
  should.equal(dict.size(sccs), 5)

  // A, B, C should share the same component (mutual reachability)
  let assert Ok(scc_a) = dict.get(sccs, a)
  let assert Ok(scc_b) = dict.get(sccs, b)
  let assert Ok(scc_c) = dict.get(sccs, c)
  should.equal(scc_a, scc_b)
  should.equal(scc_b, scc_c)

  // D and E should be in different components (no back-edge)
  let assert Ok(scc_d) = dict.get(sccs, d)
  let assert Ok(scc_e) = dict.get(sccs, e)
  should.be_true(scc_d != scc_e)

  // And the cycle SCC != D's SCC
  should.be_true(scc_a != scc_d)
}

// Helper: find index of element in list
fn list_index(
  lst: List(fact.EntityId),
  target: fact.EntityId,
  idx: Int,
) -> Result(Int, Nil) {
  case lst {
    [] -> Error(Nil)
    [head, ..tail] -> {
      case head == target {
        True -> Ok(idx)
        False -> list_index(tail, target, idx + 1)
      }
    }
  }
}
