# Stable-local evidence index

AaronDB uses **Stable** only for a documented local contract with committed
correctness, lifecycle, failure, resource-bound, and reproducible evidence.
This page indexes that evidence so a maturity label is auditable rather than a
marketing claim. All benchmark results are local regression samples, not
portable latency, throughput, memory, capacity, or availability guarantees.

## Shared verification

Every pull request runs the following checks in [CI](../.github/workflows/ci.yml):

- `gleam format --check src test bench`
- `gleam docs build`
- `gleam test` (including deterministic distributed-harness mutants)
- `actionlint`
- Vector/HNSW, BM25, graph, local-federation, and temporal/diff evidence
  harnesses

Run the same commands from the repository root before relying on a new build.
The harnesses use one local BEAM runtime and deterministic committed fixtures
where their contracts require it.

## Evidence by supported contract

| Contract | Correctness and lifecycle evidence | Failure/resource evidence | Reproducible report or harness |
| --- | --- | --- | --- |
| [Vector/HNSW](manual/vector_search.md) | `test/aarondb/vector_stable_evidence_test.gleam`: exact oracle, ordering, committed corpus, replace/delete, 1,000-operation churn | validated vector dimension, magnitude, threshold, and limit errors | [report](reports/2026-08-08-vector-hnsw-evidence.md); `gleam run -m vector_hnsw_benchmark` |
| [BM25](manual/bm25_search.md) | `test/aarondb/bm25_stable_evidence_test.gleam`: Analyzer v1, golden ranks, replacement/removal, rebuild equivalence | invalid parameter handling; immutable sequential caller-owned boundary | [correctness report](reports/2026-08-08-bm25-correctness-evidence.md), [benchmark](reports/2026-08-08-bm25-benchmark.md); `gleam run -m bm25_benchmark` |
| [Graph](manual/graph_queries.md) | `test/aarondb/graph_algo_test.gleam` and `graph_traversal_test.gleam`: directed canonical fixtures and algorithm invariants | typed traversal/global node, edge, result, visit, and iteration budgets | [benchmark](benchmarks/graph.md); `gleam run -m graph_benchmark` |
| [Local federation](manual/local_federation.md) | `test/aarondb/federation_contract_test.gleam`: schema admission, ordering, provenance, duplicate identities, source lifecycle | typed unavailable/timeout failures; fail-fast with no partial result | [benchmark](benchmarks/local_federation.md); `gleam run -m federation_benchmark` |
| [Temporal querying and diff](manual/temporal_diff.md) | `test/aarondb/bitemporal_test.gleam` and `diff_test.gleam`: snapshot lifecycle, deterministic diffs, partition invariant | typed scan/range budget errors; no partial result | [benchmark](benchmarks/temporal_diff.md); `gleam run -m temporal_diff_benchmark` |
| [Reactive subscriptions](manual/reactive_subscriptions.md) | `test/aarondb/reactive_test.gleam`: initial/delta ordering, unsubscribe, stopped-subscriber cleanup | local mailbox boundary; no replay, acknowledgement, or bounded queue | contract tests run in `gleam test` |
| [Cognitive explicit-fact solver](features/cognitive_memory.md) | `test/aarondb/cognitive_contract_test.gleam`: relevance defaults, numeric maximum, update/retract lifecycle | threshold semantics and local-only solver boundary | contract tests run in `gleam test` |
| [Virtual predicates](manual/virtual_predicates.md) | virtual-predicate integration tests exercise ordered adapter rows | typed adapter failure/timeout, invalid limit, and overflow fail-closed behavior | contract tests run in `gleam test` |
| [Mnesia single-node recovery](manual/mnesia_recovery.md) | `test/aarondb/history_test.gleam`: recovery and failing-storage no-mutation behavior | startup, schema mismatch, and aborted transaction errors are typed; incompatible tables are never reset | isolated suite: `ERL_FLAGS="-mnesia dir <temporary-directory>" gleam test` |
| [Failure and trust boundaries](manual/failure_boundaries.md) | `test/aarondb/ergonomics_test.gleam`: timeout-aware actor management APIs | safe Erlang-term decoding, malformed data errors, and documented compatibility helpers | contract tests run in `gleam test` |
| [Local MCP stdio](manual/mcp_stdio.md) | `test/aarondb/mcp_stdio_test.gleam`: request parsing, protocol errors, notifications, and supported lifecycle dispatch | local synchronous backpressure, notification suppression, EOF shutdown; no network transport or remote authentication | `sh scripts/mcp_stdio_conformance.sh`: real stdin/stdout/stderr child-process lifecycle harness, run by CI |
| [Cluster operations and recovery](manual/cluster_operations_runbook.md) | operator bootstrap, status/diagnosis, backup/restore, rotation, alarms, and incident procedures | runbook is library/runtime contract; packaging must expose equivalent commands |


## Compatibility and unsupported surfaces

Legacy unbounded graph/temporal/diff APIs remain compatibility paths, not the
Stable resource-bounded API. Sharding remains Beta; Mnesia is a
recovery-oriented single-node adapter; local stdio MCP is not a network server;
Raft is inactive. These boundaries are listed explicitly in
[Feature Maturity](feature_maturity.md).
