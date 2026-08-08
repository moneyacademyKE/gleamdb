# Analytics

AaronDB supports aggregate clauses over its in-process query engine.

## Aggregate operations

- `Count`
- `Sum`
- `Min` / `Max`
- `Avg`
- `Median`

## Local sharded reduction

For the Beta local sharding extension, each shard evaluates its aggregate and the coordinator performs a second reduction.

- `Sum`, `Count`, `Min`, and `Max` are exact under the local shard model.
- `Avg` is an **average of local averages** and is therefore approximate when shard sizes differ.
- `Median` is a **median of local medians** and is therefore approximate unless shard distributions happen to align.

Exact global average requires per-shard sums and counts. Exact global median requires raw values or mergeable distribution state. AaronDB intentionally does not claim either protocol today.

See the [local sharding guide](../distributed_guide.md) and [ADR 0002](../adr/0002-embedded-local-mcp-boundary.md) for the deployment boundary and non-goals.
