# ADR 0005: Ordered At-Least-Once Changefeeds and Durable Projections

## Status

Proposed

## Decision

A `ChangeSource` has a stable source ID, ordered offsets, a versioned serialized cursor, snapshot/range discovery, and a declared entry schema. The built-in transaction source emits only committed transactions.

Delivery is per-source ordered **at least once**: entries may repeat after restart or acknowledgement loss; delivery never silently omits a committed offset in the selected range. Each entry carries a source-scoped idempotency key. Consumers acknowledge only after their idempotent application and checkpoint are atomically durable.

Bootstrap is snapshot-then-tail at a captured position `S`: load a snapshot known to include `S`, then consume entries after `S`. Cursor expiration explicitly requires rebootstrap. Sources use bounded pull/credit flow control with outstanding-entry/byte limits, cancellation, deadlines, and typed lag—not unbounded actor mailboxes.

A projection is app-owned and specifies ID, input schema, snapshot load, idempotent apply, durable state/checkpoint, and rebuild/migration behavior. It reports `Running`, `Paused`, `Replaying`, `Failed`, `Rebuilding`, or `Stale`, plus cursor, lag, generation, schema, restart count, and failure reason. A rebuild creates a new generation, catches it up, verifies it, then swaps it safely.

## Non-goal

The contract does not claim exactly-once across calls to external systems. Consumers must use the provided idempotency key with their external sink's own deduplication/fencing capability.
