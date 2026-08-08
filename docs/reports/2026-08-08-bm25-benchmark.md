# BM25 Local Benchmark Evidence — 2026-08-08

The local BM25 primitive has a reproducible sequential-operation harness:

```text
gleam run -m bm25_benchmark
```

The harness builds 1,000 deterministic text documents, executes 100 top-10
queries, and replaces every document once. It reports build time, full
replacement time, and search p50/p95 timings. Results are machine-local
measurements, not a portable throughput or latency SLA.

## Recorded local run

Run on 2026-08-08 using the Erlang target on the local macOS development
machine:

| Measure | Result |
| --- | ---: |
| Documents | 1,000 |
| Queries | 100 |
| Build | 32 ms |
| Replace all documents | 209 ms |
| Search p50 | 5 ms |
| Search p95 | 5 ms |

## Supported boundary

`aarondb/index/bm25` is an immutable, in-memory, caller-owned index. The
benchmark represents one BEAM process performing sequential operations. The
module does **not** currently promise:

- persistence or recovery of BM25 state;
- database transaction integration or automatic index maintenance;
- concurrent mutation safety or synchronization across processes;
- configurable analyzers, stemming, stop-word removal, or Unicode tokenization;
- distributed indexing or hybrid BM25/vector scoring.

The deterministic golden corpus and incremental-versus-rebuild tests establish
correctness within that boundary; this harness provides reproducible local
operation evidence.
