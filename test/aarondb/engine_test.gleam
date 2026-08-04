import aarondb/engine
import aarondb/fact
import aarondb/index/art
import aarondb/reactive
import aarondb/shared/ast
import aarondb/shared/query_types
import aarondb/shared/state
import aarondb/storage
import aarondb/vec_index
import gleam/dict
import gleam/list
import gleam/option.{None}
import gleeunit/should

pub fn engine_run_test() {
  let assert Ok(reactive_subject) = reactive.start_link()
  let state =
    state.DbState(
      adapter: storage.ephemeral(),
      aevt: dict.new(),
      avet: dict.new(),
      bm25_indices: dict.new(),
      eavt: dict.new(),
      vec_index: vec_index.new(),
      latest_tx: 0,
      subscribers: [],
      schema: dict.new(),
      functions: dict.new(),
      composites: [],
      reactive_actor: reactive_subject,
      followers: [],
      is_distributed: False,
      ets_name: None,
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

  let query = [
    ast.Positive(#(ast.Var("e"), "name", ast.Val(fact.Str("Alice")))),
  ]
  let q =
    ast.Query(find: [], where: query, order_by: None, limit: None, offset: None)
  let results = engine.run(state, q, [], None, None)
  should.equal(list.length(results.rows), 0)
}

pub fn pull_test() {
  let assert Ok(reactive_subject) = reactive.start_link()
  let state =
    state.DbState(
      adapter: storage.ephemeral(),
      aevt: dict.new(),
      avet: dict.new(),
      bm25_indices: dict.new(),
      eavt: dict.new(),
      vec_index: vec_index.new(),
      latest_tx: 0,
      subscribers: [],
      schema: dict.new(),
      functions: dict.new(),
      composites: [],
      reactive_actor: reactive_subject,
      followers: [],
      is_distributed: False,
      ets_name: None,
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
  let res = engine.pull(state, fact.EntityId(1), [ast.Wildcard])
  let assert query_types.PullMap(m) = unsafe_coerce(res)
  should.equal(dict.size(m), 0)
}

@external(erlang, "aarondb_ffi", "dynamic_from")
fn unsafe_coerce(a: a) -> b
