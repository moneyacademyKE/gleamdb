import aarondb/fact
import aarondb/index.{type AIndex, type AVIndex, type Index}
import aarondb/index/art
import aarondb/index/bm25
import aarondb/shared/ast
import aarondb/shared/state
import aarondb/storage.{type StorageAdapter}
import aarondb/storage/internal
import aarondb/vec_index
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/option.{type Option}

/// The immutable domain facts and primary indexes in a database snapshot.
pub type Facts {
  Facts(
    eavt: Index,
    aevt: AIndex,
    avet: AVIndex,
    latest_tx: Int,
    schema: Dict(String, fact.AttributeConfig),
  )
}

/// Derived indexes owned by the state transition layer.
pub type Indexes {
  Indexes(
    vec_index: vec_index.VecIndex,
    bm25_indices: Dict(String, bm25.BM25Index),
    art_index: art.Art,
    columnar_store: Dict(String, List(internal.StorageChunk)),
  )
}

/// Runtime handles deliberately kept outside the deterministic domain.
pub type Runtime {
  Runtime(
    adapter: StorageAdapter,
    subscribers: List(Subject(List(fact.Datom))),
    reactive_actor: Subject(state.ReactiveMessage),
    followers: List(process.Pid),
    is_distributed: Bool,
    ets_name: Option(String),
  )
}

/// Optional executable registrations and extensions.
pub type Extensions {
  Extensions(
    functions: Dict(String, fact.DbFunction(state.DbState)),
    composites: List(List(String)),
    registry: Dict(String, state.IndexAdapter),
    extensions: Dict(String, state.ExtensionInstance),
    predicates: Dict(String, fn(fact.Value) -> Bool),
    stored_rules: List(ast.Rule),
    virtual_predicates: Dict(String, state.VirtualAdapter),
  )
}

/// Operational policy and bounded observability.
pub type Operations {
  Operations(config: state.Config, query_history: List(state.QueryContext))
}

/// A total, explicit ownership projection of the legacy public state record.
pub type View {
  View(
    facts: Facts,
    indexes: Indexes,
    runtime: Runtime,
    extensions: Extensions,
    operations: Operations,
  )
}

pub fn view(db: state.DbState) -> View {
  View(
    facts: Facts(db.eavt, db.aevt, db.avet, db.latest_tx, db.schema),
    indexes: Indexes(
      db.vec_index,
      db.bm25_indices,
      db.art_index,
      db.columnar_store,
    ),
    runtime: Runtime(
      db.adapter,
      db.subscribers,
      db.reactive_actor,
      db.followers,
      db.is_distributed,
      db.ets_name,
    ),
    extensions: Extensions(
      db.functions,
      db.composites,
      db.registry,
      db.extensions,
      db.predicates,
      db.stored_rules,
      db.virtual_predicates,
    ),
    operations: Operations(db.config, db.query_history),
  )
}
