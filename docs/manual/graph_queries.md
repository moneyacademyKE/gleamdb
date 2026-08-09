# Graph Query Contract

AaronDB graph clauses operate over **directed** reference-valued facts in one local `DbState`. This is a bounded local analytics contract, not a distributed graph service.

## Graph model

- A graph edge is one datom of the form `entity -[edge attribute]-> Ref(target)`.
- Only outgoing `Ref` values participate. Scalar values on the selected attribute are ignored.
- Edges are directed. A fact from `A` to `B` does not imply an edge from `B` to `A`.
- Duplicate asserted edges follow the database's datom/index semantics; callers must not rely on duplicate edges producing duplicate traversal or ranking results.
- Self-loops are valid directed edges. They are visible to cycle detection and cause topological sort to reject the graph as cyclic.
- Nodes are discovered from edge endpoints. Isolated entities with no selected edge are not graph nodes for global algorithms.

## Traversal and path semantics

- `shortest_path` uses unweighted breadth-first search and returns a minimum-hop directed path, including both endpoints. No result means no directed path exists.
- `max_depth` bounds expansion by hop count. `Some(0)` permits only the trivial path from a node to itself; a negative bound expands no edges.
- `reachable` returns the directed transitive closure **including the start node**, even when it has no outgoing edges.
- `neighbors` returns unique directed neighbors within at most `depth` hops and excludes the start node. A depth of zero or less returns no nodes.

## Global algorithm semantics

- `connected_components` follows outgoing edges during flood-fill. It is not an undirected/weak-components operation.
- `strongly_connected_components` uses directed mutual reachability.
- `cycle_detect` detects directed DFS back-edges. Its output is diagnostic: callers must not depend on cycle count, orientation, or list order.
- `topological_sort` succeeds only for directed acyclic graphs. It returns `Error(cycle_nodes)` when cycles remain; order among otherwise independent nodes is not contractual.
- `betweenness_centrality` runs unweighted directed Brandes traversal. It is local and has `O(V*E)` worst-case work.
- `pagerank` runs a fixed number of local iterations over directed edges. It returns an empty map for an empty graph or invalid parameters (`damping` outside `[0.0, 1.0]`, or non-positive iterations). Rank-map order is not contractual.

## Bounded APIs

New callers traversing arbitrary data should construct `traversal_limits(max_visits, max_results)` and use `reachable_bounded`.

- Both limits must be positive.
- The start node counts against both limits.
- Over-budget traversal returns `VisitBudgetExceeded` or `ResultLimitExceeded`; invalid limits return `InvalidLimit` before traversal begins.

New callers running graph-wide work should construct `graph_limits(max_nodes, max_edges, max_iterations)` and use:

- `pagerank_bounded`
- `connected_components_bounded`
- `cycle_detect_bounded`
- `betweenness_centrality_bounded`
- `topological_sort_bounded`
- `strongly_connected_components_bounded`

All limits must be positive. The bounded APIs fail without returning partial graph results with `InvalidGraphLimit`, `NodeBudgetExceeded`, `EdgeBudgetExceeded`, or `IterationBudgetExceeded`. `pagerank_bounded` additionally returns `InvalidPageRankParameters` for invalid damping or iterations. `topological_sort_bounded` preserves the legacy nested result: an outer graph-budget `Result` and an inner DAG/cycle result.

## Evidence and scope

Canonical and budget regression tests cover the public directed graph operators. The reproducible fixture harness (`gleam run -m graph_benchmark`) covers sparse, dense, cyclic, disconnected, chain, and hub graphs; recorded method/results are in [Graph benchmark evidence](../benchmarks/graph.md).

Legacy APIs preserve unbounded local behavior for compatibility. The Stable graph contract is the bounded local API. It does not imply cancellation, deadlines, remote execution, global snapshots, high availability, or universal throughput/memory/latency guarantees.
