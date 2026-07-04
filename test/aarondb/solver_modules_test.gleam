import aarondb/engine/solver/bindings
import aarondb/engine/solver/positive
import aarondb/engine/solver/stores
import aarondb/engine/solver/triple
import aarondb/fact
import aarondb/index
import aarondb/index/art
import aarondb/raft
import aarondb/reactive
import aarondb/shared/ast
import aarondb/shared/state as shared_state
import aarondb/storage
import aarondb/storage/internal
import aarondb/vec_index
import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import gleam/set
import gleeunit/should

pub fn bindings_resolve_part_test() {
  let ctx = dict.from_list([#("name", fact.Str("Alice"))])

  bindings.resolve_part(ast.Var("name"), ctx)
  |> should.equal(Ok(fact.Str("Alice")) |> result_to_option())

  bindings.resolve_part(ast.Uid(fact.EntityId(1)), ctx)
  |> should.equal(Ok(fact.Ref(fact.EntityId(1))) |> result_to_option())

  bindings.resolve_part(ast.Lookup(#("user/name", fact.Str("Bob"))), ctx)
  |> should.equal(Ok(fact.Str("Bob")) |> result_to_option())
}

pub fn stores_merge_optional_stores_test() {
  let chunk_a =
    internal.StorageChunk(
      attribute: "a",
      values: internal.Leaf([fact.Int(1)]),
      max_tx: 0,
      is_compressed: False,
    )
  let chunk_b =
    internal.StorageChunk(
      attribute: "b",
      values: internal.Leaf([fact.Int(2)]),
      max_tx: 0,
      is_compressed: False,
    )

  let left = Some(dict.from_list([#("a", [chunk_a])]))
  let right = Some(dict.from_list([#("b", [chunk_b])]))

  case stores.merge_optional_stores(left, right) {
    Some(merged) -> dict.size(merged) |> should.equal(2)
    None -> should.fail()
  }
}

pub fn triple_solve_binds_entity_and_value_test() {
  let state =
    base_state()
    |> with_datoms([
      fact.Datom(
        entity: fact.EntityId(1),
        attribute: "user/name",
        value: fact.Str("Alice"),
        tx: 1,
        tx_index: 0,
        valid_time: 0,
        operation: fact.Assert,
      ),
    ])

  let rows =
    triple.solve(
      state,
      #(ast.Var("e"), "user/name", ast.Var("name")),
      dict.new(),
      set.new(),
      None,
      None,
    )

  list.length(rows) |> should.equal(1)
  let assert [row] = rows
  dict.get(row, "e") |> should.equal(Ok(fact.Ref(fact.EntityId(1))))
  dict.get(row, "name") |> should.equal(Ok(fact.Str("Alice")))
}

pub fn positive_solve_returns_matching_rows_test() {
  let state =
    base_state()
    |> with_datoms([
      fact.Datom(
        entity: fact.EntityId(1),
        attribute: "user/name",
        value: fact.Str("Alice"),
        tx: 1,
        tx_index: 0,
        valid_time: 0,
        operation: fact.Assert,
      ),
    ])

  let rows =
    positive.positive(
      state,
      #(ast.Var("e"), "user/name", ast.Val(fact.Str("Alice"))),
      dict.new(),
      None,
      None,
    )

  list.length(rows) |> should.equal(1)
}

fn base_state() {
  let assert Ok(reactive_actor) = reactive.start_link()
  shared_state.DbState(
    adapter: storage.ephemeral(),
    eavt: dict.new(),
    aevt: dict.new(),
    avet: dict.new(),
    latest_tx: 0,
    subscribers: [],
    schema: dict.new(),
    functions: dict.new(),
    composites: [],
    reactive_actor: reactive_actor,
    followers: [],
    is_distributed: False,
    ets_name: None,
    raft_state: raft.new([]),
    vec_index: vec_index.new(),
    bm25_indices: dict.new(),
    art_index: art.new(),
    registry: dict.new(),
    extensions: dict.new(),
    predicates: dict.new(),
    stored_rules: [],
    virtual_predicates: dict.new(),
    columnar_store: dict.new(),
    config: shared_state.Config(
      parallel_threshold: 500,
      batch_size: 100,
      prefetch_enabled: False,
      zero_copy_threshold: 10_000,
    ),
    query_history: [],
  )
}

fn with_datoms(state, datoms) {
  let eavt =
    list.fold(datoms, dict.new(), fn(idx, d) {
      index.insert_eavt(idx, d, fact.All)
    })
  let aevt =
    list.fold(datoms, dict.new(), fn(idx, d) {
      index.insert_aevt(idx, d, fact.All)
    })
  let avet =
    list.fold(datoms, dict.new(), fn(idx, d) { index.insert_avet(idx, d) })
  shared_state.DbState(..state, eavt: eavt, aevt: aevt, avet: avet)
}

fn result_to_option(res) {
  case res {
    Ok(v) -> Some(v)
    Error(_) -> None
  }
}
