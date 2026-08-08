# Local Sharding Guide

> **Status: Beta.** AaronDB supports parallel, local sharding inside one BEAM runtime. It is not a distributed database or HA system. The supported boundary is defined in [ADR 0002](adr/0002-embedded-local-mcp-boundary.md).

## What works

`aarondb/sharded` partitions facts across local shard actors and executes transactions and queries using parallel scatter/gather coordination.

```gleam
import aarondb/sharded

let assert Ok(cluster) = sharded.start_sharded("analytics", 4, None)
```

This is useful for local parallelism, not remote clustering.

## Guarantees and limits

- Queries currently fan out across all local shards; there is no bounded distributed planner or remote shard routing.
- `Sum`, `Count`, `Min`, and `Max` use exact secondary reduction over shard results.
- `Avg` is an **average of per-shard averages**, and `Median` is a **median of per-shard medians**. Neither is an exact global aggregate when shard cardinalities or distributions differ.
- `migrate_shard_data` deliberately returns an explicit not-implemented error. There is no copy/verify/cut-over/retract protocol, retry idempotency, interruption recovery, automatic rebalancing, or failover.
- Raft is not involved: its election-only state machine is an inactive stub with no runtime integration or replicated log.

## Choosing sharding

Use local sharding only when parallel local execution is valuable and the above constraints are acceptable. It is unsuitable for any workflow that requires an atomic cross-shard write, source-of-truth migration, automatic recovery after a partial move, remote membership, or high availability.

Before this feature can claim a broader distributed contract, it needs all of:

1. A transactional or idempotent copy → verify → cut-over → retract migration protocol with interruption recovery.
2. Exact aggregate reducers (sum/count state for averages; mergeable distribution or raw-value state for medians).
3. Explicit membership, health, and failover semantics.
4. Fault-injection tests for duplicate prevention, partial failure, and recovery.

Until those exist, do not expose `sharded` as a remote cluster or HA service. For exact global average/median, dynamic migration, remote membership, or HA, use a separately designed distributed system.
