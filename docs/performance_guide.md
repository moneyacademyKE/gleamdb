# Performance guide

> **Scope:** local, embedded AaronDB in one BEAM runtime. This document describes implementation characteristics and measurement guidance; it does **not** promise a universal latency, throughput, memory, or asymptotic-performance SLA. Reproducible evidence for supported local contracts lives in [Stable-local evidence](evidence.md).

## Local execution model

- ETS indexes support concurrent local reads; database writes remain serialized through the transactor actor.
- Direct attribute lookups and indexed operations have different costs based on data shape, query plan, and index state. Measure representative workloads rather than relying on Big-O marketing claims.
- HNSW vector search is approximate. Its committed local recall/churn evidence and benchmark method are documented in [Vector search](manual/vector_search.md).
- Local sharding is Beta scatter/gather inside one BEAM runtime. It is not remote clustering, replication, or high availability; see the [Local Sharding Guide](distributed_guide.md).
- Mnesia is a recovery-oriented, single-node adapter. It has no supported HA, multi-node, power-loss, or concurrent-writer performance contract.
- Virtual predicates run synchronously in the query actor. An adapter that performs remote I/O makes that query branch wait; remote adapters are outside the supported local contract.

## Measurement discipline

Run the committed evidence harnesses before making local performance decisions:

- `gleam run -m vector_benchmark`
- `gleam run -m bm25_benchmark`
- `gleam run -m graph_benchmark`
- `gleam run -m federation_benchmark`
- `gleam run -m temporal_diff_benchmark`

Record the machine, runtime, corpus or fixture shape, and configuration alongside each result. Do not extrapolate a local fixture result to a production or distributed-service promise.

## Configuration

Named databases enable ETS-backed indexes automatically:

```gleam
let db = aarondb.start_named("fast_db", storage.ephemeral())
```

When `ets_name` is present in `DbState`, the engine can use ETS-backed index lookups. Query result size, history depth, graph budgets, and vector configuration remain caller-controlled inputs; use each feature’s documented bounded API when available.

## Feature-specific contracts

- [Vector search](manual/vector_search.md) — local approximate cosine search, validation, lifecycle, and evidence.
- [BM25 search](manual/bm25_search.md) — local caller-owned analyzer and ranking primitive.
- [Graph queries](manual/graph_queries.md) — directed local analytics; bounded APIs are preferred for new callers.
- [Temporal querying and diff](manual/temporal_diff.md) — local bounded history scans and diffs.
- [Local federation](manual/local_federation.md) — named local actor reads, deterministic ordering, and fail-fast errors.
- [Reactive subscriptions](manual/reactive_subscriptions.md) — local mailbox delivery; consumers own backpressure.
- [Mnesia recovery](manual/mnesia_recovery.md) — single-node recovery-only storage boundary.

## Retention

Use retention policies to bound data retained for attributes with ephemeral workloads. Retention is a data-model decision: it can discard historical visibility for that attribute, so it must be chosen deliberately rather than treated as a performance toggle.
