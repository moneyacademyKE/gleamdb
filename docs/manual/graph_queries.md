# Graph Query Contract

AaronDB graph clauses operate over **directed** reference-valued facts in the local in-memory database. This document defines the behavior callers can rely on today, and the limits that keep the feature Beta rather than pretending it is a distributed graph engine.

## Graph model

- A graph edge is one datom of the form `entity -[edge attribute]-> Ref(target)`.
- Only outgoing `Ref` values participate. Scalar values on the selected attribute are ignored.
- Edges are directed. A fact from `A` to `B` does not imply an edge from `B` to `A`.
- Duplicate asserted edges are represented by the database's datom/index semantics; callers must not rely on duplicate edges producing duplicate traversal or ranking results.
- Self-loops are valid directed edges. They are visible to cycle detection and cause topological sort to reject the graph as cyclic.
- Nodes are discovered from edge endpoints. Isolated entities with no selected edge are not graph nodes for global algorithms.

## Traversal and path semantics

- `shortest_path` uses unweighted breadth-first search and returns a minimum-hop directed path, including both endpoints. No result means no directed path exists.
- `max_depth` bounds expansion by hop count. `Some(0)` permits only the trivial path from a node to itself; a negative bound expands no edges.
- `reachable` returns the directed transitive closure **including the start node**, even when it has no outgoing edges.
- `neighbors` returns unique directed neighbors within at most `depth` hops and excludes the start node. A depth of zero or less returns no nodes.
- Traversal is local to one `DbState`; it has no source provenance, remote fan-out, migration, failover, or HA semantics.

## Global algorithm semantics

- `connected_components` follows outgoing edges during flood-fill. It is not an undirected/weak-components operation.
- `strongly_connected_components` uses directed mutual reachability.
- `cycle_detect` detects directed DFS back-edges. Its output is diagnostic: callers must not depend on cycle count, orientation, or list order.
- `topological_sort` succeeds only for directed acyclic graphs. It returns `Error(cycle_nodes)` when cycles remain; order among otherwise independent nodes is not contractual.
- `betweenness_centrality` runs unweighted directed Brandes traversal. It is local and has `O(V*E)` worst-case work.
- `pagerank` runs a fixed number of local iterations over directed edges. It returns an empty map for an empty graph or invalid parameters (`damping` outside `[0.0, 1.0]`, or non-positive iterations). Rank-map order is not contractual.

## Resource and maturity limits

The APIs do not currently expose cancellation, node/edge budgets, timeout controls, benchmark envelopes, or distributed execution. Global algorithms materialize the selected local graph and should be used only on caller-bounded datasets. AaronDB makes no throughput, memory, latency, or distributed-consistency claim for graph processing yet.
