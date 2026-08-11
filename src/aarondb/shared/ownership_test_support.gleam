import aarondb/index
import aarondb/index/art
import aarondb/reactive
import aarondb/shared/ownership
import aarondb/shared/state
import aarondb/storage
import aarondb/vec_index
import gleam/dict
import gleam/option.{type Option}

/// Creates the one canonical all-empty state used by state-characterization
/// tests. Production startup uses the same defaults in the transactor adapter.
pub fn empty(
  store: storage.StorageAdapter,
  distributed: Bool,
  ets_name: Option(String),
) -> state.DbState {
  let assert Ok(reactive_actor) = reactive.start_link()
  state.DbState(
    adapter: store,
    eavt: index.new_index(),
    aevt: index.new_aindex(),
    avet: index.new_avindex(),
    latest_tx: 0,
    subscribers: [],
    schema: dict.new(),
    functions: dict.new(),
    composites: [],
    reactive_actor: reactive_actor,
    followers: [],
    is_distributed: distributed,
    ets_name: ets_name,
    vec_index: vec_index.new(),
    bm25_indices: dict.new(),
    art_index: art.new(),
    registry: dict.new(),
    extensions: dict.new(),
    predicates: dict.new(),
    stored_rules: [],
    virtual_predicates: dict.new(),
    columnar_store: dict.new(),
    config: state.Config(
      parallel_threshold: 1000,
      batch_size: 1000,
      prefetch_enabled: False,
      zero_copy_threshold: 10_000,
    ),
    query_history: [],
  )
}

pub fn has_no_optional_extensions(db: state.DbState) -> Bool {
  let view = ownership.view(db)
  view.extensions.extensions == dict.new()
  && view.extensions.registry == dict.new()
  && view.extensions.virtual_predicates == dict.new()
}
