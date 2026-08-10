# ADR 0008: Linearizable Commands, CAS, and Read Modes

## Status

Proposed

## Decision

A distributed command is admitted by the leader, durably deduplicated by idempotency key, quorum-committed, and deterministically applied at one log index. Retrying an accepted key returns the original result; reusing a key with a different payload returns a typed mismatch error.

CAS is a committed command evaluated at its apply index, never client-side read-then-write. Read APIs name their safety: `Local`, `LeaseRead` (only when a proven leader lease is valid), and `Linearizable` (ReadIndex/quorum proof). A failed proof returns an error; it never degrades silently.

Fencing issuance is part of the deterministic command model. Token allocation is dormant until consensus runtime activation.

## Consequences

Callers select correctness/availability trade-offs visibly. The embedded API stays separate and cannot accidentally acquire distributed semantics.
