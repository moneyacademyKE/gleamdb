# Local federation benchmark

## Scope

This is reproducible **local-process** evidence for the fail-fast federation
API. It is not a remote-network, availability, failover, or high-availability
benchmark.

## Command

```sh
gleam run -m federation_benchmark
```

The harness creates two ephemeral AaronDB actors, inserts 500 deterministic
`person/name` facts into each, builds a federation with names supplied in
reverse order, then executes 100 `federation.query` calls. It reports the rows
from the final call and total wall-clock time.

## Local sample

Environment: macOS, Erlang target, AaronDB development build.

```text
sources=2 rows=998 reads=100 total_ms=219
```

This is a regression fixture and a reproducible method, not a latency SLA.
Timing depends on hardware, BEAM version, scheduler state, and local database
size. The durable contract is deterministic source-name ordering, per-row
provenance, and fail-fast `SourceUnavailable`/`SourceTimeout` errors with no
partial `FederatedResult`.
