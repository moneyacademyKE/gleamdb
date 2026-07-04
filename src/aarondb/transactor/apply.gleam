import aarondb/fact
import aarondb/index
import aarondb/index/art
import aarondb/index/ets as ets_index
import aarondb/shared/state
import aarondb/storage/internal
import aarondb/vec_index
import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import gleam/result

pub fn apply_datom(
  state: state.DbState,
  d: fact.Datom,
  tx_idx_counter: Int,
) -> #(state.DbState, List(fact.Datom), Int) {
  let config = attribute_config(state, d.attribute)

  let #(state_after_cascade, cascade_datoms, cascade_idx) =
    component_cascade(state, d, tx_idx_counter, config)

  let #(state_after_card, card_datoms, card_idx) =
    cardinality_one(state_after_cascade, d, cascade_idx, config)

  let state_after_retention = retention_policy(state_after_card, d, config)
  let d_with_idx = fact.Datom(..d, tx_index: card_idx)
  let final_state = update_indices(state_after_retention, d_with_idx)

  #(
    final_state,
    list.append(list.append(cascade_datoms, card_datoms), [d_with_idx]),
    card_idx + 1,
  )
}

pub fn update_indices(state: state.DbState, d: fact.Datom) -> state.DbState {
  let art_index = art.insert(state.art_index, d.value, d.entity)
  let vec_index = case d.value {
    fact.Vec(v) ->
      case d.operation {
        fact.Assert -> vec_index.insert(state.vec_index, d.entity, v)
        fact.Retract -> state.vec_index
      }
    _ -> state.vec_index
  }

  let columnar_store = case d.operation {
    fact.Assert -> update_columnar_store(state, d)
    _ -> state.columnar_store
  }

  let state =
    state.DbState(
      ..state,
      eavt: index.insert_eavt(state.eavt, d, fact.All),
      aevt: index.insert_aevt(state.aevt, d, fact.All),
      avet: index.insert_avet(state.avet, d),
      art_index: art_index,
      vec_index: vec_index,
      columnar_store: columnar_store,
    )

  case state.ets_name {
    Some(name) -> {
      let _ = ets_index.insert_datom(name <> "_eavt", d.entity, d)
      let _ = ets_index.insert_datom(name <> "_aevt", d.attribute, d)
      let avet_table = name <> "_avet"
      case d.operation {
        fact.Assert ->
          ets_index.insert_avet(avet_table, #(d.attribute, d.value), d.entity)
        fact.Retract -> ets_index.delete(avet_table, #(d.attribute, d.value))
      }
      state
    }
    None -> state
  }
}

pub fn resolve_transaction_functions(
  state: state.DbState,
  tx_id: Int,
  vt: Int,
  facts: List(fact.Fact),
) -> List(fact.Fact) {
  list.flat_map(facts, fn(f) {
    case f.0 {
      fact.Lookup(lu) -> {
        let #(a, v) = lu
        case a == "db/fn" {
          True -> {
            let func_name = case v {
              fact.Str(s) -> s
              _ -> fact.to_string(v)
            }
            case dict.get(state.functions, func_name) {
              Ok(func) -> {
                let args = case f.2 {
                  fact.List(l) -> l
                  _ -> []
                }
                func(state, tx_id, vt, args)
              }
              Error(_) -> [f]
            }
          }
          False -> [f]
        }
      }
      _ ->
        case f.2 {
          fact.List([fact.Str("db/id"), ..]) -> [#(f.0, f.1, fact.Int(tx_id))]
          _ -> [f]
        }
    }
  })
}

fn attribute_config(
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

fn component_cascade(
  state: state.DbState,
  d: fact.Datom,
  tx_idx_counter: Int,
  config: fact.AttributeConfig,
) -> #(state.DbState, List(fact.Datom), Int) {
  case config.component && d.operation == fact.Retract {
    True -> {
      let children = case d.value {
        fact.Ref(eid) -> [eid]
        fact.Int(eid_int) -> [fact.EntityId(eid_int)]
        _ -> []
      }
      list.fold(children, #(state, [], tx_idx_counter), fn(acc, child_eid) {
        let #(curr_state, curr_datoms, idx) = acc
        let child_datoms = index.filter_by_entity(curr_state.eavt, child_eid)
        list.fold(child_datoms, #(curr_state, curr_datoms, idx), fn(acc2, cd) {
          let #(s2, d2, i2) = acc2
          let r_d =
            fact.Datom(..cd, operation: fact.Retract, tx: d.tx, tx_index: i2)
          #(update_indices(s2, r_d), [r_d, ..d2], i2 + 1)
        })
      })
    }
    False -> #(state, [], tx_idx_counter)
  }
}

fn cardinality_one(
  state: state.DbState,
  d: fact.Datom,
  tx_idx_counter: Int,
  config: fact.AttributeConfig,
) -> #(state.DbState, List(fact.Datom), Int) {
  case config.cardinality == fact.One && d.operation == fact.Assert {
    True -> {
      let all_datoms =
        index.get_datoms_by_entity_attr(state.eavt, d.entity, d.attribute)
      let asserts =
        list.filter(all_datoms, fn(d) { d.operation == fact.Assert })
      let retractions =
        list.filter(all_datoms, fn(d) { d.operation == fact.Retract })
      let active_asserts =
        list.filter(asserts, fn(ad) {
          !list.any(retractions, fn(rd) {
            rd.value == ad.value && rd.tx >= ad.tx
          })
        })

      list.fold(active_asserts, #(state, [], tx_idx_counter), fn(acc, old_d) {
        let #(s, ds, i) = acc
        let r_d =
          fact.Datom(..old_d, operation: fact.Retract, tx: d.tx, tx_index: i)
        #(update_indices(s, r_d), [r_d, ..ds], i + 1)
      })
    }
    False -> #(state, [], tx_idx_counter)
  }
}

fn retention_policy(
  state: state.DbState,
  d: fact.Datom,
  config: fact.AttributeConfig,
) -> state.DbState {
  case config.retention == fact.LatestOnly && d.operation == fact.Assert {
    True -> {
      let existing =
        index.get_datoms_by_entity_attr(state.eavt, d.entity, d.attribute)
      list.fold(existing, state, fn(acc, old_d) {
        state.DbState(..acc, eavt: index.evict_from_memory(acc.eavt, [old_d]))
      })
    }
    False -> state
  }
}

fn update_columnar_store(
  state: state.DbState,
  d: fact.Datom,
) -> dict.Dict(String, List(internal.StorageChunk)) {
  let chunks = dict.get(state.columnar_store, d.attribute) |> result.unwrap([])
  case chunks {
    [] -> {
      let chunk =
        internal.StorageChunk(
          attribute: d.attribute,
          values: internal.Leaf([d.value]),
          max_tx: 0,
          is_compressed: False,
        )
      dict.insert(state.columnar_store, d.attribute, [chunk])
    }
    [last, ..rest] -> {
      let updated = case last.values {
        internal.Leaf(l) -> internal.Leaf(list.append(l, [d.value]))
        node -> node
      }
      dict.insert(state.columnar_store, d.attribute, [
        internal.StorageChunk(..last, values: updated),
        ..rest
      ])
    }
  }
}
