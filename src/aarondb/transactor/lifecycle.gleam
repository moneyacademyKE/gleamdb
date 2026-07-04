import aarondb/engine/prefetch
import aarondb/fact
import aarondb/index
import aarondb/index/ets as ets_index
import aarondb/shared/state
import aarondb/storage
import gleam/dict
import gleam/list
import gleam/option.{None, Some}

pub fn handle_tick(state: state.DbState) -> state.DbState {
  let current_tx = state.latest_tx
  let cut_off = current_tx - state.config.batch_size

  let disk_attrs =
    dict.to_list(state.schema)
    |> list.filter(fn(item) {
      let #(_, config) = item
      config.tier == fact.Disk
    })
    |> list.map(fn(item) { item.0 })

  let #(new_eavt, new_aevt, new_avet) =
    list.fold(disk_attrs, #(state.eavt, state.aevt, state.avet), fn(acc, attr) {
      let #(acc_eavt, acc_aevt, acc_avet) = acc
      let cold =
        index.get_cold_datoms(acc_eavt, cut_off)
        |> list.filter(fn(d: fact.Datom) { d.attribute == attr })

      case cold {
        [] -> acc
        _ -> {
          let _ = storage.append(state.adapter, cold)
          case state.ets_name {
            Some(name) -> {
              list.each(cold, fn(d) {
                let _ = ets_index.insert_datom(name <> "_eavt", d.entity, d)
                let _ = ets_index.insert_datom(name <> "_aevt", d.attribute, d)
              })
            }
            None -> Nil
          }
          let next_eavt = index.evict_from_memory(acc_eavt, cold)
          let next_aevt =
            list.fold(cold, acc_aevt, fn(a, d) { index.delete_aevt(a, d) })
          let next_avet =
            list.fold(cold, acc_avet, fn(a, d) { index.delete_avet(a, d) })
          #(next_eavt, next_aevt, next_avet)
        }
      }
    })

  case state.config.prefetch_enabled {
    True -> {
      let _hot_attrs = prefetch.analyze_history(state.query_history)
      case state.ets_name {
        Some(_name) -> Nil
        None -> Nil
      }
    }
    False -> Nil
  }

  state.DbState(..state, eavt: new_eavt, aevt: new_aevt, avet: new_avet)
}
