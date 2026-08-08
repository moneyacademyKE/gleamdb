# Vector Search Contract

AaronDB's vector search is an in-memory approximate nearest-neighbour capability built on the `aarondb/vec_index` HNSW index. It is Beta. This document defines the behavior callers can rely on today and, equally importantly, the behavior that is not claimed.

## Similarity semantics

- AaronDB uses **cosine similarity**.
- HNSW normalizes every stored vector and every query vector; its dot-product score is therefore cosine similarity for valid non-zero vectors.
- Scores are in the inclusive range `[-1.0, 1.0]` for finite, non-zero inputs.
- The `threshold` is inclusive: a result is returned when `score >= threshold`.
- Results are sorted in descending score order. Equal-score ordering is not part of the current public contract.

## Input validation

A vector index establishes its dimension from its first accepted vector.

- `try_insert` returns `Error(Nil)` for vectors whose dimensions differ from the index.
- `try_search` returns `Error(Nil)` for a query whose dimensions differ from the index.
- Empty and zero-magnitude vectors are invalid for similarity search and are rejected by the `try_*` API.
- `k` must be positive.
- `threshold` must be within `[-1.0, 1.0]`.
- The compatibility `insert` and `search` wrappers preserve their historical total return types: invalid inserts leave the index unchanged and invalid searches return `[]`.

## Approximation boundary

`VecIndex` is an HNSW approximate index. It does **not** promise exhaustive nearest-neighbour results or a recall percentage yet. Its graph construction currently uses runtime randomness and is not deterministic across runs.

For exact, testable cosine comparisons, use `aarondb/math.cosine_similarity` over a caller-owned finite corpus. AaronDB does not yet expose an exact corpus-search API or latency/recall SLA.

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
