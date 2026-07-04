import aarondb/fact
import aarondb/index
import aarondb/index/ets as ets_index
import aarondb/shared/ast
import aarondb/shared/query_types
import aarondb/shared/state
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result

pub fn entity_history(
  db_state: state.DbState,
  eid: fact.EntityId,
) -> List(fact.Datom) {
  dict.get(db_state.eavt, eid)
  |> result.unwrap([])
  |> list.sort(fn(a, b) {
    case int.compare(a.tx, b.tx) {
      order.Eq -> {
        case a.operation, b.operation {
          fact.Retract, fact.Assert -> order.Lt
          fact.Assert, fact.Retract -> order.Gt
          _, _ -> order.Eq
        }
      }
      other -> other
    }
  })
}

pub fn filter_active(
  datoms: List(fact.Datom),
  db_state: state.DbState,
) -> List(fact.Datom) {
  let latest =
    list.fold(datoms, dict.new(), fn(acc, d) {
      let config = attribute_config(db_state, d.attribute)
      let key = case config.cardinality {
        fact.Many -> #(d.entity, d.attribute, Some(d.value))
        fact.One -> #(d.entity, d.attribute, None)
      }

      case dict.get(acc, key) {
        Ok(#(tx, tx_idx, _op)) -> {
          case tx > d.tx || { tx == d.tx && tx_idx > d.tx_index } {
            True -> acc
            False -> dict.insert(acc, key, #(d.tx, d.tx_index, d.operation))
          }
        }
        _ -> dict.insert(acc, key, #(d.tx, d.tx_index, d.operation))
      }
    })

  list.filter(datoms, fn(d: fact.Datom) {
    let config = attribute_config(db_state, d.attribute)
    let key = case config.cardinality {
      fact.Many -> #(d.entity, d.attribute, Some(d.value))
      fact.One -> #(d.entity, d.attribute, None)
    }

    case dict.get(latest, key) {
      Ok(#(tx, tx_idx, op)) ->
        tx == d.tx && tx_idx == d.tx_index && op == fact.Assert
      _ -> False
    }
  })
}

pub fn pull(
  db_state: state.DbState,
  eid: fact.EntityId,
  pattern: ast.PullPattern,
) -> query_types.PullResult {
  let datoms = case db_state.ets_name {
    Some(name) -> ets_index.lookup_datoms(name <> "_eavt", eid)
    None -> index.filter_by_entity(db_state.eavt, eid) |> list.reverse()
  }

  case list.length(datoms) > db_state.config.zero_copy_threshold {
    True -> {
      case db_state.ets_name {
        Some(name) -> {
          let assert Ok(bin) = ets_index.get_raw_binary(name <> "_eavt", eid)
          query_types.PullRawBinary(bin)
        }
        None -> query_types.PullRawBinary(ets_index.serialize_term(datoms))
      }
    }
    False -> {
      let active = filter_active(datoms, db_state)
      let mapped =
        list.fold(pattern, dict.new(), fn(acc, item) {
          case item {
            ast.Wildcard -> {
              list.fold(active, acc, fn(inner_acc, d: fact.Datom) {
                dict.insert(inner_acc, d.attribute, query_types.PullSingle(d.value))
              })
            }
            ast.Attr(name) -> {
              let values =
                list.filter(active, fn(d: fact.Datom) { d.attribute == name })
                |> list.map(fn(d) { d.value })
              case values {
                [v] -> dict.insert(acc, name, query_types.PullSingle(v))
                [_, ..] -> dict.insert(acc, name, query_types.PullMany(values))
                [] -> acc
              }
            }
            ast.Except(exclusions) -> {
              list.fold(active, acc, fn(inner_acc, d: fact.Datom) {
                case list.contains(exclusions, d.attribute) {
                  True -> inner_acc
                  False ->
                    dict.insert(inner_acc, d.attribute, query_types.PullSingle(d.value))
                }
              })
            }
            ast.PullRecursion(attr, depth) -> pull_recursion(db_state, active, acc, attr, depth)
            ast.Nested(name, sub_pattern) -> pull_nested(db_state, active, acc, name, sub_pattern)
          }
        })
      query_types.PullMap(mapped)
    }
  }
}

pub fn pull_result_to_value(res: query_types.PullResult) -> fact.Value {
  case res {
    query_types.PullSingle(v) -> v
    query_types.PullMany(vs) -> fact.List(vs)
    query_types.PullNestedMany(res_list) ->
      fact.List(list.map(res_list, pull_result_to_value))
    query_types.PullMap(m) ->
      fact.Map(dict.map_values(m, fn(_, v) { pull_result_to_value(v) }))
    query_types.PullRawBinary(bin) -> fact.Blob(bin)
  }
}

pub fn diff(
  db_state: state.DbState,
  from_tx: Int,
  to_tx: Int,
) -> List(fact.Datom) {
  index.get_all_datoms(db_state.eavt)
  |> list.filter(fn(d) { d.tx > from_tx && d.tx <= to_tx })
}

pub fn filter_by_time(
  datoms: List(fact.Datom),
  tx_limit: Option(Int),
  valid_limit: Option(Int),
) -> List(fact.Datom) {
  datoms
  |> list.filter(fn(d) {
    let tx_ok = case tx_limit {
      Some(tx) -> d.tx <= tx
      None -> True
    }
    let valid_ok = case valid_limit {
      Some(vt) -> d.valid_time <= vt
      None -> True
    }
    tx_ok && valid_ok
  })
}

fn attribute_config(
  db_state: state.DbState,
  attribute: String,
) -> fact.AttributeConfig {
  dict.get(db_state.schema, attribute)
  |> result.unwrap(fact.AttributeConfig(
    unique: False,
    component: False,
    retention: fact.All,
    cardinality: fact.Many,
    check: None,
    composite_group: None,
    layout: fact.Row,
    tier: fact.Memory,
    eviction: fact.AlwaysInMemory,
  ))
}

fn pull_recursion(
  db_state: state.DbState,
  datoms: List(fact.Datom),
  acc: dict.Dict(String, query_types.PullResult),
  attr: String,
  depth: Int,
) -> dict.Dict(String, query_types.PullResult) {
  case depth <= 0 {
    True -> acc
    False -> {
      let values =
        list.filter(datoms, fn(d: fact.Datom) { d.attribute == attr })
        |> list.map(fn(d) { d.value })
      let results =
        list.map(values, fn(v) {
          case v {
            fact.Ref(next_id) ->
              pull(db_state, next_id, [ast.Wildcard, ast.PullRecursion(attr, depth - 1)])
            fact.Int(next_id_int) ->
              pull(db_state, fact.EntityId(next_id_int), [
                ast.Wildcard,
                ast.PullRecursion(attr, depth - 1),
              ])
            _ -> query_types.PullSingle(v)
          }
        })
      case results {
        [r] -> dict.insert(acc, attr, r)
        [_, ..] -> dict.insert(acc, attr, query_types.PullNestedMany(results))
        [] -> acc
      }
    }
  }
}

fn pull_nested(
  db_state: state.DbState,
  datoms: List(fact.Datom),
  acc: dict.Dict(String, query_types.PullResult),
  name: String,
  sub_pattern: ast.PullPattern,
) -> dict.Dict(String, query_types.PullResult) {
  let values =
    list.filter(datoms, fn(d: fact.Datom) { d.attribute == name })
    |> list.map(fn(d) { d.value })
  case values {
    [fact.Ref(eid)] -> dict.insert(acc, name, pull(db_state, eid, sub_pattern))
    [fact.Int(sub_id)] ->
      dict.insert(acc, name, pull(db_state, fact.EntityId(sub_id), sub_pattern))
    [_, ..] -> {
      let nested =
        list.map(values, fn(v) {
          case v {
            fact.Ref(eid) -> pull(db_state, eid, sub_pattern)
            fact.Int(sub_id) -> pull(db_state, fact.EntityId(sub_id), sub_pattern)
            _ -> query_types.PullSingle(v)
          }
        })
      case nested {
        [r] -> dict.insert(acc, name, r)
        [_, ..] -> dict.insert(acc, name, query_types.PullNestedMany(nested))
        _ -> acc
      }
    }
    _ -> acc
  }
}
