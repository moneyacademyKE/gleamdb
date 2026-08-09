# Vector search

> **Status: Beta.** AaronDB provides an in-process approximate HNSW index for
> cosine-similarity retrieval. Its supported contract is defined in
> [the vector search manual](../manual/vector_search.md).

## What it provides

- A fixed vector dimension established by the first accepted vector.
- Validation for empty, zero-magnitude, dimension-mismatched, invalid-threshold,
  and non-positive-result-limit inputs.
- Approximate HNSW search through `VecIndex`.
- `exact_search` for deterministic finite-corpus reference comparisons.
- Deterministic result ordering: descending score, then ascending entity ID.

## What it does not provide

- A universal logarithmic-complexity, latency, memory, or recall guarantee.
- A production topology that is deterministic across runs; production HNSW
  construction uses runtime randomness.
- A claim that vectors are normalized automatically by every API boundary.
- A distributed vector index or a hybrid BM25/vector retrieval service.

Use the manual for the exact validation, threshold, lifecycle, and evidence
contract. Stable promotion requires measured, reproducible local benchmark
coverage in addition to correctness regression tests.
