import aarondb/fact
import aarondb/shared/ast

pub type StorageError {
  StorageError(message: String)
  TransactionError(reason: String)
  NotFoundError
}

pub type StorageAdapter {
  StorageAdapter(
    insert: fn(List(fact.Datom)) -> Result(Nil, StorageError),
    append: fn(List(fact.Datom)) -> Result(Nil, StorageError),
    read: fn(String) -> Result(List(fact.Datom), StorageError),
    read_all: fn() -> Result(List(fact.Datom), StorageError),
    query_datoms: fn(ast.Clause) -> Result(List(fact.Datom), StorageError),
  )
}

pub fn insert(
  adapter: StorageAdapter,
  datoms: List(fact.Datom),
) -> Result(Nil, StorageError) {
  adapter.insert(datoms)
}

pub fn append(
  adapter: StorageAdapter,
  datoms: List(fact.Datom),
) -> Result(Nil, StorageError) {
  adapter.append(datoms)
}

pub fn read_all(
  adapter: StorageAdapter,
) -> Result(List(fact.Datom), StorageError) {
  adapter.read_all()
}

pub fn query_datoms(
  adapter: StorageAdapter,
  pattern: ast.Clause,
) -> Result(List(fact.Datom), StorageError) {
  adapter.query_datoms(pattern)
}

pub fn error_message(error: StorageError) -> String {
  case error {
    StorageError(message) -> message
    TransactionError(reason) -> reason
    NotFoundError -> "storage record not found"
  }
}

pub fn ephemeral() -> StorageAdapter {
  StorageAdapter(
    insert: fn(_) { Ok(Nil) },
    append: fn(_) { Ok(Nil) },
    read: fn(_) { Ok([]) },
    read_all: fn() { Ok([]) },
    query_datoms: fn(_) { Ok([]) },
  )
}
