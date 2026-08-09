# Graph benchmark evidence

Run from the repository root:

    gleam run -m graph_benchmark

The harness constructs all fixtures in one local BEAM process and runs reachable
traversal, PageRank (20 iterations), cycle detection, and strongly connected
components for each. It is a reproducible regression fixture, not a portable
latency or memory SLA.

## Fixture shapes

| Fixture | Shape | Edges |
| --- | --- | ---: |
| Sparse | five-node directed path | 4 |
| Dense | complete directed graph over five nodes, excluding self-loops | 20 |
| Cyclic | three-node cycle with an outgoing tail | 4 |
| Disconnected | three independent directed pairs | 3 |
| Chain | 99-node directed chain | 98 |
| Hub | one source with 99 outgoing edges | 98 |

## Recorded local run

Environment: macOS, local Gleam/Erlang toolchain. Command: `gleam run -m graph_benchmark`.

| Fixture | Total selected operations |
| --- | ---: |
| Sparse | 1 ms |
| Dense | <1 ms |
| Cyclic | <1 ms |
| Disconnected | <1 ms |
| Chain | 1 ms |
| Hub | 1 ms |

Sub-millisecond values are rendered as `0` by the integer-millisecond harness;
they must not be read as a sub-millisecond production guarantee. Re-run the
command on the deployment environment before making capacity decisions.

## Boundaries

- The harness only demonstrates local correctness and a small regression envelope.
- `reachable_bounded` and the bounded global graph APIs are the supported paths
  for arbitrary local data; they return typed budget errors instead of partial
  results.
- Legacy unbounded APIs remain compatibility paths and are not the
  resource-bounded Stable contract.
