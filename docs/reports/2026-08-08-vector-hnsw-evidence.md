# Vector/HNSW Evidence Report — 2026-08-08

## Scope

This report records reproducible local evidence for AaronDB's in-memory
`aarondb/vec_index` HNSW implementation. It is a regression and operational
sample, **not** a portable performance SLA.

## Reproduction

```text
gleam run -m vector_hnsw_benchmark
```

The harness lives in `src/vector_hnsw_benchmark.gleam` so Gleam can execute it
without external scripts. It creates a deterministic corpus of 1,000
8-dimensional non-zero vectors, builds an HNSW index with `max_neighbors: 32`,
`search_budget: 1000`, deterministic level zero, then compares 100 top-10 HNSW
queries with `exact_search`.

## Environment

| Field | Value |
|---|---|
| Date | 2026-08-08 |
| Host | macOS local development machine |
| Runtime | Gleam/Erlang dev target |
| Corpus | 1,000 deterministic vectors, 8 dimensions |
| Queries | 100 deterministic top-10 cosine searches |
| HNSW config | `max_neighbors: 32`, `search_budget: 1000`, fixed level 0 |

## Measured sample

| Metric | Result |
|---|---:|
| Index build | 14,533 ms |
| HNSW queries, total | 1,799 ms |
| HNSW query p50 | 18 ms |
| HNSW query p95 | 20 ms |
| Exact-query timing | below 1 ms precision of this millisecond harness |
| Recall@10 vs exact | 1.00 |

## Correctness regression evidence

In addition to the benchmark harness:

- `test/aarondb/vector_stable_evidence_test.gleam` checks deterministic graph
  construction, exact-oracle ordering, a committed semantic corpus, and 1,000
  mixed insert/replace/delete operations.
- The committed small corpus reports recall@5 = 1.00.
- The lifecycle soak reports recall@10 = 1.00 and verifies no returned entity
  has been deleted.
- Invalid empty, zero-magnitude, dimension-mismatched, threshold, and result
  limit inputs are tested through the validated `try_*` API.

## Interpretation and limits

The result is valid only for the stated corpus, configuration, runtime, and
machine. Production `VecIndex.new()` uses randomized levels and remains
approximate. This report deliberately makes no universal latency, memory,
complexity, or recall claim. Re-run the harness on a target deployment before
using its numbers for capacity planning.
