# Local federation contract

> **Status: Beta.** Local federation composes independently owned AaronDB
> databases inside one BEAM runtime. It is not sharding, remote federation,
> replication, or high availability.

## What it provides

`aarondb/federation` evaluates one query against a named list of local database
actors. Results retain their source so callers do not confuse equal entity IDs
or values from different databases.

```gleam
import aarondb/federation

let assert Ok(federation) = federation.new([
  federation.Source("analytics", analytics_db),
  federation.Source("catalog", catalog_db),
])

let results = federation.query(federation, query)
```

A `FederatedResult` contains:

- `sources`: source names sorted ascending;
- `rows`: `FederatedRow(source:, row:)`, grouped in that same stable source
  order; and
- source provenance for every row.

The stable order is by source name. Row order *inside* a source remains the
order returned by that source's query engine. No global ranking, join, or
collision merge is implied.

## Admission rules

`federation.new` rejects:

- an empty source set;
- empty or duplicate source names; and
- sources whose declared schema attribute-name sets differ.

Schema compatibility is an admission guard, not negotiation or migration.
Callers own schema deployment across the component databases.

## Consistency and failures

Every source is queried independently and sequentially in stable name order.
There is no cross-source transaction, snapshot, retry, timeout policy, or
partial-result mode. A caller must treat a federation query as local composition
of independent reads, not as an atomic distributed read.

AaronDB currently exposes no recoverable source-failure result for federation.
If a local source actor is unavailable, the underlying actor state read fails;
the caller must manage source lifecycle before constructing or querying the
federation. This is intentionally fail-fast rather than silently returning a
partial result.

## Explicit non-goals

This module does **not** provide:

- remote peers or network transport;
- source discovery, health checks, failover, quorum, or HA;
- coordinated writes, two-phase commit, or replication;
- entity-ID namespacing or automatic collision resolution;
- cross-source joins, globally exact aggregates, or global query optimization;
- membership change or data migration.

Use `aarondb/sharded` only for its separately documented local partitioning
contract. Do not describe either module as a distributed database service.
