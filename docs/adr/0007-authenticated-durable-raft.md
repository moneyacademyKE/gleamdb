# ADR 0007: Authenticated Durable Raft Runtime

## Status

Proposed

## Decision

The election-only `raft` stub is not activated. It is replaced by an optional runtime owning persistent hard state and log, RequestVote, AppendEntries with conflict repair, current-term quorum commit, ordered deterministic application, catch-up, snapshot install, ReadIndex, joint-consensus membership change, and safe bootstrap.

Every RPC crosses an authenticated transport port. Membership authorization occurs before protocol processing. Transport policy bounds payload size, queues, retries, and deadlines. A single-node configuration uses the same command/apply path, not a special local shortcut.

Hard state contains current term, vote, commit index, and membership epoch. Log/snapshot storage has stated persistence semantics. A node may not advertise quorum, leader, or linearizable reads after storage or membership uncertainty.

## Consequences

No HA, replication, or linearizability claim exists until the runtime passes deterministic partition/crash/reorder/snapshot/membership tests. Election APIs are quarantined or removed from the public supported surface to prevent semantic fraud.
