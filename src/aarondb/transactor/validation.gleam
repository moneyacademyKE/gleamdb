import aarondb/fact
import aarondb/index
import aarondb/shared/state
import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string

pub fn validate_datom(
  state: state.DbState,
  tx_datoms: List(fact.Datom),
  d: fact.Datom,
) -> Result(Nil, String) {
  let config = schema_config(state, d.attribute)

  let res = validate_uniqueness(state, tx_datoms, d, config)
  let res = validate_check_constraint(state, d, config, res)
  validate_composite(state, tx_datoms, d, config, res)
}

fn schema_config(
  state: state.DbState,
  attribute: String,
) -> fact.AttributeConfig {
  dict.get(state.schema, attribute)
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

fn validate_uniqueness(
  state: state.DbState,
  tx_datoms: List(fact.Datom),
  d: fact.Datom,
  config: fact.AttributeConfig,
) -> Result(Nil, String) {
  case config.unique && d.operation == fact.Assert {
    True -> {
      let existing = index.get_datoms_by_val(state.aevt, d.attribute, d.value)
      let effectively_existing =
        list.filter(existing, fn(ed) {
          ed.operation == fact.Assert
          && !list.any(tx_datoms, fn(td) {
            td.entity == ed.entity
            && td.attribute == ed.attribute
            && td.operation == fact.Retract
          })
        })

      case effectively_existing {
        [ed, ..] if ed.entity != d.entity ->
          Error("Uniqueness violation for " <> d.attribute)
        _ -> {
          let in_flight_violation =
            list.any(tx_datoms, fn(td) {
              td.attribute == d.attribute
              && td.value == d.value
              && td.entity != d.entity
              && td.operation == fact.Assert
              && td.tx_index < d.tx_index
            })
          case in_flight_violation {
            True ->
              Error("Uniqueness violation (in-flight) for " <> d.attribute)
            False -> Ok(Nil)
          }
        }
      }
    }
    False -> Ok(Nil)
  }
}

fn validate_check_constraint(
  state: state.DbState,
  d: fact.Datom,
  config: fact.AttributeConfig,
  prev: Result(Nil, String),
) -> Result(Nil, String) {
  case prev {
    Ok(_) ->
      case config.check {
        Some(pred_name) ->
          case dict.get(state.predicates, pred_name) {
            Ok(pred) ->
              case pred(d.value) {
                True -> Ok(Nil)
                False -> Error("Check constraint failed: " <> pred_name)
              }
            Error(_) -> Ok(Nil)
          }
        None -> Ok(Nil)
      }
    Error(e) -> Error(e)
  }
}

fn validate_composite(
  state: state.DbState,
  tx_datoms: List(fact.Datom),
  d: fact.Datom,
  config: fact.AttributeConfig,
  prev: Result(Nil, String),
) -> Result(Nil, String) {
  case prev {
    Ok(_) -> {
      let registered_groups = state.composites
      let schema_groups = case config.composite_group {
        Some(group_name) -> {
          let attrs =
            dict.to_list(state.schema)
            |> list.filter(fn(item) {
              { item.1 }.composite_group == Some(group_name)
            })
            |> list.map(fn(item) { item.0 })
          [attrs]
        }
        None -> []
      }

      let all_groups = list.append(registered_groups, schema_groups)
      let groups =
        list.filter(all_groups, fn(c) { list.contains(c, d.attribute) })

      list.fold_until(groups, Ok(Nil), fn(_, attrs) {
        let current_values =
          list.fold_until(attrs, Ok([]), fn(acc_res, attr) {
            let assert Ok(acc) = acc_res
            case attr == d.attribute {
              True -> list.Continue(Ok([#(attr, d.value), ..acc]))
              False -> {
                let in_flight =
                  list.find(tx_datoms, fn(td) {
                    td.entity == d.entity
                    && td.attribute == attr
                    && td.operation == fact.Assert
                  })
                case in_flight {
                  Ok(ifd) -> list.Continue(Ok([#(attr, ifd.value), ..acc]))
                  Error(_) -> {
                    case
                      index.get_datoms_by_entity_attr(
                        state.eavt,
                        d.entity,
                        attr,
                      )
                      |> list.filter(fn(d) { d.operation == fact.Assert })
                    {
                      [existing_d, ..] ->
                        list.Continue(Ok([#(attr, existing_d.value), ..acc]))
                      [] ->
                        list.Stop(Error(
                          "Missing attribute for composite: " <> attr,
                        ))
                    }
                  }
                }
              }
            }
          })

        case current_values {
          Ok(vs) -> {
            case list.length(vs) == list.length(attrs) {
              True -> check_composite_uniqueness(state, tx_datoms, d, attrs, vs)
              False -> list.Continue(Ok(Nil))
            }
          }
          _ -> list.Continue(Ok(Nil))
        }
      })
    }
    Error(e) -> Error(e)
  }
}

fn check_composite_uniqueness(
  state: state.DbState,
  tx_datoms: List(fact.Datom),
  d: fact.Datom,
  attrs: List(String),
  vs: List(#(String, fact.Value)),
) {
  let entities_per_attr =
    list.map(vs, fn(pair) {
      let in_db =
        index.get_datoms_by_val(state.aevt, pair.0, pair.1)
        |> list.map(fn(datom) { datom.entity })
      let in_flight =
        list.filter(tx_datoms, fn(td) {
          td.attribute == pair.0
          && td.value == pair.1
          && td.operation == fact.Assert
        })
        |> list.map(fn(td) { td.entity })
      list.unique(list.append(in_db, in_flight))
    })

  let common_entities = case entities_per_attr {
    [first, ..rest] ->
      list.fold(rest, first, fn(acc, eids) {
        list.filter(acc, fn(eid) { list.contains(eids, eid) })
      })
    [] -> []
  }

  let violation = list.filter(common_entities, fn(e) { e != d.entity })
  case violation {
    [] -> list.Continue(Ok(Nil))
    _ ->
      list.Stop(Error(
        "Composite uniqueness violation: "
        <> string.inspect(list.sort(attrs, string.compare)),
      ))
  }
}
