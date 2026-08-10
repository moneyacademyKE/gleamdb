# Durable Projections Manual

A projection owns an ID, input schema/version, generation, snapshot loader, idempotent `apply`, durable state/checkpoint transaction, and rebuild policy. Its state is derived; source log/facts remain authority.

## Lifecycle

`Running`, `Paused`, `Replaying`, `Failed`, `Rebuilding`, and `Stale` are observable states. Status includes offset, lag, restart count, reason, generation, schema, and transition time. Rebuild constructs a new generation from snapshot + tail, validates it, then swaps it; the old generation remains queryable until safe replacement.

A retryable failure obeys bounded supervision. Permanent, corrupt, source-loss, and rebuild-required failures remain visible rather than spinning an unbounded restart loop.
