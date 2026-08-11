# ADR 0003: Durable Distributed Library Evolution

## Status

Proposed

## Context

AaronDB 4.1 is an embedded temporal Datalog library. Its transaction actor serializes local writes; `StorageAdapter` is fact storage; reactive subscriptions are local BEAM mailbox delivery; Mnesia is recovery-oriented; and `raft` is an inactive election-only stub. None is a durable changefeed or a consensus system.

## Decision

Introduce an **experimental, library-only durable/distributed layer**. It is built around a durable ordered log. Fact state, query indexes, and external materializations are projections and may be rebuilt from a retained snapshot plus log tail.

The layer is introduced in independently useful slices. No existing local API is relabelled durable, linearizable, or highly available. `aarondb.new()` retains its embedded meaning; distributed mode has a distinct constructor.

## Invariants

- `Offset` is opaque and strictly ordered within a stable `SourceId`.
- A projection checkpoint stores source, offset, schema version, and generation atomically with projection state, or the backing adapter is rejected.
- Delivery is ordered **at least once** per source. A duplicate is valid; an unacknowledged gap is not.
- Commands are deterministically applied at a committed log index; idempotency is durable.
- Only a quorum-committed Raft log authorizes linearizable commands or lease/fence transitions.
- Indexes and projections are derived and never authoritative over facts/log state.
- Operational status reports reality, including quorum loss and unsafe-recovery alarms.

## Vocabulary

| Term | Meaning |
|---|---|
| Offset / cursor | Ordered log position / versioned resumable position for one source |
| Snapshot position | Offset included in a durable snapshot |
| Projection generation | Independently buildable projection instance used for safe swap |
| Applied index / term | Deterministic state-machine position / Raft epoch |
| Membership / lease epoch | Version of committed members / lease policy state |
| Fencing token | Strictly increasing resource token that downstream systems reject when stale |
| Unsafe-recovery alarm | Persistent acknowledgement-required record of an operator-forced recovery |

## Explicit non-goals

- Exactly-once external effects.
- Arbitrary projection stores that cannot atomically persist state and checkpoint.
- Automatic conflict-discarding recovery, unauthenticated discovery, or silent membership rewrites.
- A network server, deployment product, or local API compatibility fiction.

## Consequences

This work adds ports and typed contracts before implementation. Experimental APIs must document their storage/fsync model, retention, read consistency, and recovery limits. Promotion requires adversarial evidence, not three friendly nodes.

## References

- [ADR 0002](0002-embedded-local-mcp-boundary.md)
- [Durable log manual](../manual/durable_log.md)
- [Projection manual](../manual/durable_projections.md)
- [Consensus manual](../manual/consensus.md)
