//// # storage/mnesia — recovery-oriented Mnesia StorageAdapter
////
//// Thin Gleam wrapper over the `aarondb_mnesia_ffi` Erlang FFI: creates a
//// disc-copy `datoms` schema and persists/recovers datoms transactionally.
//// Initialization never rewrites an existing incompatible schema: it reports a
//// descriptive `Error` and leaves persisted data untouched. Back up and
//// migrate explicitly—or intentionally reset the table—before retrying.
//// STATUS: Supported for one local BEAM node's recovery path only. `init_mnesia`
//// and reads/writes return explicit errors, including startup, schema-mismatch,
//// and aborted-transaction failures; they never reset an incompatible table.
//// Test isolation: run the suite with a disposable Mnesia directory, e.g.
//// `ERL_FLAGS="-mnesia dir <temporary-directory>" gleam test`. The adapter
//// owns no schema migration or cleanup operation: existing data is never reset.
//// Concurrent initialization re-checks the existing table schema. This adapter
//// does not provide multi-node durability, HA, schema migration,
//// concurrent-writer performance guarantee. See ADR 0002.

import aarondb/fact.{type Datom}
import aarondb/shared/ast.{type Clause}
import aarondb/storage.{type StorageAdapter, type StorageError, TransactionError}

@external(erlang, "aarondb_mnesia_ffi", "init")
pub fn init_mnesia() -> Result(Nil, String)

@external(erlang, "aarondb_mnesia_ffi", "persist")
pub fn persist_datom(datom: Datom) -> Result(Nil, String)

@external(erlang, "aarondb_mnesia_ffi", "persist_batch")
pub fn persist_batch(datoms: List(Datom)) -> Result(Nil, String)

pub fn adapter() -> StorageAdapter {
  storage.StorageAdapter(
    insert: fn(datoms) { persist_batch(datoms) |> map_write_err },
    append: fn(datoms) { persist_batch(datoms) |> map_write_err },
    read: fn(_attr) {
      // Simplified for read(attr) - ideally this uses a targeted select
      recover_datoms() |> map_err
    },
    read_all: fn() { recover_datoms() |> map_err },
    query_datoms: fn(pattern) { select_ffi(pattern) |> map_err },
  )
}

fn map_write_err(res: Result(Nil, String)) -> Result(Nil, StorageError) {
  case res {
    Ok(Nil) -> Ok(Nil)
    Error(error) -> Error(TransactionError(error))
  }
}

fn map_err(
  res: Result(List(Datom), String),
) -> Result(List(Datom), StorageError) {
  case res {
    Ok(datoms) -> Ok(datoms)
    Error(error) -> Error(TransactionError(error))
  }
}

@external(erlang, "aarondb_mnesia_ffi", "recover")
pub fn recover_datoms() -> Result(List(Datom), String)

@external(erlang, "aarondb_mnesia_ffi", "select")
fn select_ffi(pattern: Clause) -> Result(List(Datom), String)
