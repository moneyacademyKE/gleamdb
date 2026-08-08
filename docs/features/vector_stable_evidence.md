# Vector/HNSW Stable-Evidence Checklist

**Status:** Planned after PR #8 baseline merge (`f0fe892`).

## Goal

Promote `aarondb/vec_index` from Beta to Stable only after its approximate-search behavior is measured against a deterministic exact oracle and its mutation lifecycle has repeatable evidence.

## Tasks

1. **Exact oracle and shared result contract**
   - Add a finite-corpus exact cosine-search implementation with the same validation, threshold, ordering, and result shape as HNSW.
   - Define deterministic ties: ascending entity ID after descending score.
   - Done when exact and approximate searches can be compared mechanically in tests and benchmarks.

2. **Deterministic HNSW test configuration**
   - Introduce a public configuration record for `m`, construction/search breadth, and an injectable deterministic level source used only for tests.
   - Preserve a randomized production default.
   - Done when equivalent seeded/test configurations build identical topology and produce identical query results.

3. **Versioned correctness corpus and recall suite**
   - Add a small committed corpus that exercises clusters, ties, opposite vectors, and thresholds.
   - Compare HNSW against exact cosine results and report recall@1/recall@10.
   - Done when CI enforces an explicit documented recall floor on the corpus.

4. **Lifecycle/churn evidence**
   - Add deterministic mixed insert, replacement, delete, and search churn (at least 1,000 operations).
   - Assert removed entities never return; dimension rules persist; recall does not fall below the documented floor after churn.
   - Done when the soak test is stable and regression-safe.

5. **Benchmark evidence and docs**
   - Add a reproducible local benchmark harness with corpus generator, measured index build time, query latency distribution, recall, and index-size proxy.
   - Publish environment and numbers in a versioned report; do not make universal complexity claims.
   - Done when the report is reproducible and the vector contract/maturity table truthfully reflect the measured envelope.

## Stable exit gate

- Deterministic test mode and exact oracle exist.
- CI validates the versioned corpus and documented recall floor (target: recall@10 >= 0.95).
- 1,000-operation mutation/churn suite passes.
- A reproducible benchmark report exists.
- Public documentation makes HNSW’s approximate nature and its measured—not assumed—envelope explicit.
