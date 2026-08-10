//// # raft_durability — filesystem-backed persistence boundary for cluster Raft
////
//// The adapter commits a complete Raft recovery image through an Erlang-owned
//// write/rename/fsync sequence. A recovery image is accepted only when its
//// SHA-256 checksum and term encoding verify. Corruption is an alarm, never a
//// repair path. The state image is opaque to this adapter so callers can keep
//// command, membership, lease, idempotency, and projection-checkpoint state in
//// one atomically recovered envelope.

import aarondb/raft_runtime.{type Persisted}

pub type Store {
  Store(path: String)
}

pub type Error {
  Io(String)
  Corrupt(String)
}

pub fn open(path: String) -> Store {
  Store(path)
}

@external(erlang, "aarondb_raft_durability_ffi", "save")
fn save_ffi(
  path: String,
  persisted: Persisted,
  state_image: String,
) -> Result(Nil, String)

/// Atomically writes `hard state + log + snapshot + state image` and fsyncs both
/// the file and directory before acknowledging success.
pub fn save(
  store: Store,
  persisted: Persisted,
  state_image: String,
) -> Result(Nil, Error) {
  let Store(path) = store
  case save_ffi(path, persisted, state_image) {
    Ok(Nil) -> Ok(Nil)
    Error(reason) -> Error(Io(reason))
  }
}

@external(erlang, "aarondb_raft_durability_ffi", "load")
fn load_ffi(path: String) -> Result(#(Persisted, String), #(String, String))

/// Reads exactly one verified image. Missing storage is a normal empty-node
/// bootstrap condition; malformed/torn/corrupt storage is a terminal alarm.
pub fn load(store: Store) -> Result(#(Persisted, String), Error) {
  let Store(path) = store
  case load_ffi(path) {
    Ok(image) -> Ok(image)
    Error(#("corrupt", reason)) -> Error(Corrupt(reason))
    Error(#(_, reason)) -> Error(Io(reason))
  }
}

@external(erlang, "aarondb_raft_durability_ffi", "backup")
fn backup_ffi(path: String, destination: String) -> Result(Nil, String)

/// Exports the already verified durable image. It never serializes a partial
/// in-memory state or overwrites the source store.
pub fn backup(store: Store, destination: String) -> Result(Nil, Error) {
  let Store(path) = store
  case backup_ffi(path, destination) {
    Ok(Nil) -> Ok(Nil)
    Error(reason) -> Error(Io(reason))
  }
}

@external(erlang, "aarondb_raft_durability_ffi", "remove")
pub fn remove_for_test(path: String) -> Result(Nil, String)

@external(erlang, "aarondb_raft_durability_ffi", "overwrite_for_test")
pub fn overwrite_for_test(path: String, bytes: String) -> Result(Nil, String)
