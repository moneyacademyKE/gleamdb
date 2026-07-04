import aarondb/engine/entity
import aarondb/fact
import aarondb/index
import aarondb/index/ets as ets_index
import aarondb/shared/query_types
import aarondb/shared/state
import gleam/list
import gleam/option.{None, Some}

pub fn traverse(
  db_state: state.DbState,
  start_id: Int,
  expr: query_types.TraversalExpr,
  max_depth: Int,
) -> Result(List(fact.Value), String) {
  case list.length(expr) > max_depth {
    True -> Error("DepthLimitExceeded")
    False -> {
      let result_eids = do_traverse(db_state, [start_id], expr)
      Ok(list.map(result_eids, fn(id) { fact.Ref(fact.EntityId(id)) }))
    }
  }
}

fn do_traverse(
  db_state: state.DbState,
  current_ids: List(Int),
  expr: query_types.TraversalExpr,
) -> List(Int) {
  case expr {
    [] -> current_ids
    [step, ..rest] -> {
      let next_ids =
        list.fold(current_ids, [], fn(acc, id) {
          let step_results = case step {
            query_types.Out(attr) -> outgoing(db_state, id, attr)
            query_types.In(attr) -> incoming(db_state, id, attr)
          }
          list.append(step_results, acc)
        })
        |> list.unique()

      do_traverse(db_state, next_ids, rest)
    }
  }
}

fn outgoing(db_state: state.DbState, id: Int, attr: String) -> List(Int) {
  let datoms = case db_state.ets_name {
    Some(name) ->
      ets_index.lookup_datoms(name <> "_eavt", fact.EntityId(id))
      |> list.filter(fn(d: fact.Datom) { d.attribute == attr })
    None ->
      index.get_datoms_by_entity_attr(db_state.eavt, fact.EntityId(id), attr)
  }

  entity.filter_active(datoms, db_state)
  |> list.filter_map(fn(d) {
    case d.value {
      fact.Ref(fact.EntityId(v_id)) -> Ok(v_id)
      fact.Int(v_id) -> Ok(v_id)
      _ -> Error(Nil)
    }
  })
}

fn incoming(db_state: state.DbState, id: Int, attr: String) -> List(Int) {
  let datoms = case db_state.ets_name {
    Some(name) ->
      ets_index.lookup_datoms(name <> "_aevt", attr)
      |> list.filter(fn(d: fact.Datom) {
        case d.value {
          fact.Ref(fact.EntityId(v_id)) -> v_id == id
          fact.Int(v_id) -> v_id == id
          _ -> False
        }
      })
    None ->
      index.get_datoms_by_val(db_state.aevt, attr, fact.Ref(fact.EntityId(id)))
  }

  entity.filter_active(datoms, db_state)
  |> list.map(fn(d) {
    let fact.EntityId(e) = d.entity
    e
  })
}
