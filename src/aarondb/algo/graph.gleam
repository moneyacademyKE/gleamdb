import aarondb/fact.{type EntityId, Ref}
import aarondb/index
import aarondb/shared/state
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/set.{type Set}

/// Explicit local work limits for graph traversals.
///
/// A limit counts visited nodes, including the starting node. Callers that need
/// unbounded traversal must opt into it through the legacy APIs; new callers
/// should use the bounded variants below.
pub type TraversalLimits {
  TraversalLimits(max_visits: Int, max_results: Int)
}

/// Typed outcomes for bounded traversal requests.
pub type TraversalError {
  InvalidLimit
  VisitBudgetExceeded
  ResultLimitExceeded
}

pub fn traversal_limits(
  max_visits: Int,
  max_results: Int,
) -> Result(TraversalLimits, TraversalError) {
  case max_visits > 0 && max_results > 0 {
    True -> Ok(TraversalLimits(max_visits, max_results))
    False -> Error(InvalidLimit)
  }
}

/// Explicit local work limits for global graph algorithms.
///
/// Bounded global APIs construct at most `max_edges` selected reference edges,
/// admit at most `max_nodes` endpoints, and reject PageRank requests above
/// `max_iterations`. They return a typed error rather than producing a partial
/// graph result.
pub type GraphLimits {
  GraphLimits(max_nodes: Int, max_edges: Int, max_iterations: Int)
}

/// Typed outcomes for bounded global graph requests.
pub type GraphError {
  InvalidGraphLimit
  NodeBudgetExceeded
  EdgeBudgetExceeded
  IterationBudgetExceeded
  InvalidPageRankParameters
}

pub fn graph_limits(
  max_nodes: Int,
  max_edges: Int,
  max_iterations: Int,
) -> Result(GraphLimits, GraphError) {
  case max_nodes > 0 && max_edges > 0 && max_iterations > 0 {
    True -> Ok(GraphLimits(max_nodes, max_edges, max_iterations))
    False -> Error(InvalidGraphLimit)
  }
}

type Queue(a) {
  Queue(in: List(a), out: List(a))
}

fn new_queue() -> Queue(a) {
  Queue([], [])
}

fn push_queue(q: Queue(a), item: a) -> Queue(a) {
  Queue([item, ..q.in], q.out)
}

