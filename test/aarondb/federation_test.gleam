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

pub fn virtual_predicate_test() {
  // Define a dummy virtual adapter that returns static data
  // Predicate: "users_csv"
  // Args: [] (none)
  // Outputs: ["name", "age"]
  let users_csv = fn(_args: List(fact.Value)) -> List(List(fact.Value)) {
    [
      [Str("Alice"), Int(30)],
      [Str("Bob"), Int(25)],
    ]
  }

  let db_state =
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
      virtual_predicates: dict.from_list([#("users_csv", users_csv)]),
      columnar_store: dict.new(),
      config: state.Config(
        parallel_threshold: 500,
        batch_size: 100,
        prefetch_enabled: False,
        zero_copy_threshold: 10_000,
      ),
      query_history: [],
    )

  // Query: find users older than 28 from the virtual predicate
  // ?find ?name ?age . virtual("users_csv", [], [?name, ?age]) . ?age > 28
  let clauses =
    q.new()
    |> q.virtual("users_csv", [], ["name", "age"])
    |> q.filter(types.Gt(types.Var("age"), types.Val(Int(28))))
    |> q.to_clauses()

  let results = aarondb.query_state(db_state, clauses)

  should.equal(list.length(results.rows), 1)
  let assert [row] = results.rows
  should.equal(dict.get(row, "name"), Ok(Str("Alice")))
  should.equal(dict.get(row, "age"), Ok(Int(30)))
}
