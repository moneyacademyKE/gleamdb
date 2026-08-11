# ADR 0010: Identity, Recovery, and Fault-Evidence Gates

## Status

Proposed

## Decision

Nodes have durable identities and trust configuration distinct from envelope authors and local capability tokens. The reference transport uses mTLS with certificate-to-member binding, trust-root rotation/revocation, membership authorization, bounded reconnect/retry/deadline policy, and payload limits.

Recovery tooling is inspect/export/acknowledged-force-recovery only. Force recovery persists an `UnsafeRecoveryAlarm` until explicit operator acknowledgement; it never silently resets a cluster, rewrites membership, or discards conflict evidence.

Promotion gates require deterministic fault tests: partitions, crashes/restarts, duplicate/reordered/lost RPC, slow followers, blocked storage, interrupted snapshots, membership churn, and bounded clock anomalies. Histories for command/CAS/leases are checked for linearizability and minimized with reproducible seeds.

## Consequences

Three happy nodes prove fuck all. Distributed labels remain experimental until seeded mutants for split brain, duplicate apply, stale fence, and unsafe recovery are detected by the harness.
