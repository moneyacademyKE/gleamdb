//// # durable_log — independent deterministic durable-log reference
////
//// This pure local reference is deliberately separate from fact storage. It
//// models the port contract used by later durable adapters: ordered offsets,
//// retained tails, verified snapshots, idempotent append, and an atomic
//// projection-checkpoint boundary. It is not a filesystem implementation.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub type SourceId =
  String

pub type Offset =
  Int

pub type Entry {
  Entry(
    offset: Offset,
    payload: String,
    idempotency_key: String,
    checksum: String,
  )
}

pub type Snapshot {
  Snapshot(offset: Offset, state: String, checksum: String)
}

pub type ProjectionCheckpoint {
  ProjectionCheckpoint(projection: String, offset: Offset)
}

pub type CheckpointFault {
  NoFault
  FailBeforeCommit
}

pub type DurableLog {
  DurableLog(
    source: SourceId,
    next_offset: Offset,
    entries: List(Entry),
    snapshots: List(Snapshot),
    checkpoints: List(ProjectionCheckpoint),
  )
}

pub type DurableLogError {
  CursorExpired(requested: Offset, earliest_available: Offset)
  CorruptEntry(offset: Offset)
  SnapshotUnavailable(offset: Offset)
  CheckpointFaultInjected
}

pub fn new(source: SourceId) -> DurableLog {
  DurableLog(
    source: source,
    next_offset: 0,
    entries: [],
    snapshots: [],
    checkpoints: [],
  )
}

/// Append is idempotent for a source-local key. Retrying returns its first entry.
pub fn append(
  log: DurableLog,
  payload: String,
  idempotency_key: String,
) -> #(DurableLog, Entry) {
  case find_key(log.entries, idempotency_key) {
    Some(entry) -> #(log, entry)
    None -> {
      let entry =
        Entry(
          offset: log.next_offset,
          payload: payload,
          idempotency_key: idempotency_key,
          checksum: fingerprint(payload),
        )
      #(
        DurableLog(
          ..log,
          next_offset: log.next_offset + 1,
          entries: list.append(log.entries, [entry]),
        ),
        entry,
      )
    }
  }
}

/// Read the retained tail strictly after `cursor` after validating every entry.
pub fn scan_after(
  log: DurableLog,
  cursor: Offset,
) -> Result(List(Entry), DurableLogError) {
  let earliest = earliest_available(log)
  case cursor < earliest - 1 {
    True ->
      Error(CursorExpired(requested: cursor, earliest_available: earliest))
    False -> verify_and_filter(log.entries, cursor)
  }
}

/// Persist a verified snapshot at an already committed position.
pub fn snapshot(
  log: DurableLog,
  offset: Offset,
  state: String,
) -> Result(DurableLog, DurableLogError) {
  case offset < -1 || offset >= log.next_offset {
    True -> Error(SnapshotUnavailable(offset))
    False ->
      Ok(
        DurableLog(
          ..log,
          snapshots: list.append(log.snapshots, [
            Snapshot(offset, state, fingerprint(state)),
          ]),
        ),
      )
  }
}

