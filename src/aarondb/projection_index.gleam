//// # projection_index — non-authoritative index lifecycle
////
//// Index state is a replayable projection of an ordered source. Queries are only
//// available while the index is healthy; the source remains authoritative.

import gleam/list
import gleam/option.{type Option, None, Some}

pub type Health {
  Building
  Rebuilding
  Queryable
  Degraded(reason: String)
  Failed(reason: String)
}

pub type Index {
  Index(
    schema_version: Int,
    generation: Int,
    health: Health,
    last_applied_offset: Int,
    values: List(String),
  )
}

pub type Error {
  InvalidSchemaVersion
  OffsetGap(expected: Int, received: Int)
  NotQueryable(Health)
}

pub fn new(schema_version: Int) -> Result(Index, Error) {
  case schema_version > 0 {
    True -> Ok(Index(schema_version, 0, Building, -1, []))
    False -> Error(InvalidSchemaVersion)
  }
}

pub fn apply(index: Index, offset: Int, value: String) -> Result(Index, Error) {
  case offset <= index.last_applied_offset {
    True -> Ok(index)
    False ->
      case offset == index.last_applied_offset + 1 {
        True ->
          Ok(
            Index(
              ..index,
              health: next_health(index.health),
              last_applied_offset: offset,
              values: list.append(index.values, [value]),
            ),
          )
        False -> Error(OffsetGap(index.last_applied_offset + 1, offset))
      }
  }
}

fn next_health(health: Health) -> Health {
  case health {
    Rebuilding -> Rebuilding
    _ -> Queryable
  }
}

pub fn query(index: Index) -> Result(List(String), Error) {
  case index.health {
    Queryable -> Ok(index.values)
    other -> Error(NotQueryable(other))
  }
}

/// Marks the current projection unavailable while a separate generation is built.
pub fn begin_rebuild(
  index: Index,
  schema_version: Int,
) -> Result(Index, Error) {
  case schema_version > 0 {
    True -> Ok(Index(schema_version, index.generation + 1, Rebuilding, -1, []))
    False -> Error(InvalidSchemaVersion)
  }
}

/// The caller swaps only a fully caught-up replacement. This makes a partial
/// rebuild unqueryable instead of returning silently incomplete answers.
pub fn swap(
  _current: Index,
  replacement: Index,
  source_high_watermark: Int,
) -> Result(Index, Error) {
  case replacement.last_applied_offset == source_high_watermark {
    True -> Ok(Index(..replacement, health: Queryable))
    False ->
      Error(OffsetGap(source_high_watermark, replacement.last_applied_offset))
  }
}

pub fn degrade(index: Index, reason: String) -> Index {
  Index(..index, health: Degraded(reason))
}

pub fn fail(index: Index, reason: String) -> Index {
  Index(..index, health: Failed(reason))
}

pub fn failure_reason(index: Index) -> Option(String) {
  case index.health {
    Degraded(reason) -> Some(reason)
    Failed(reason) -> Some(reason)
    _ -> None
  }
}
