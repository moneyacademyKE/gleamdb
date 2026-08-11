# Consensus Manual

Distributed AaronDB is experimental and library-only. The durable Raft runtime commits commands only when a current-term quorum has replicated them, then deterministically applies them in index order. `Linearizable` reads use ReadIndex; `LeaseRead` requires an explicit valid proof; `Local` is intentionally weaker.

## Leader failover

A leader that cannot prove quorum stops committing. A new leader reconciles conflicting uncommitted suffixes with AppendEntries before committing new commands. Committed entries are never rolled back. Clients retry with the same idempotency key and receive the original committed result.

Membership changes use joint consensus. Snapshots retain enough metadata to validate state and membership before tail replay. Unsafe operator intervention records a persistent alarm and needs acknowledgement.
