# Durable Log Manual

## Contract

A durable log is an independent port, not fact `StorageAdapter` or `reactive` subscriptions. A `SourceId` defines one total offset order. Entries have a payload, checksum/hash, idempotency key, and committed position. Cursors are versioned and source-scoped.

An adapter supports append preconditions, scans, end position, verified snapshots, retention, and typed corruption/cursor-expiry errors. Projection registration requires an atomic state-and-checkpoint transaction.

## Bootstrap and retention

Capture snapshot position `S`, load a verified snapshot through `S`, then consume entries after `S`. On cursor expiry, start this bootstrap again; never jump to end.

## Failure examples

- **Duplicate delivery:** after a consumer writes state but loses its acknowledgement, it receives the entry again. Idempotent application plus atomic checkpoint gives the same final state.
- **Apply/checkpoint crash:** a crash before atomic commit leaves neither state nor checkpoint durable; replay is required. A crash after it leaves both durable; replay starts after the entry. Splitting these writes is rejected.
- **Corruption:** checksum failure returns `CorruptEntry`; recovery uses a verified snapshot plus retained tail or stops. It cannot silently skip bytes.