fn pop_queue(q: Queue(a)) -> Result(#(a, Queue(a)), Nil) {
  case q.out {
    [head, ..tail] -> Ok(#(head, Queue(q.in, tail)))
    [] ->
      case list.reverse(q.in) {
        [] -> Error(Nil)
        [head, ..tail] -> Ok(#(head, Queue([], tail)))
      }
  }
}

pub fn shortest_path(
  state: state.DbState,
  from: EntityId,
  to: EntityId,
  edge_attr: String,
  max_depth: Option(Int),
) -> Option(List(EntityId)) {
  bfs(
    state,
    edge_attr,
    to,
    new_queue() |> push_queue(#(from, 0)),
    set.new(),
    dict.new(),
    max_depth,
  )
}

fn bfs(
  state: state.DbState,
  attr: String,
  target: EntityId,
  q: Queue(#(EntityId, Int)),
  visited: Set(EntityId),
  parents: Dict(EntityId, EntityId),
  max_depth: Option(Int),
) -> Option(List(EntityId)) {
  case pop_queue(q) {
    Error(_) -> None
    // Queue empty, not found
    Ok(#(#(current, depth), new_q)) -> {
      case current == target {
        True -> Some(reconstruct_path(target, parents, []))
        False -> {
          let at_max = case max_depth {
            Some(max) -> depth >= max
            None -> False
          }
          case at_max {
            True -> bfs(state, attr, target, new_q, visited, parents, max_depth)
            False -> {
              // Get neighbors
              let neighbors = get_neighbors(state, current, attr)

              // Filter unvisited
              let new_neighbors =
                list.filter(neighbors, fn(n) { !set.contains(visited, n) })

              // Update visited and parents
              let new_visited =
                list.fold(new_neighbors, visited, fn(s, n) { set.insert(s, n) })
              let new_parents =
                list.fold(new_neighbors, parents, fn(p, n) {
                  dict.insert(p, n, current)
                })

              // Enqueue
              let next_q =
                list.fold(new_neighbors, new_q, fn(q_acc, n) {
                  push_queue(q_acc, #(n, depth + 1))
                })

              bfs(
                state,
                attr,
                target,
                next_q,
                new_visited,
                new_parents,
                max_depth,
              )
            }
          }
        }
      }
    }
  }
}

fn get_neighbors(
  state: state.DbState,
  entity: EntityId,
  attr: String,
) -> List(EntityId) {
  // Look up outgoing edges: entity -[attr]-> value (must be Ref)
  index.get_datoms_by_entity_attr(state.eavt, entity, attr)
  |> list.filter_map(fn(d) {
    case d.value {
      Ref(id) -> Ok(id)
      _ -> Error(Nil)
    }
  })
}

fn reconstruct_path(
  current: EntityId,
  parents: Dict(EntityId, EntityId),
  acc: List(EntityId),
) -> List(EntityId) {
  let new_acc = [current, ..acc]
  case dict.get(parents, current) {
    Ok(parent) -> reconstruct_path(parent, parents, new_acc)
    Error(_) -> new_acc
  }
}

pub fn pagerank(
  state: state.DbState,
  attr: String,
  damping: Float,
  iterations: Int,
) -> Dict(EntityId, Float) {
  let edges = build_graph(state, attr)
  let nodes = get_all_nodes(edges)
  case
    set.size(nodes) == 0 || damping <. 0.0 || damping >. 1.0 || iterations <= 0
  {
    True -> dict.new()
    False -> {
      let n = int.to_float(set.size(nodes))
      let initial_rank = 1.0 /. n
      let ranks =
        list.fold(set.to_list(nodes), dict.new(), fn(acc, node) {
          dict.insert(acc, node, initial_rank)
        })
      let #(incoming, out_degree) = preprocess_graph(edges, nodes)
      pagerank_iter(nodes, incoming, out_degree, ranks, damping, iterations, n)
    }
  }
}

pub fn pagerank_bounded(
  state: state.DbState,
  attr: String,
  damping: Float,
  iterations: Int,
  limits: GraphLimits,
) -> Result(Dict(EntityId, Float), GraphError) {
  let GraphLimits(_, _, max_iterations) = limits
  case damping <. 0.0 || damping >. 1.0 || iterations <= 0 {
    True -> Error(InvalidPageRankParameters)
    False -> {
      case iterations > max_iterations {
        True -> Error(IterationBudgetExceeded)
        False -> {
          case build_graph_bounded(state, attr, limits) {
            Error(error) -> Error(error)
            Ok(edges) -> Ok(pagerank_from_graph(edges, damping, iterations))
          }
        }
      }
    }
  }
}

fn pagerank_from_graph(
  edges: Graph,
  damping: Float,
  iterations: Int,
) -> Dict(EntityId, Float) {
  let nodes = get_all_nodes(edges)
  case set.size(nodes) == 0 {
    True -> dict.new()
    False -> {
      let n = int.to_float(set.size(nodes))
      let initial_rank = 1.0 /. n
      let ranks =
        list.fold(set.to_list(nodes), dict.new(), fn(acc, node) {
          dict.insert(acc, node, initial_rank)
        })
      let #(incoming, out_degree) = preprocess_graph(edges, nodes)
      pagerank_iter(nodes, incoming, out_degree, ranks, damping, iterations, n)
    }
  }
}

// Graph: Node -> List(Neighbor)
type Graph =
  Dict(EntityId, List(EntityId))

fn build_graph(state: state.DbState, attr: String) -> Graph {
  index.filter_by_attribute(state.aevt, attr)
  |> list.fold(dict.new(), fn(graph, d) {
    case d.value {
      Ref(target) -> {
        let source = d.entity
        let current_outgoing = dict.get(graph, source) |> result.unwrap([])
        dict.insert(graph, source, [target, ..current_outgoing])
      }
      _ -> graph
    }
  })
}

fn build_graph_bounded(
  state: state.DbState,
  attr: String,
  limits: GraphLimits,
) -> Result(Graph, GraphError) {
  let GraphLimits(max_nodes, max_edges, _) = limits
  build_graph_bounded_from_datoms(
    index.filter_by_attribute(state.aevt, attr),
    dict.new(),
    set.new(),
    0,
    max_nodes,
    max_edges,
  )
}

fn build_graph_bounded_from_datoms(
  datoms: List(fact.Datom),
  graph: Graph,
  nodes: Set(EntityId),
  edge_count: Int,
  max_nodes: Int,
  max_edges: Int,
) -> Result(Graph, GraphError) {
  case datoms {
    [] -> Ok(graph)
    [datom, ..rest] -> {
      case datom.value {
        Ref(target) -> {
          case edge_count >= max_edges {
            True -> Error(EdgeBudgetExceeded)
            False -> {
              let next_nodes =
                nodes |> set.insert(datom.entity) |> set.insert(target)
              case set.size(next_nodes) > max_nodes {
                True -> Error(NodeBudgetExceeded)
                False -> {
                  let outgoing =
                    dict.get(graph, datom.entity) |> result.unwrap([])
                  let next_graph =
                    dict.insert(graph, datom.entity, [target, ..outgoing])
                  build_graph_bounded_from_datoms(
                    rest,
                    next_graph,
                    next_nodes,
                    edge_count + 1,
                    max_nodes,
                    max_edges,
                  )
                }
              }
            }
          }
        }
        _ ->
          build_graph_bounded_from_datoms(
            rest,
            graph,
            nodes,
            edge_count,
            max_nodes,
            max_edges,
          )
      }
    }
  }
}

fn get_all_nodes(graph: Graph) -> Set(EntityId) {
  dict.fold(graph, set.new(), fn(nodes, source, targets) {
    let nodes = set.insert(nodes, source)
    list.fold(targets, nodes, set.insert)
  })
}

fn pagerank_iter(
  nodes: Set(EntityId),
  incoming: Dict(EntityId, List(EntityId)),
  out_degree: Dict(EntityId, Int),
  ranks: Dict(EntityId, Float),
  d: Float,
  iter: Int,
  n: Float,
) -> Dict(EntityId, Float) {
  case iter {
    0 -> ranks
    _ -> {
      let node_list = set.to_list(nodes)

      let next_ranks =
        list.fold(node_list, dict.new(), fn(acc, u) {
          let incoming_nodes = dict.get(incoming, u) |> result.unwrap([])
          let sum =
            list.fold(incoming_nodes, 0.0, fn(s, v) {
              let rank_v = dict.get(ranks, v) |> result.unwrap(0.0)
              let degree_v =
                dict.get(out_degree, v) |> result.unwrap(1) |> int.to_float
              s +. { rank_v /. degree_v }
            })
          let new_rank = { 1.0 -. d } /. n +. { d *. sum }
          dict.insert(acc, u, new_rank)
        })

      pagerank_iter(nodes, incoming, out_degree, next_ranks, d, iter - 1, n)
    }
  }
}

fn preprocess_graph(
  edges: Graph,
  _nodes: Set(fact.EntityId),
) -> #(Dict(fact.EntityId, List(fact.EntityId)), Dict(fact.EntityId, Int)) {
  let out_degree =
    dict.map_values(edges, fn(_, targets) { list.length(targets) })
  let incoming =
    dict.fold(edges, dict.new(), fn(acc, source, targets) {
      list.fold(targets, acc, fn(inner_acc, target) {
        let current = dict.get(inner_acc, target) |> result.unwrap([])
        dict.insert(inner_acc, target, [source, ..current])
      })
    })
  #(incoming, out_degree)
}

// --- Reachable: All nodes reachable from a starting node (transitive closure) ---

pub fn reachable(
  state: state.DbState,
  from: EntityId,
  edge_attr: String,
) -> List(EntityId) {
  reachable_bfs(
    state,
    edge_attr,
    new_queue() |> push_queue(from),
    set.from_list([from]),
  )
  |> set.to_list()
}

pub fn reachable_bounded(
  state: state.DbState,
  from: EntityId,
  edge_attr: String,
  limits: TraversalLimits,
) -> Result(List(EntityId), TraversalError) {
  let TraversalLimits(max_visits, max_results) = limits
  reachable_bounded_bfs(
    state,
    edge_attr,
    new_queue() |> push_queue(from),
    set.from_list([from]),
    max_visits,
    max_results,
  )
}

fn reachable_bounded_bfs(
  state: state.DbState,
  attr: String,
  q: Queue(EntityId),
  visited: Set(EntityId),
  max_visits: Int,
  max_results: Int,
) -> Result(List(EntityId), TraversalError) {
  case set.size(visited) > max_visits {
    True -> Error(VisitBudgetExceeded)
    False -> {
      case set.size(visited) > max_results {
        True -> Error(ResultLimitExceeded)
        False -> {
          case pop_queue(q) {
            Error(_) -> Ok(set.to_list(visited))
            Ok(#(current, new_q)) -> {
              let neighbors = get_neighbors(state, current, attr)
              let new_neighbors =
                list.filter(neighbors, fn(n) { !set.contains(visited, n) })
              let new_visited = list.fold(new_neighbors, visited, set.insert)
              let next_q = list.fold(new_neighbors, new_q, push_queue)
              reachable_bounded_bfs(
                state,
                attr,
                next_q,
                new_visited,
                max_visits,
                max_results,
              )
            }
          }
        }
      }
    }
  }
}

fn reachable_bfs(
  state: state.DbState,
  attr: String,
  q: Queue(EntityId),
  visited: Set(EntityId),
) -> Set(EntityId) {
  case pop_queue(q) {
    Error(_) -> visited
    Ok(#(current, new_q)) -> {
      let neighbors = get_neighbors(state, current, attr)
      let new_neighbors =
        list.filter(neighbors, fn(n) { !set.contains(visited, n) })
      let new_visited = list.fold(new_neighbors, visited, set.insert)
      let next_q = list.fold(new_neighbors, new_q, push_queue)
      reachable_bfs(state, attr, next_q, new_visited)
    }
  }
}

/// Labels directed flood-fill components after enforcing local graph limits.
pub fn connected_components_bounded(
  state: state.DbState,
  edge_attr: String,
  limits: GraphLimits,
) -> Result(Dict(EntityId, Int), GraphError) {
  case build_graph_bounded(state, edge_attr, limits) {
    Error(error) -> Error(error)
    Ok(graph) -> Ok(connected_components_from_graph(graph))
  }
}

fn connected_components_from_graph(graph: Graph) -> Dict(EntityId, Int) {
  cc_flood_graph(
    get_all_nodes(graph) |> set.to_list(),
    graph,
    set.new(),
    dict.new(),
    0,
  )
}

fn cc_flood_graph(
  remaining: List(EntityId),
  graph: Graph,
  visited: Set(EntityId),
  labels: Dict(EntityId, Int),
  component_id: Int,
) -> Dict(EntityId, Int) {
  case remaining {
    [] -> labels
    [node, ..rest] -> {
      case set.contains(visited, node) {
        True -> cc_flood_graph(rest, graph, visited, labels, component_id)
        False -> {
          let component_nodes = reachable_graph(graph, node)
          let next_visited = list.fold(component_nodes, visited, set.insert)
          let next_labels =
            list.fold(component_nodes, labels, fn(labels, member) {
              dict.insert(labels, member, component_id)
            })
          cc_flood_graph(
            rest,
            graph,
            next_visited,
            next_labels,
            component_id + 1,
          )
        }
      }
    }
  }
}

fn reachable_graph(graph: Graph, start: EntityId) -> List(EntityId) {
  reachable_graph_bfs(
    graph,
    new_queue() |> push_queue(start),
    set.from_list([start]),
  )
  |> set.to_list()
}

fn reachable_graph_bfs(
  graph: Graph,
  q: Queue(EntityId),
  visited: Set(EntityId),
) -> Set(EntityId) {
  case pop_queue(q) {
    Error(_) -> visited
    Ok(#(current, next_q)) -> {
      let unseen =
        dict.get(graph, current)
        |> result.unwrap([])
        |> list.filter(fn(node) { !set.contains(visited, node) })
      let next_visited = list.fold(unseen, visited, set.insert)
      let q = list.fold(unseen, next_q, push_queue)
      reachable_graph_bfs(graph, q, next_visited)
    }
  }
}

// --- ConnectedComponents: Label each node with a component ID ---

pub fn connected_components(
  state: state.DbState,
  edge_attr: String,
) -> Dict(EntityId, Int) {
  let graph = build_graph(state, edge_attr)
  connected_components_from_graph(graph)
}

// --- Neighbors: K-hop neighborhood (bounded BFS) ---

pub fn neighbors_khop(
  state: state.DbState,
  from: EntityId,
  edge_attr: String,
  max_depth: Int,
) -> List(EntityId) {
  khop_bfs(state, edge_attr, [#(from, 0)], set.from_list([from]), max_depth)
  |> set.delete(from)
  // Exclude the starting node
  |> set.to_list()
}

fn khop_bfs(
  state: state.DbState,
  attr: String,
  frontier: List(#(EntityId, Int)),
  visited: Set(EntityId),
  max_depth: Int,
) -> Set(EntityId) {
  case frontier {
    [] -> visited
    [#(current, depth), ..rest] -> {
      case depth >= max_depth {
        True -> khop_bfs(state, attr, rest, visited, max_depth)
        False -> {
          let neighbors = get_neighbors(state, current, attr)
          let new_neighbors =
            list.filter(neighbors, fn(n) { !set.contains(visited, n) })
          let new_visited = list.fold(new_neighbors, visited, set.insert)
          let new_frontier =
            list.fold(new_neighbors, rest, fn(acc, n) {
              list.append(acc, [#(n, depth + 1)])
            })
          khop_bfs(state, attr, new_frontier, new_visited, max_depth)
        }
      }
    }
  }
}

/// Detects directed cycles after enforcing local graph limits.
pub fn cycle_detect_bounded(
  state: state.DbState,
  edge_attr: String,
  limits: GraphLimits,
) -> Result(List(List(EntityId)), GraphError) {
  case build_graph_bounded(state, edge_attr, limits) {
    Error(error) -> Error(error)
    Ok(graph) -> Ok(cycle_detect_from_graph(graph))
  }
}

fn cycle_detect_from_graph(graph: Graph) -> List(List(EntityId)) {
  let node_list = get_all_nodes(graph) |> set.to_list()
  cd_search(graph, node_list, set.new(), set.new(), [], [])
}

// --- CycleDetect: Find all cycles in a directed graph (DFS back-edge) ---

pub fn cycle_detect(
  state: state.DbState,
  edge_attr: String,
) -> List(List(EntityId)) {
  let graph = build_graph(state, edge_attr)
  cycle_detect_from_graph(graph)
}

fn cd_search(
  graph: Graph,
  remaining: List(EntityId),
  visited: Set(EntityId),
  in_stack: Set(EntityId),
  stack: List(EntityId),
  cycles: List(List(EntityId)),
) -> List(List(EntityId)) {
  case remaining {
    [] -> cycles
    [node, ..rest] -> {
      case set.contains(visited, node) {
        True -> cd_search(graph, rest, visited, in_stack, stack, cycles)
        False -> {
          let #(new_visited, new_in_stack, _, new_cycles) =
            cd_dfs(graph, node, visited, in_stack, [node, ..stack], cycles)
          cd_search(graph, rest, new_visited, new_in_stack, stack, new_cycles)
        }
      }
    }
  }
}

fn cd_dfs(
  graph: Graph,
  node: EntityId,
  visited: Set(EntityId),
  in_stack: Set(EntityId),
  stack: List(EntityId),
  cycles: List(List(EntityId)),
) -> #(Set(EntityId), Set(EntityId), List(EntityId), List(List(EntityId))) {
  let visited = set.insert(visited, node)
  let in_stack = set.insert(in_stack, node)
  let neighbors = dict.get(graph, node) |> result.unwrap([])

  let #(final_visited, final_in_stack, final_stack, final_cycles) =
    list.fold(neighbors, #(visited, in_stack, stack, cycles), fn(acc, neighbor) {
      let #(v, is, s, c) = acc
      case set.contains(is, neighbor) {
        True -> {
          // Back edge found — extract cycle from stack
          let cycle = extract_cycle(s, neighbor)
          #(v, is, s, [cycle, ..c])
        }
        False -> {
          case set.contains(v, neighbor) {
            True -> acc
            False -> cd_dfs(graph, neighbor, v, is, [neighbor, ..s], c)
          }
        }
      }
    })

  let final_in_stack = set.delete(final_in_stack, node)
  #(final_visited, final_in_stack, final_stack, final_cycles)
}

fn extract_cycle(stack: List(EntityId), target: EntityId) -> List(EntityId) {
  extract_cycle_loop(stack, target, [])
}

fn extract_cycle_loop(
  stack: List(EntityId),
  target: EntityId,
  acc: List(EntityId),
) -> List(EntityId) {
  case stack {
    [] -> acc
    [head, ..tail] -> {
      let new_acc = [head, ..acc]
      case head == target {
        True -> new_acc
        False -> extract_cycle_loop(tail, target, new_acc)
      }
    }
  }
}

/// Runs directed Brandes centrality after enforcing local graph limits.
pub fn betweenness_centrality_bounded(
  state: state.DbState,
  edge_attr: String,
  limits: GraphLimits,
) -> Result(Dict(EntityId, Float), GraphError) {
  case build_graph_bounded(state, edge_attr, limits) {
    Error(error) -> Error(error)
    Ok(graph) -> Ok(betweenness_from_graph(graph))
  }
}

fn betweenness_from_graph(graph: Graph) -> Dict(EntityId, Float) {
  let node_list = get_all_nodes(graph) |> set.to_list()
  let scores =
    list.fold(node_list, dict.new(), fn(acc, n) { dict.insert(acc, n, 0.0) })
  list.fold(node_list, scores, fn(acc, source) {
    bc_from_source(graph, source, node_list, acc)
  })
}

// --- BetweennessCentrality: Brandes' algorithm O(V*E) ---

pub fn betweenness_centrality(
  state: state.DbState,
  edge_attr: String,
) -> Dict(EntityId, Float) {
  let graph = build_graph(state, edge_attr)
  betweenness_from_graph(graph)
}

fn bc_from_source(
  graph: Graph,
  source: EntityId,
  _all_nodes: List(EntityId),
  scores: Dict(EntityId, Float),
) -> Dict(EntityId, Float) {
  // BFS phase: compute shortest path counts and predecessors
  let #(order, sigma, pred) = bc_bfs(graph, source)

  // Accumulation phase: back-propagate dependency
  let delta =
    list.fold(order, dict.new(), fn(acc, n) { dict.insert(acc, n, 0.0) })

  // Process in reverse BFS order (skip source)
  let reversed = list.reverse(order)
  let delta =
    list.fold(reversed, delta, fn(d, w) {
      let predecessors = dict.get(pred, w) |> result.unwrap([])
      let sigma_w = dict.get(sigma, w) |> result.unwrap(1.0)
      let delta_w = dict.get(d, w) |> result.unwrap(0.0)

      list.fold(predecessors, d, fn(d_acc, v) {
        let sigma_v = dict.get(sigma, v) |> result.unwrap(1.0)
        let delta_v = dict.get(d_acc, v) |> result.unwrap(0.0)
        let contribution = { sigma_v /. sigma_w } *. { 1.0 +. delta_w }
        dict.insert(d_acc, v, delta_v +. contribution)
      })
    })

  // Add delta to scores (exclude source)
  list.fold(order, scores, fn(s, v) {
    case v == source {
      True -> s
      False -> {
        let current = dict.get(s, v) |> result.unwrap(0.0)
        let d = dict.get(delta, v) |> result.unwrap(0.0)
        dict.insert(s, v, current +. d)
      }
    }
  })
}

fn bc_bfs(
  graph: Graph,
  source: EntityId,
) -> #(List(EntityId), Dict(EntityId, Float), Dict(EntityId, List(EntityId))) {
  let sigma = dict.from_list([#(source, 1.0)])
  let dist = dict.from_list([#(source, 0)])
  let pred = dict.new()
  let order = []
  let q = new_queue() |> push_queue(source)

  bc_bfs_loop(graph, q, sigma, dist, pred, order)
}

fn bc_bfs_loop(
  graph: Graph,
  q: Queue(EntityId),
  sigma: Dict(EntityId, Float),
  dist: Dict(EntityId, Int),
  pred: Dict(EntityId, List(EntityId)),
  order: List(EntityId),
) -> #(List(EntityId), Dict(EntityId, Float), Dict(EntityId, List(EntityId))) {
  case pop_queue(q) {
    Error(_) -> #(order, sigma, pred)
    Ok(#(v, new_q)) -> {
      let new_order = list.append(order, [v])
      let v_dist = dict.get(dist, v) |> result.unwrap(0)
      let neighbors = dict.get(graph, v) |> result.unwrap([])

      let #(new_q2, new_sigma, new_dist, new_pred) =
        list.fold(neighbors, #(new_q, sigma, dist, pred), fn(acc, w) {
          let #(q_acc, s_acc, d_acc, p_acc) = acc
          case dict.get(d_acc, w) {
            Error(_) -> {
              // First visit
              let d_acc = dict.insert(d_acc, w, v_dist + 1)
              let q_acc = push_queue(q_acc, w)
              let sv = dict.get(s_acc, v) |> result.unwrap(1.0)
              let s_acc = dict.insert(s_acc, w, sv)
              let p_acc = dict.insert(p_acc, w, [v])
              #(q_acc, s_acc, d_acc, p_acc)
            }
            Ok(w_dist) -> {
              case w_dist == v_dist + 1 {
                True -> {
                  // Another shortest path found
                  let sw = dict.get(s_acc, w) |> result.unwrap(0.0)
                  let sv = dict.get(s_acc, v) |> result.unwrap(1.0)
                  let s_acc = dict.insert(s_acc, w, sw +. sv)
                  let wp = dict.get(p_acc, w) |> result.unwrap([])
                  let p_acc = dict.insert(p_acc, w, [v, ..wp])
                  #(q_acc, s_acc, d_acc, p_acc)
                }
                False -> acc
              }
            }
          }
        })

      bc_bfs_loop(graph, new_q2, new_sigma, new_dist, new_pred, new_order)
    }
  }
}

/// Topologically sorts a bounded directed graph or returns typed budget errors.
pub fn topological_sort_bounded(
  state: state.DbState,
  edge_attr: String,
  limits: GraphLimits,
) -> Result(Result(List(EntityId), List(EntityId)), GraphError) {
  case build_graph_bounded(state, edge_attr, limits) {
    Error(error) -> Error(error)
    Ok(graph) -> Ok(topological_sort_from_graph(graph))
  }
}

fn topological_sort_from_graph(
  graph: Graph,
) -> Result(List(EntityId), List(EntityId)) {
  let all_nodes = get_all_nodes(graph)
  let in_degree =
    dict.fold(
      graph,
      list.fold(set.to_list(all_nodes), dict.new(), fn(acc, n) {
        dict.insert(acc, n, 0)
      }),
      fn(acc, _source, targets) {
        list.fold(targets, acc, fn(inner, target) {
          let current = dict.get(inner, target) |> result.unwrap(0)
          dict.insert(inner, target, current + 1)
        })
      },
    )
  let zero_in =
    dict.fold(in_degree, [], fn(acc, node, degree) {
      case degree == 0 {
        True -> [node, ..acc]
        False -> acc
      }
    })
  topo_kahn(
    graph,
    list.fold(zero_in, new_queue(), push_queue),
    in_degree,
    [],
    set.size(all_nodes),
  )
}

// --- TopologicalSort: Kahn's algorithm (BFS-based) ---

pub fn topological_sort(
  state: state.DbState,
  edge_attr: String,
) -> Result(List(EntityId), List(EntityId)) {
  let graph = build_graph(state, edge_attr)
  topological_sort_from_graph(graph)
}

fn topo_kahn(
  graph: Graph,
  q: Queue(EntityId),
  in_degree: Dict(EntityId, Int),
  order: List(EntityId),
  total: Int,
) -> Result(List(EntityId), List(EntityId)) {
  case pop_queue(q) {
    Error(_) -> {
      case list.length(order) == total {
        True -> Ok(list.reverse(order))
        False -> {
          // Remaining nodes form cycles
          let cycle_nodes =
            dict.fold(in_degree, [], fn(acc, node, deg) {
              case deg > 0 {
                True -> [node, ..acc]
                False -> acc
              }
            })
          Error(cycle_nodes)
        }
      }
    }
    Ok(#(node, new_q)) -> {
      let new_order = [node, ..order]
      let neighbors = dict.get(graph, node) |> result.unwrap([])

      let #(next_q, next_in) =
        list.fold(neighbors, #(new_q, in_degree), fn(acc, neighbor) {
          let #(q_acc, id_acc) = acc
          let new_deg = { dict.get(id_acc, neighbor) |> result.unwrap(1) } - 1
          let id_acc = dict.insert(id_acc, neighbor, new_deg)
          case new_deg {
            0 -> #(push_queue(q_acc, neighbor), id_acc)
            _ -> #(q_acc, id_acc)
          }
        })

      topo_kahn(graph, next_q, next_in, new_order, total)
    }
  }
}

// --- StronglyConnectedComponents: Tarjan's algorithm O(V+E) ---

pub type TarjanState {
  TarjanState(
    index: Int,
    indices: Dict(EntityId, Int),
    lowlinks: Dict(EntityId, Int),
    on_stack: Set(EntityId),
    stack: List(EntityId),
    components: Dict(EntityId, Int),
    comp_id: Int,
  )
}

pub fn strongly_connected_components(
  state: state.DbState,
  edge_attr: String,
) -> Dict(EntityId, Int) {
  let graph = build_graph(state, edge_attr)
  strongly_connected_components_from_graph(graph)
}

/// Labels strongly connected components after enforcing local graph limits.
pub fn strongly_connected_components_bounded(
  state: state.DbState,
  edge_attr: String,
  limits: GraphLimits,
) -> Result(Dict(EntityId, Int), GraphError) {
  case build_graph_bounded(state, edge_attr, limits) {
    Error(error) -> Error(error)
    Ok(graph) -> Ok(strongly_connected_components_from_graph(graph))
  }
}

fn strongly_connected_components_from_graph(
  graph: Graph,
) -> Dict(EntityId, Int) {
  let all_nodes = get_all_nodes(graph)
  let ts =
    TarjanState(
      index: 0,
      indices: dict.new(),
      lowlinks: dict.new(),
      on_stack: set.new(),
      stack: [],
      components: dict.new(),
      comp_id: 0,
    )
  let final_ts =
    set.fold(all_nodes, ts, fn(ts, node) {
      case dict.has_key(ts.indices, node) {
        True -> ts
        False -> tarjan_dfs(graph, node, ts)
      }
    })
  final_ts.components
}

fn tarjan_dfs(graph: Graph, node: EntityId, ts: TarjanState) -> TarjanState {
  let ts =
    TarjanState(
      ..ts,
      indices: dict.insert(ts.indices, node, ts.index),
      lowlinks: dict.insert(ts.lowlinks, node, ts.index),
      index: ts.index + 1,
      stack: [node, ..ts.stack],
      on_stack: set.insert(ts.on_stack, node),
    )

  let neighbors = dict.get(graph, node) |> result.unwrap([])

  let ts =
    list.fold(neighbors, ts, fn(ts, w) {
      case dict.has_key(ts.indices, w) {
        False -> {
          // Recurse
          let ts = tarjan_dfs(graph, w, ts)
          let node_low = dict.get(ts.lowlinks, node) |> result.unwrap(0)
          let w_low = dict.get(ts.lowlinks, w) |> result.unwrap(0)
          TarjanState(
            ..ts,
            lowlinks: dict.insert(ts.lowlinks, node, int.min(node_low, w_low)),
          )
        }
        True -> {
          case set.contains(ts.on_stack, w) {
            True -> {
              let node_low = dict.get(ts.lowlinks, node) |> result.unwrap(0)
              let w_idx = dict.get(ts.indices, w) |> result.unwrap(0)
              TarjanState(
                ..ts,
                lowlinks: dict.insert(
                  ts.lowlinks,
                  node,
                  int.min(node_low, w_idx),
                ),
              )
            }
            False -> ts
          }
        }
      }
    })

  // If node is a root of an SCC, pop stack
  let node_low = dict.get(ts.lowlinks, node) |> result.unwrap(0)
  let node_idx = dict.get(ts.indices, node) |> result.unwrap(-1)

  case node_low == node_idx {
    True -> pop_scc(ts, node)
    False -> ts
  }
}

fn pop_scc(ts: TarjanState, root: EntityId) -> TarjanState {
  case ts.stack {
    [] -> ts
    [top, ..rest] -> {
      let ts =
        TarjanState(
          ..ts,
          stack: rest,
          on_stack: set.delete(ts.on_stack, top),
          components: dict.insert(ts.components, top, ts.comp_id),
        )
      case top == root {
        True -> TarjanState(..ts, comp_id: ts.comp_id + 1)
        False -> pop_scc(ts, root)
      }
    }
  }
}
