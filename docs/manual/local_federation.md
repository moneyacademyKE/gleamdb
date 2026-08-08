# Local federation contract

> **Status: Beta.** Local federation composes independently owned AaronDB
> databases inside one BEAM runtime. It is not sharding, remote federation,
> replication, or high availability.

## What it provides

`aarondb/federation` evaluates one query against a named list of live local
actors. Results retain their source so callers do not confuse equal entity IDs
or values from different databases.

```gleam
import aarondb/federation

let assert Ok(federation) = federation.new([
  federation.Source("analytics", analytics_db),
  federation.Source("catalog", catalog_db),
])

let assert Ok(results) = federation.query(federation, query)
```

A `FederatedResult` contains:

- `sources`: source names sorted ascending;
- `rows`: `FederatedRow(source:, row:)`, grouped in that same stable source
  order; and
- source provenance for every row.

The stable order is by source name. Row order *inside* a source remains the
order returned by that source's query engine. No global ranking, join, or
collision merge is implied. Provenance namespaces otherwise colliding entity
IDs: the raw ID alone is not a federation-wide identity.

## Admission rules

`federation.new` rejects:

- an empty source set;
- empty or duplicate source names; and
- sources whose declared schema attribute-name sets differ.

Schema compatibility is an admission guard, not negotiation or migration.
Callers own schema deployment across the component databases.

## Execution and failures

Every source is queried independently and sequentially in stable name order.
There is no cross-source transaction or snapshot guarantee.

`query` is fail-fast and uses a five-second deadline per source.
`query_with_timeout` lets callers select another positive deadline. Both return
`Result(FederatedResult, FederationError)`:

- `SourceUnavailable(name)` means the actor was already dead before execution;
- `SourceTimeout(name)` means a live source did not provide state by its
  deadline.

On either error the API returns **no `FederatedResult`**. It never leaks the
rows gathered from earlier sources as a partial success. There is deliberately
no partial-results mode, retry policy, or silent source omission.

## Explicit non-goals

This module does **not** provide:

- remote peers or network transport;
- source discovery, health checks, failover, quorum, or HA;
- coordinated writes, two-phase commit, or replication;
- entity-ID rewriting or automatic collision resolution;
- cross-source joins, globally exact aggregates, or global query optimization;
- membership change or data migration.

Use `aarondb/sharded` only for its separately documented local partitioning
contract. Do not describe either module as a distributed database service.
