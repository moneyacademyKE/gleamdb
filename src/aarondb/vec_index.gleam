import aarondb/fact
import aarondb/vector
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

/// A single layer in the Hierarchical Navigable Small-World (HNSW) graph.
pub type Layer {
  Layer(edges: Dict(fact.EntityId, List(fact.EntityId)))
}

/// A Hierarchical Navigable Small-World (HNSW) graph for approximate nearest neighbor search.
/// Scales logarithmically even for million-scale datasets by using hierarchical layers.
pub type VecIndex {
  VecIndex(
    nodes: Dict(fact.EntityId, List(Float)),
    layers: Dict(Int, Layer),
    dimensions: Option(Int),
    max_neighbors: Int,
    entry_point: Result(fact.EntityId, Nil),
    max_level: Int,
  )
}

/// A search result: entity ID + similarity score.
pub type SearchResult {
  SearchResult(entity: fact.EntityId, score: Float)
}

// --- Constructor ---

/// Create an empty vector index with default max_neighbors of 16.
pub fn new() -> VecIndex {
  VecIndex(
    nodes: dict.new(),
    layers: dict.from_list([#(0, Layer(edges: dict.new()))]),
    dimensions: None,
    max_neighbors: 16,
    entry_point: Error(Nil),
    max_level: 0,
  )
}

/// Create an empty vector index with custom max_neighbors.
pub fn new_with_m(m: Int) -> VecIndex {
  VecIndex(..new(), max_neighbors: m)
}

fn random_level(multiplier: Float) -> Int {
  let r = uniform_float()
  let assert Ok(log_r) = float.logarithm(r)
  let level = float.round(float.floor(multiplier *. log_r))
  case level < 0 {
    True -> -level
    False -> level
  }
}

@external(erlang, "rand", "uniform")
fn uniform_float() -> Float

// --- Insert ---

/// Insert a vector into the NSW graph.
///
/// A vector index has one fixed dimensionality, established by its first vector.
/// A mismatched vector is rejected without changing the index.
pub fn insert(
  idx: VecIndex,
  entity: fact.EntityId,
  vec: List(Float),
) -> VecIndex {
  case try_insert(idx, entity, vec) {
    Ok(index) -> index
    Error(Nil) -> idx
  }
}

/// Insert a vector, returning `Error` when it is empty, has zero magnitude, or
/// its dimensionality differs from the index. Use this at validation boundaries
/// when an invalid vector must be surfaced to the caller.
pub fn try_insert(
  idx: VecIndex,
  entity: fact.EntityId,
  vec: List(Float),
) -> Result(VecIndex, Nil) {
  let dimensions = vector.dimensions(vec)
  case valid_vector(vec) {
    False -> Error(Nil)
    True ->
      case idx.dimensions {
        Some(expected) if expected != dimensions -> Error(Nil)
        _ -> Ok(do_insert(idx, entity, vec, dimensions))
      }
  }
}

fn valid_vector(vec: List(Float)) -> Bool {
  vector.dimensions(vec) > 0 && vector.magnitude(vec) != 0.0
}

/// Greedy-links the new node to its nearest existing neighbors across multiple levels.
fn do_insert(
  idx: VecIndex,
  entity: fact.EntityId,
  vec: List(Float),
  dimensions: Int,
) -> VecIndex {
  // Store the normalized vector
  let vec = vector.normalize(vec)
  let nodes = dict.insert(idx.nodes, entity, vec)

  // Determine insertion level (Phase 44: HNSW scaling)
  let assert Ok(log_16) = float.logarithm(16.0)
  let level = random_level(1.0 /. log_16)
  let new_max_level = int.max(idx.max_level, level)

  case idx.entry_point {
    Error(Nil) -> {
      // First node — no edges needed, set entry point across all levels up to level
      let layers =
        int.range(from: 0, to: level + 1, with: idx.layers, run: fn(acc, i) {
          dict.insert(acc, i, Layer(edges: dict.insert(dict.new(), entity, [])))
        })
      VecIndex(
        ..idx,
        nodes: nodes,
        layers: layers,
        dimensions: Some(dimensions),
        entry_point: Ok(entity),
        max_level: level,
      )
    }
    Ok(ep_id) -> {
      // 1. Search from top layer down to level + 1 to find entry point for insertion
      let ep_for_level =
        descend_to_level(idx, vec, ep_id, idx.max_level, level + 1)

      // 2. Insert into layers from level down to 0
      let #(final_layers, _) =
        int.range(
          from: level,
          to: -1,
          with: #(idx.layers, ep_for_level),
          run: fn(acc, i) {
            let #(curr_layers, curr_ep) = acc
            let layer =
              dict.get(curr_layers, i)
              |> result.unwrap(Layer(edges: dict.new()))

            // Find neighbors in this layer
            let vec_ep = dict.get(nodes, curr_ep) |> result.unwrap(vec)
            let ep_res =
              SearchResult(
                entity: curr_ep,
                score: vector.dot_product(vec, vec_ep),
              )

            let neighbors =
              greedy_search(
                nodes,
                layer.edges,
                vec,
                [curr_ep],
                dict.from_list([#(curr_ep, True)]),
                [ep_res],
                100,
              )
              |> list.filter(fn(r) { r.entity != entity })
              // Don't connect to self
              |> list.sort(fn(a, b) { float.compare(b.score, a.score) })
              |> list.take(idx.max_neighbors)

            let neighbor_ids = list.map(neighbors, fn(r) { r.entity })

            // Add bidirectional edges
            let edges_with_new = dict.insert(layer.edges, entity, neighbor_ids)
            let final_edges =
              list.fold(neighbor_ids, edges_with_new, fn(e_acc, n_id) {
                let existing = dict.get(e_acc, n_id) |> unwrap_list()
                let updated =
                  prune_neighbors(
                    idx.max_neighbors,
                    n_id,
                    [entity, ..existing],
                    nodes,
                  )
                dict.insert(e_acc, n_id, updated)
              })

            let new_layers =
              dict.insert(curr_layers, i, Layer(edges: final_edges))
            let next_ep = case list.first(neighbors) {
              Ok(best) -> best.entity
              Error(Nil) -> curr_ep
            }
            #(new_layers, next_ep)
          },
        )

      VecIndex(
        ..idx,
        nodes: nodes,
        layers: final_layers,
        max_level: new_max_level,
        entry_point: case
          level > idx.max_level || result.is_error(idx.entry_point)
        {
          True -> Ok(entity)
          False -> idx.entry_point
        },
      )
    }
  }
}

fn descend_to_level(
  idx: VecIndex,
  query: List(Float),
  ep: fact.EntityId,
  current_level: Int,
  stop_level: Int,
) -> fact.EntityId {
  case current_level < stop_level {
    True -> ep
    False -> {
      let layer =
        dict.get(idx.layers, current_level)
        |> result.unwrap(Layer(edges: dict.new()))
      // Find single best neighbor in this layer to move down.
      // High budget (10) to ensure we actually find the local minimum.
      let vec_ep = dict.get(idx.nodes, ep) |> result.unwrap(query)
      let ep_res =
        SearchResult(entity: ep, score: vector.dot_product(query, vec_ep))
      let results =
        greedy_search(
          idx.nodes,
          layer.edges,
          query,
          [ep],
          dict.new(),
          [ep_res],
          10,
        )
      let next_ep = case
        results
        |> list.sort(fn(a, b) { float.compare(b.score, a.score) })
        |> list.first()
      {
        Ok(best) -> best.entity
        Error(Nil) -> ep
      }
      descend_to_level(idx, query, next_ep, current_level - 1, stop_level)
    }
  }
}

// --- Search ---

pub fn search(
  idx: VecIndex,
  query: List(Float),
  threshold: Float,
  k: Int,
) -> List(SearchResult) {
  case try_search(idx, query, threshold, k) {
    Ok(results) -> results
    Error(Nil) -> []
  }
}

/// Search for vectors similar to `query`.
///
/// Returns `Error` when the query is empty, has zero magnitude, does not match
/// the index dimensions, `threshold` is outside `[-1.0, 1.0]`, or `k` is not
/// positive. This prevents invalid inputs from receiving ambiguous scores.
pub fn try_search(
  idx: VecIndex,
  query: List(Float),
  threshold: Float,
  k: Int,
) -> Result(List(SearchResult), Nil) {
  let dimensions = vector.dimensions(query)
  case valid_query(query, threshold, k) {
    False -> Error(Nil)
    True ->
      case idx.dimensions {
        Some(expected) if expected != dimensions -> Error(Nil)
        _ -> Ok(do_search(idx, query, threshold, k))
      }
  }
}

fn valid_query(query: List(Float), threshold: Float, k: Int) -> Bool {
  valid_vector(query) && threshold >=. -1.0 && threshold <=. 1.0 && k > 0
}

/// Uses hierarchical greedy beam search.
fn do_search(
  idx: VecIndex,
  query: List(Float),
  threshold: Float,
  k: Int,
) -> List(SearchResult) {
  case idx.entry_point {
    Error(Nil) -> []
    Ok(start) -> {
      let query = vector.normalize(query)
      // 1. Descend to Layer 0
      let ep_0 = descend_to_level(idx, query, start, idx.max_level, 1)

      // 2. Final search in Layer 0
      let layer_0 =
        dict.get(idx.layers, 0) |> result.unwrap(Layer(edges: dict.new()))
      let vec_ep = dict.get(idx.nodes, ep_0) |> result.unwrap(query)
      let ep_res =
        SearchResult(entity: ep_0, score: vector.dot_product(query, vec_ep))

      let results =
        greedy_search(
          idx.nodes,
          layer_0.edges,
          query,
          [ep_0],
          dict.new(),
          [ep_res],
          k * 10,
        )

      // Filter by threshold and take top-k
      results
      |> list.filter(fn(r) { r.score >=. threshold })
      |> list.sort(fn(a, b) { float.compare(b.score, a.score) })
      |> list.take(k)
    }
  }
}

fn greedy_search(
  nodes: Dict(fact.EntityId, List(Float)),
  edges: Dict(fact.EntityId, List(fact.EntityId)),
  query: List(Float),
  candidates: List(fact.EntityId),
  visited: Dict(fact.EntityId, Bool),
  results: List(SearchResult),
  budget: Int,
) -> List(SearchResult) {
  case budget <= 0 || list.is_empty(candidates) {
    True -> results
    False -> {
      // 1. Pop the best candidate (nearest to query) based on pre-calculated results or re-score
      let scored_candidates =
        list.filter_map(candidates, fn(eid) {
          case dict.get(nodes, eid) {
            Ok(v) ->
              Ok(SearchResult(entity: eid, score: vector.dot_product(query, v)))
            _ -> Error(Nil)
          }
        })
        |> list.sort(fn(a, b) { float.compare(b.score, a.score) })

      case scored_candidates {
        [] -> results
        [best, ..] -> {
          let rest_candidates =
            list.filter(candidates, fn(c) { c != best.entity })

          // 2. Decide whether to stop
          let furthest_res =
            results
            |> list.sort(fn(a, b) { float.compare(a.score, b.score) })
            |> list.first()

          let results_count = list.length(results)
          case furthest_res {
            Ok(furthest) -> {
              let stop = best.score <. furthest.score && results_count >= 20
              case stop {
                True -> results
                False -> {
                  // Explore neighbors
                  let neighbors =
                    dict.get(edges, best.entity)
                    |> unwrap_list()
                    |> list.filter(fn(n) { !dict.has_key(visited, n) })

                  let new_visited =
                    list.fold(neighbors, visited, fn(acc, n) {
                      dict.insert(acc, n, True)
                    })

                  let scored_neighbors =
                    list.filter_map(neighbors, fn(n) {
                      case dict.get(nodes, n) {
                        Ok(v) ->
                          Ok(SearchResult(
                            entity: n,
                            score: vector.dot_product(query, v),
                          ))
                        _ -> Error(Nil)
                      }
                    })

                  let new_candidates =
                    list.append(rest_candidates, neighbors)
                    |> list.unique()

                  let new_results =
                    list.append(results, scored_neighbors)
                    |> list.unique()
                    |> list.sort(fn(a, b) { float.compare(b.score, a.score) })
                    |> list.take(100)

                  greedy_search(
                    nodes,
                    edges,
                    query,
                    new_candidates,
                    new_visited,
                    new_results,
                    budget - 1,
                  )
                }
              }
            }
            Error(Nil) -> {
              // Explore neighbors of 'best'
              let neighbors =
                dict.get(edges, best.entity)
                |> unwrap_list()
                |> list.filter(fn(n) { !dict.has_key(visited, n) })

              let new_visited =
                list.fold(neighbors, visited, fn(acc, n) {
                  dict.insert(acc, n, True)
                })

              let scored_neighbors =
                list.filter_map(neighbors, fn(n) {
                  case dict.get(nodes, n) {
                    Ok(v) ->
                      Ok(SearchResult(
                        entity: n,
                        score: vector.dot_product(query, v),
                      ))
                    _ -> Error(Nil)
                  }
                })

              let new_candidates =
                list.append(rest_candidates, neighbors)
                |> list.unique()

              let new_results =
                list.append(results, scored_neighbors)
                |> list.unique()
                |> list.sort(fn(a, b) { float.compare(b.score, a.score) })
                |> list.take(100)

              greedy_search(
                nodes,
                edges,
                query,
                new_candidates,
                new_visited,
                new_results,
                budget - 1,
              )
            }
          }
        }
      }
    }
  }
}

// --- Delete ---

/// Remove a node from the index across all layers and repair edges.
pub fn delete(idx: VecIndex, entity: fact.EntityId) -> VecIndex {
  let nodes = dict.delete(idx.nodes, entity)

  // Repair each layer
  let layers =
    dict.map_values(idx.layers, fn(_, layer) {
      let neighbors = dict.get(layer.edges, entity) |> unwrap_list()
      let edges = dict.delete(layer.edges, entity)
      let repaired_edges =
        list.fold(neighbors, edges, fn(acc, n_id) {
          let existing = dict.get(acc, n_id) |> unwrap_list()
          let filtered = list.filter(existing, fn(e) { e != entity })
          dict.insert(acc, n_id, filtered)
        })
      Layer(edges: repaired_edges)
    })

  // Update entry point if necessary
  let new_entry = case idx.entry_point {
    Ok(ep) if ep == entity -> {
      // Pick any remaining node from Layer 0
      case dict.get(layers, 0) {
        Ok(l0) -> {
          case dict.keys(l0.edges) |> list.first() {
            Ok(k) -> Ok(k)
            Error(Nil) -> Error(Nil)
          }
        }
        Error(Nil) -> Error(Nil)
      }
    }
    other -> other
  }

  VecIndex(..idx, nodes: nodes, layers: layers, entry_point: new_entry)
}

// --- Helpers ---

/// Prune a neighbor list to max_neighbors, keeping the most similar.
fn prune_neighbors(
  max_neighbors: Int,
  node_id: fact.EntityId,
  candidates: List(fact.EntityId),
  nodes: Dict(fact.EntityId, List(Float)),
) -> List(fact.EntityId) {
  case dict.get(nodes, node_id) {
    Error(Nil) -> list.take(list.unique(candidates), max_neighbors)
    Ok(node_vec) -> {
      list.unique(candidates)
      |> list.filter_map(fn(c) {
        case dict.get(nodes, c) {
          Ok(v) -> Ok(#(c, vector.dot_product(node_vec, v)))
          Error(Nil) -> Error(Nil)
        }
      })
      |> list.sort(fn(a, b) { float.compare(b.1, a.1) })
      |> list.take(max_neighbors)
      |> list.map(fn(pair) { pair.0 })
    }
  }
}

fn unwrap_list(res: Result(List(a), Nil)) -> List(a) {
  case res {
    Ok(l) -> l
    Error(Nil) -> []
  }
}

/// Get the number of vectors in the index.
pub fn size(idx: VecIndex) -> Int {
  dict.size(idx.nodes)
}

/// Check if the index contains a given entity.
pub fn contains(idx: VecIndex, entity: fact.EntityId) -> Bool {
  dict.has_key(idx.nodes, entity)
}