/// Bootstrap state from the latest verified snapshot at or before `through`, then tail it.
pub fn snapshot_then_tail(
  log: DurableLog,
  through: Offset,
) -> Result(#(Snapshot, List(Entry)), DurableLogError) {
  case latest_snapshot(log.snapshots, through) {
    None -> Error(SnapshotUnavailable(through))
    Some(saved) ->
      case verify_snapshot(saved) {
        Error(error) -> Error(error)
        Ok(snapshot) ->
          case scan_after(log, snapshot.offset) {
            Error(error) -> Error(error)
            Ok(entries) -> Ok(#(snapshot, entries))
          }
      }
  }
}

/// Drop entries through an offset only when a verified recovery snapshot covers it.
pub fn retain_after(
  log: DurableLog,
  offset: Offset,
) -> Result(DurableLog, DurableLogError) {
  case latest_snapshot(log.snapshots, offset) {
    Some(saved) if saved.offset >= offset ->
      case verify_snapshot(saved) {
        Ok(_) ->
          Ok(
            DurableLog(
              ..log,
              entries: list.filter(log.entries, fn(entry) {
                entry.offset > offset
              }),
            ),
          )
        Error(error) -> Error(error)
      }
    _ -> Error(SnapshotUnavailable(offset))
  }
}

/// This boundary represents one storage transaction: projection state is owned by
/// the adapter, and its successful application advances this checkpoint together.
pub fn commit_checkpoint(
  log: DurableLog,
  checkpoint: ProjectionCheckpoint,
  fault: CheckpointFault,
) -> Result(DurableLog, DurableLogError) {
  case fault {
    FailBeforeCommit -> Error(CheckpointFaultInjected)
    NoFault ->
      Ok(
        DurableLog(
          ..log,
          checkpoints: replace_checkpoint(log.checkpoints, checkpoint),
        ),
      )
  }
}

pub fn checkpoint(
  log: DurableLog,
  projection: String,
) -> Option(ProjectionCheckpoint) {
  find_checkpoint(log.checkpoints, projection)
}

/// Test-only fault-model hook: a decoder must fail rather than skip altered bytes.
pub fn corrupt_entry(log: DurableLog, offset: Offset) -> DurableLog {
  DurableLog(
    ..log,
    entries: list.map(log.entries, fn(entry) {
      case entry.offset == offset {
        True -> Entry(..entry, payload: entry.payload <> "!corrupt")
        False -> entry
      }
    }),
  )
}

fn earliest_available(log: DurableLog) -> Offset {
  case log.entries {
    [Entry(offset, _, _, _), ..] -> offset
    [] -> log.next_offset
  }
}

fn verify_and_filter(
  entries: List(Entry),
  cursor: Offset,
) -> Result(List(Entry), DurableLogError) {
  list.fold(entries, Ok([]), fn(result, entry) {
    case result, verify_entry(entry) {
      Error(error), _ -> Error(error)
      _, Error(error) -> Error(error)
      Ok(acc), Ok(valid) ->
        case valid.offset > cursor {
          True -> Ok(list.append(acc, [valid]))
          False -> Ok(acc)
        }
    }
  })
}

fn verify_entry(entry: Entry) -> Result(Entry, DurableLogError) {
  case entry.checksum == fingerprint(entry.payload) {
    True -> Ok(entry)
    False -> Error(CorruptEntry(entry.offset))
  }
}

fn verify_snapshot(snapshot: Snapshot) -> Result(Snapshot, DurableLogError) {
  case snapshot.checksum == fingerprint(snapshot.state) {
    True -> Ok(snapshot)
    False -> Error(CorruptEntry(snapshot.offset))
  }
}

fn fingerprint(value: String) -> String {
  int.to_string(string.length(value)) <> ":" <> value
}

fn find_key(entries: List(Entry), key: String) -> Option(Entry) {
  case list.find(entries, fn(entry) { entry.idempotency_key == key }) {
    Ok(entry) -> Some(entry)
    Error(Nil) -> None
  }
}

fn latest_snapshot(
  snapshots: List(Snapshot),
  through: Offset,
) -> Option(Snapshot) {
  list.fold(snapshots, None, fn(latest: Option(Snapshot), candidate: Snapshot) {
    case candidate.offset <= through {
      False -> latest
      True ->
        case latest {
          None -> Some(candidate)
          Some(current) ->
            case candidate.offset > current.offset {
              True -> Some(candidate)
              False -> latest
            }
        }
    }
  })
}

fn replace_checkpoint(
  checkpoints: List(ProjectionCheckpoint),
  replacement: ProjectionCheckpoint,
) -> List(ProjectionCheckpoint) {
  let without =
    list.filter(checkpoints, fn(current) {
      current.projection != replacement.projection
    })
  list.append(without, [replacement])
}

fn find_checkpoint(
  checkpoints: List(ProjectionCheckpoint),
  projection: String,
) -> Option(ProjectionCheckpoint) {
  case
    list.find(checkpoints, fn(current) { current.projection == projection })
  {
    Ok(checkpoint) -> Some(checkpoint)
    Error(Nil) -> None
  }
}
