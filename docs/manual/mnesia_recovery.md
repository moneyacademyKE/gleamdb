# Mnesia Single-Node Recovery

AaronDB's Mnesia adapter is a **single local BEAM-node recovery adapter**. It
persists datoms in the local `datoms` table and restores them when a database is
started with the adapter again.

## Supported behavior

- Initialization creates the local Mnesia schema/table when absent.
- A compatible existing table is reused; concurrent initializers re-check the
  table instead of assuming that they created it.
- An incompatible `datoms` schema returns a descriptive error and is never
  deleted, recreated, or migrated automatically.
- Persist, batch persist, recovery, and select failures cross the FFI boundary
  as `Result` errors. A failed durable write does not publish the proposed
  in-memory transaction state or reactive delta.
- Restart/recovery and failing-storage behavior are covered by
  `test/aarondb/history_test.gleam`.

## Test isolation

Mnesia persists to a node-local directory. Run the suite with a fresh temporary
Mnesia directory to prove that recovery does not rely on state from another
run:

```sh
mnesia_dir=$(mktemp -d)
ERL_FLAGS="-mnesia dir '\"$mnesia_dir\"'" gleam test
rm -rf "$mnesia_dir"
```

This is the same contract CI uses for the isolated Mnesia evidence run.

## Explicit non-goals

This adapter does **not** promise multi-node replication, high availability,
schema migration, automatic repair/reset, power-loss/crash-consistency proof,
or concurrent-writer performance characteristics. Those require a separate
storage and operational design.
