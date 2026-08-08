//// Local, in-runtime federation over independently owned AaronDB databases.
//// Local, in-runtime federation over independently owned AaronDB databases.
////
//// This module deliberately composes local database actors only. It does not
//// provide remote transport, coordinated writes, failover, quorum, or HA.

import aarondb/engine
import aarondb/fact
import aarondb/shared/ast
import aarondb/transactor
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{None}
import gleam/order.{type Order}
import gleam/string

pub type Source {
  Source(name: String, db: transactor.Db)
}

pub type Federation {
  Federation(sources: List(Source))
}

pub type FederatedRow {
  FederatedRow(source: String, row: Dict(String, fact.Value))
}

pub type FederatedResult {
  FederatedResult(rows: List(FederatedRow), sources: List(String))
}

/// Construct a local federation.
///
/// Source names must be non-empty and unique. Every source must expose the
/// same set of declared schema attributes. This is a compatibility guard, not
/// schema negotiation: callers own schema rollout across their databases.
pub fn new(sources: List(Source)) -> Result(Federation, String) {
  case sources {
    [] -> Error("A federation requires at least one source")
    _ ->
      case validate_names(sources, []) {
        Error(error) -> Error(error)
        Ok(_) -> validate_schema_compatibility(sources)
      }
  }
}

/// Run a query against each source in stable source-name order.
///
/// Results retain their origin in `FederatedRow.source`. Sources are queried
/// independently: there is no cross-source transaction or snapshot guarantee.
pub fn query(federation: Federation, query: ast.Query) -> FederatedResult {
  let Federation(sources:) = federation
  let ordered_sources = list.sort(sources, compare_source)
  let rows =
    list.fold(ordered_sources, [], fn(acc, source) {
      let Source(name:, db:) = source
      let result = engine.run(transactor.get_state(db), query, [], None, None)
      let sourced_rows =
        list.map(result.rows, fn(row) { FederatedRow(source: name, row: row) })
      list.append(acc, sourced_rows)
    })

  FederatedResult(
    rows: rows,
    sources: list.map(ordered_sources, fn(source) {
      let Source(name:, ..) = source
      name
    }),
  )
}

fn validate_names(
  sources: List(Source),
  seen: List(String),
) -> Result(Nil, String) {
  case sources {
    [] -> Ok(Nil)
    [Source(name:, ..), ..] if name == "" ->
      Error("Federation source names cannot be empty")
    [Source(name:, ..), ..rest] ->
      case list.contains(seen, name) {
        True -> Error("Duplicate federation source: " <> name)
        False -> validate_names(rest, [name, ..seen])
      }
  }
}

fn validate_schema_compatibility(
  sources: List(Source),
) -> Result(Federation, String) {
  case sources {
    [] -> Error("A federation requires at least one source")
    [first, ..rest] -> {
      let Source(db: first_db, ..) = first
      let expected = schema_attributes(first_db)
      case
        list.all(rest, fn(source) {
          let Source(db:, ..) = source
          schema_attributes(db) == expected
        })
      {
        True -> Ok(Federation(sources))
        False ->
          Error("Federation sources must declare the same schema attributes")
      }
    }
  }
}

fn schema_attributes(db: transactor.Db) -> List(String) {
  transactor.get_state(db).schema
  |> dict.keys
  |> list.sort(string.compare)
}

fn compare_source(left: Source, right: Source) -> Order {
  let Source(name: left_name, ..) = left
  let Source(name: right_name, ..) = right
  string.compare(left_name, right_name)
}
