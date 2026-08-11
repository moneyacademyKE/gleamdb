# ADR 0009: Consensus Leases, Fencing, and Time

## Status

Proposed

## Decision

Lease grant, renewal, revocation, and expiry policy are committed state-machine commands. Each resource owns a monotonically increasing fencing token; every grant returns a higher token. Protected downstream resources must persist the greatest token seen and reject stale holders.

Expiry is derived from committed policy and bounded-time assumptions documented by the cluster configuration. A leader's wall clock alone cannot prove lease ownership. On leader, quorum, membership, or clock-bound uncertainty, the runtime refuses new grants and lease-backed operations rather than guessing.

## Consequences

Fencing is the safety mechanism; a lease without downstream token enforcement is advisory and must be documented as such. Restart and failover preserve the committed token sequence.
