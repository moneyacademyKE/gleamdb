import aarondb/fact.{type AttributeConfig, type Datom, type DbFunction}
import aarondb/index.{type AIndex, type AVIndex, type Index}
import aarondb/index/art
import aarondb/index/bm25
import aarondb/shared/ast
import aarondb/shared/query_types
import aarondb/storage.{type StorageAdapter}
import aarondb/storage/internal
import aarondb/vec_index
import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/erlang/process.{type Subject}
import gleam/option.{type Option}

pub type Config {
  Config(
    parallel_threshold: Int,
    batch_size: Int,
    prefetch_enabled: Bool,
    zero_copy_threshold: Int,
  )
}

pub type QueryContext {
  QueryContext(
    attributes: List(String),
    entities: List(fact.EntityId),
    timestamp: Int,
  )
}

pub type IndexAdapter {
  IndexAdapter(
    name: String,
    create: fn(String) -> Dynamic,
    update: fn(Dynamic, List(Datom)) -> Dynamic,
    search: fn(Dynamic, IndexQuery, Float) -> List(fact.EntityId),
  )
}

pub type ExtensionInstance {
  ExtensionInstance(adapter_name: String, attribute: String, data: Dynamic)
}

pub type IndexQuery {
  TextQuery(text: String)
  NumericRange(min: Float, max: Float)
  Custom(data: String)
}

pub type DbState {
  DbState(
    adapter: StorageAdapter,
    eavt: Index,
    aevt: AIndex,
    avet: AVIndex,
    latest_tx: Int,
    subscribers: List(Subject(List(Datom))),
    schema: Dict(String, AttributeConfig),
    functions: Dict(String, DbFunction(DbState)),
    composites: List(List(String)),
    reactive_actor: Subject(ReactiveMessage),
    followers: List(process.Pid),
    is_distributed: Bool,
    ets_name: Option(String),
    vec_index: vec_index.VecIndex,
    bm25_indices: Dict(String, bm25.BM25Index),
    art_index: art.Art,
    registry: Dict(String, IndexAdapter),
    extensions: Dict(String, ExtensionInstance),
    predicates: Dict(String, fn(fact.Value) -> Bool),
    stored_rules: List(ast.Rule),
    virtual_predicates: Dict(String, VirtualAdapter),
    columnar_store: Dict(String, List(internal.StorageChunk)),
    config: Config,
    query_history: List(QueryContext),
  )
}

pub type ReactiveMessage {
  Subscribe(
    query: ast.Query,
    attributes: List(String),
    subscriber: Subject(query_types.ReactiveDelta),
    initial_state: query_types.QueryResult,
  )
  Unsubscribe(subscriber: Subject(query_types.ReactiveDelta))
  Notify(changed_attributes: List(String), current_state: DbState)
}

/// A local virtual predicate adapter.
///
/// The adapter runs synchronously inside the query actor. It must return either
/// a complete ordered set of rows or a failure; it must not perform remote I/O
/// or assume AaronDB can interrupt a blocked call.
pub type VirtualAdapter {
  VirtualAdapter(
    execute: fn(List(fact.Value)) ->
      Result(List(List(fact.Value)), VirtualAdapterError),
    max_rows: Int,
  )
}

/// Typed result of running a bounded local virtual predicate adapter.
pub type VirtualAdapterError {
  InvalidVirtualRowLimit
  VirtualAdapterFailed(message: String)
  VirtualAdapterTimedOut
  VirtualRowLimitExceeded
}

pub fn virtual_adapter(
  execute: fn(List(fact.Value)) ->
    Result(List(List(fact.Value)), VirtualAdapterError),
  max_rows: Int,
) -> Result(VirtualAdapter, VirtualAdapterError) {
  case max_rows > 0 {
    True -> Ok(VirtualAdapter(execute: execute, max_rows: max_rows))
    False -> Error(InvalidVirtualRowLimit)
  }
}
