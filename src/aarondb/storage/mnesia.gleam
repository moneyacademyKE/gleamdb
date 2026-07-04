import aarondb/fact.{type Datom}
import aarondb/shared/ast.{type Clause}
import aarondb/storage.{
  type StorageAdapter, type StorageError, TransactionError,
}

@external(erlang, "aarondb_mnesia_ffi", "init")
pub fn init_mnesia() -> Nil

@external(erlang, "aarondb_mnesia_ffi", "persist")
pub fn persist_datom(datom: Datom) -> Nil

@external(erlang, "aarondb_mnesia_ffi", "persist_batch")
pub fn persist_batch(datoms: List(Datom)) -> Nil

pub fn adapter() -> StorageAdapter {
  storage.StorageAdapter(
    insert: fn(datoms) {
      persist_batch(datoms)
      Ok(Nil)
    },
    append: fn(datoms) {
      persist_batch(datoms)
      Ok(Nil)
    },
    read: fn(_attr) {
      // Simplified for read(attr) - ideally this uses a targeted select
      recover_datoms() |> map_err
    },
    read_all: fn() { recover_datoms() |> map_err },
    query_datoms: fn(pattern) { select_ffi(pattern) |> map_err },
  )
}

fn map_err(
  res: Result(List(Datom), String),
) -> Result(List(Datom), StorageError) {
  case res {
    Ok(d) -> Ok(d)
    Error(e) -> Error(TransactionError(e))
  }
}

@external(erlang, "aarondb_mnesia_ffi", "recover")
pub fn recover_datoms() -> Result(List(Datom), String)

@external(erlang, "aarondb_mnesia_ffi", "select")
fn select_ffi(pattern: Clause) -> Result(List(Datom), String)
