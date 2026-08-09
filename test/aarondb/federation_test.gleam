import aarondb
import aarondb/fact.{Int, Str}
import aarondb/index/art
import aarondb/q
import aarondb/shared/ast as types
import aarondb/shared/state
import aarondb/storage
import aarondb/vec_index
import gleam/dict
import gleam/erlang/process
import gleam/list
import gleam/option.{None}
import gleeunit/should

fn db_with_adapter(adapter: state.VirtualAdapter) -> state.DbState {
  state.DbState(
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
    vec_index: vec_index.new(),
    art_index: art.new(),
    registry: dict.new(),
    extensions: dict.new(),
    predicates: dict.new(),
    stored_rules: [],
    virtual_predicates: dict.from_list([#("users_csv", adapter)]),
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

fn query_users(db_state: state.DbState) -> aarondb.QueryResult {
  let clauses =
    q.new()
    |> q.virtual("users_csv", [], ["name", "age"])
    |> q.filter(types.Gt(types.Var("age"), types.Val(Int(28))))
    |> q.to_clauses()
  aarondb.query_state(db_state, clauses)
}

pub fn virtual_predicate_test() {
  let users_csv = fn(_args: List(fact.Value)) -> Result(
    List(List(fact.Value)),
    state.VirtualAdapterError,
  ) {
    Ok([
      [Str("Alice"), Int(30)],
      [Str("Bob"), Int(25)],
    ])
  }
  let assert Ok(users_adapter) = state.virtual_adapter(users_csv, 10)
  let results = db_with_adapter(users_adapter) |> query_users

  should.equal(list.length(results.rows), 1)
  let assert [row] = results.rows
  should.equal(dict.get(row, "name"), Ok(Str("Alice")))
  should.equal(dict.get(row, "age"), Ok(Int(30)))
}

pub fn virtual_predicate_failure_produces_no_rows_test() {
  let failing = fn(_args: List(fact.Value)) -> Result(
    List(List(fact.Value)),
    state.VirtualAdapterError,
  ) {
    Error(state.VirtualAdapterFailed("fixture failure"))
  }
  let assert Ok(adapter) = state.virtual_adapter(failing, 10)
  let results = db_with_adapter(adapter) |> query_users
  should.equal(results.rows, [])
}

pub fn virtual_predicate_row_budget_produces_no_rows_test() {
  let too_many = fn(_args: List(fact.Value)) -> Result(
    List(List(fact.Value)),
    state.VirtualAdapterError,
  ) {
    Ok([
      [Str("Alice"), Int(30)],
      [Str("Bob"), Int(31)],
    ])
  }
  let assert Ok(adapter) = state.virtual_adapter(too_many, 1)
  let results = db_with_adapter(adapter) |> query_users
  should.equal(results.rows, [])
}

pub fn virtual_predicate_timeout_produces_no_rows_test() {
  let timed_out = fn(_args: List(fact.Value)) -> Result(
    List(List(fact.Value)),
    state.VirtualAdapterError,
  ) {
    Error(state.VirtualAdapterTimedOut)
  }
  let assert Ok(adapter) = state.virtual_adapter(timed_out, 10)
  let results = db_with_adapter(adapter) |> query_users
  should.equal(results.rows, [])
}

pub fn virtual_predicate_invalid_row_budget_test() {
  let adapter = fn(_args: List(fact.Value)) -> Result(
    List(List(fact.Value)),
    state.VirtualAdapterError,
  ) {
    Ok([])
  }
  should.equal(
    state.virtual_adapter(adapter, 0),
    Error(state.InvalidVirtualRowLimit),
  )
}
