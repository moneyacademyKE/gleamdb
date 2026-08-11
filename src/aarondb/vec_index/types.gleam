import aarondb/fact
import gleam/dict.{type Dict}
import gleam/option.{type Option}

/// A single layer in the Hierarchical Navigable Small-World graph.
pub type Layer {
  Layer(edges: Dict(fact.EntityId, List(fact.EntityId)))
}

/// The source used to choose HNSW insertion levels.
pub type LevelSource {
  RandomLevels
  DeterministicLevels(List(Int))
}

/// Construction and search limits for an HNSW index.
pub type HnswConfig {
  HnswConfig(max_neighbors: Int, search_budget: Int, level_source: LevelSource)
}

/// A Hierarchical Navigable Small-World graph for approximate nearest-neighbor search.
pub type VecIndex {
  VecIndex(
    nodes: Dict(fact.EntityId, List(Float)),
    layers: Dict(Int, Layer),
    dimensions: Option(Int),
    config: HnswConfig,
    entry_point: Result(fact.EntityId, Nil),
    max_level: Int,
  )
}

/// An entity and its cosine-similarity score.
pub type SearchResult {
  SearchResult(entity: fact.EntityId, score: Float)
}
