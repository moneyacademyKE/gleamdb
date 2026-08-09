# Graph Algorithms (Native Predicates)

AaronDB provides **nine local directed graph algorithms** as Datalog body clauses. They operate over reference-valued facts in one in-memory `DbState`; they are not a distributed graph service.

The authoritative behavior and resource contract is [Graph Query Contract](../manual/graph_queries.md). That document overrides historical examples or performance claims.

## Predicate reference

| DSL Function | Algorithm | Directed semantics | Work profile |
| --- | --- | --- | --- |
| `q.shortest_path` | breadth-first search | Minimum-hop path following outgoing edges | `O(V + E)` in selected local graph |
| `q.pagerank` | fixed-iteration power method | Incoming rank over outgoing edges | `O(V × iterations)` |
| `q.reachable` | breadth-first flood | Directed closure, including source | `O(V + E)` |
| `q.connected_components` | directed flood-fill | Labels nodes reached by outgoing-edge floods; **not weak/undirected components** | `O(V + E)` per flood in worst case |
| `q.neighbors` | depth-bounded breadth-first search | Unique outgoing neighbors within depth | bounded by requested depth, not total work |
| `q.cycle_detect` | DFS back-edge detection | Directed cycles | `O(V + E)` |
| `q.betweenness_centrality` | unweighted directed Brandes | Directed shortest paths | `O(V × E)` |
| `q.topological_sort` | Kahn's algorithm | Directed DAG ordering | `O(V + E)` |
| `q.strongly_connected_components` | Tarjan's algorithm | Mutual directed reachability | `O(V + E)` |

## Contracts worth knowing

- Edges are `entity -[attribute]-> Ref(target)`. Scalar values are ignored.
- Self-loops are valid edges, are cycles, and cause topological sorting to fail.
- Nodes are discovered from selected edge endpoints; isolated entities are not included in global graph algorithms.
- `shortest_path` is unweighted and includes both endpoints.
- `reachable` includes its source. `neighbors` excludes its source and returns no nodes for depth zero or less.
- PageRank returns an empty map for an empty graph, invalid damping outside `0.0..1.0`, or non-positive iterations.
- Topological ordering among independent nodes and cycle-detection output ordering are intentionally unspecified.

## Bounded traversal

Legacy APIs remain for compatibility. New callers traversing arbitrary local data should use `graph.traversal_limits` with `graph.reachable_bounded`:

- Both visit and result limits must be positive.
- The start node counts against both limits.
- Exceeded work returns `VisitBudgetExceeded` or `ResultLimitExceeded`; invalid limits return `InvalidLimit`.

Global algorithms still materialize the selected local graph through legacy APIs. New callers use the bounded global entry points, which return typed node/edge/iteration budget errors rather than partial results. The Stable graph contract remains local-only: it does not add cancellation, remote execution, global snapshots, high availability, or universal throughput/memory/latency guarantees.

