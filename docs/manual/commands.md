# Deterministic Commands and CAS

`aarondb/command` is the pure state-machine boundary consumed by a future consensus runtime. It is **not** a network client and does not make the local AaronDB constructor distributed.

## Contract

- `apply(index, request, state)` accepts only the next contiguous committed index.
- A repeated idempotency key paired with the same command returns the original stored result and does not apply the command again.
- Reusing an idempotency key with different command bytes returns `IdempotencyPayloadMismatch`.
- `CompareAndSet` evaluates against the value at its committed position. It is not a client-side read-then-write convenience.
- `Local`, `LeaseRead`, and `Linearizable` are declared data. This reference does not silently turn one mode into another; a consensus runtime must prove the requested mode before serving it.
- `IssueFence` produces monotonically increasing tokens per resource in deterministic state. Lease validity and downstream token enforcement arrive with the consensus lease layer.

`replay_hash` is a deterministic audit fingerprint over ordered state. It is intentionally not a cryptographic integrity boundary; signed envelopes cover that different concern.

## Recovery

The `State` value is the persistence boundary for this reference. A durable adapter persists it together with the committed index and dedupe table. After recovery, duplicates retain their first result and fence numbers continue monotonically.

## Non-goals

There is no leader routing, quorum acknowledgement, network transport, lease expiry, or linearizability claim in this module. Those require the Raft runtime and cluster API, not hand-wavy local wrappers.
