# Vector Search Contract

AaronDB's vector search is an in-memory approximate nearest-neighbour capability built on the `aarondb/vec_index` HNSW index. It is **Stable for the documented local approximate contract**: deterministic regression configuration, exact-oracle comparison, lifecycle churn coverage, a reproducible benchmark harness, and CI evidence. It is not a universal latency, memory, or recall SLA.

## Similarity semantics

- AaronDB uses **cosine similarity**.
- HNSW normalizes every stored vector and every query vector; its dot-product score is therefore cosine similarity for valid non-zero vectors.
- Scores are in the inclusive range `[-1.0, 1.0]` for finite, non-zero inputs.
- The `threshold` is inclusive: a result is returned when `score >= threshold`.
- Results are sorted in descending score order. Equal-score ordering is ascending entity ID.

## Input validation

A vector index establishes its dimension from its first accepted vector.

- `try_insert` returns `Error(Nil)` for vectors whose dimensions differ from the index.
- `try_search` returns `Error(Nil)` for a query whose dimensions differ from the index.
- Empty and zero-magnitude vectors are invalid for similarity search and are rejected by the `try_*` API.
- `k` must be positive.
- `threshold` must be within `[-1.0, 1.0]`.
- The compatibility `insert` and `search` wrappers preserve their historical total return types: invalid inserts leave the index unchanged and invalid searches return `[]`.

## Approximation boundary

`VecIndex` is an HNSW approximate index. Its production graph construction uses runtime randomness, so topology and recall can differ between runs. For a deterministic finite-corpus reference, use `exact_search`: it returns the same `SearchResult` type and validation behavior, and orders ties by ascending entity ID after descending score.

The committed deterministic evidence corpus reports recall@5 = 1.00, and its 1,000-operation lifecycle soak reports recall@10 = 1.00. A reproducible 1,000-vector local benchmark also records a 14,533 ms build, 18 ms p50 / 20 ms p95 HNSW top-10 query sample, and recall@10 = 1.00 on its stated macOS/Gleam-Erlang environment; see `docs/reports/2026-08-08-vector-hnsw-evidence.md`. These are regression fixtures and a machine-local sample, **not** universal latency, memory, or recall SLAs.

## Lifecycle

- Insertion normalizes vectors before indexing.
- Deletion removes a node and repairs incident graph edges.
- Re-inserting an existing entity replaces its stored vector; callers should treat this as an index update and test their own application-level fact lifecycle separately.
- The index is in-memory. Persistence/rebuild behavior belongs to the enclosing database/storage adapter, not `VecIndex`.

## Scope limits

This contract does not claim:

- deterministic HNSW graph topology;
- benchmarked recall, latency, or memory envelopes;
- distributed vector search, migration, replication, or failover;
- hybrid BM25/vector ranking semantics.

Those are separate maturity milestones.
