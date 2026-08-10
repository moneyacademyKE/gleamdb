# ADR 0004: Durable Log, Retention, and Projection Checkpoints

## Status

Proposed

## Decision

A new durable-log port is the authority for ordered durable events. It is distinct from `StorageAdapter` fact persistence and from reactive mailboxes.

A log adapter provides source identity, append with explicit preconditions, scan by opaque cursor, end position, snapshot metadata/load, retention reporting, corruption detection, and atomic `projection_state + checkpoint` commit. An adapter lacking the latter must reject durable projection registration.

Offsets are opaque, monotonically ordered only within a stable source. Cursors encode source ID, offset, format version, and retention epoch. A cursor outside retention returns `CursorExpired(snapshot_position)`; it never silently starts at the newest entry.

Snapshots identify the exact included offset and schema/version. Recovery validates entry hash/checksum and either returns a typed corruption error or restores a verified snapshot plus tail; it must not skip corrupt data.

## Retention

Retention is explicit policy. Truncation happens only below a published safe point and preserves a snapshot needed to bootstrap new or expired consumers. Consumers must handle expiry with snapshot-then-tail bootstrap.

## Consequences

Append durability, fsync policy, and crash model are backend-declared rather than inferred. The initial local reference backend is deterministic and testable, but cannot be called consensus-safe until a later Raft storage contract is proven.
