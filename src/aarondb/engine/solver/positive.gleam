import aarondb/algo/cracking
import aarondb/algo/vectorized
import aarondb/engine/entity
import aarondb/engine/morsel
import aarondb/engine/solver/bindings
import aarondb/fact
import aarondb/index
import aarondb/index/ets as ets_index
import aarondb/shared/ast
import aarondb/shared/state
import aarondb/storage
import aarondb/storage/internal
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, None, Some}

pub fn positive_with_state(
  db_state: state.DbState,
  triple: ast.Clause,
  ctx: Dict(String, fact.Value),
  as_of_tx: Option(Int),
  as_of_valid: Option(Int),
) -> #(
  List(Dict(String, fact.Value)),
  Option(Dict(String, List(internal.StorageChunk))),
) {
  let #(e_p, attr, v_p) = triple
  let e_val = bindings.resolve_part(e_p, ctx)
  let v_val = bindings.resolve_part(v_p, ctx)

  let #(base_datoms, new_store) = case dict.get(db_state.columnar_store, attr) {
    Ok(chunks) -> {
      let updated_chunks = case v_val {
        Some(v) ->
          list.map(chunks, fn(chunk) {
            let new_values = cracking.partition(chunk.values, v)
            internal.StorageChunk(..chunk, values: new_values)
          })
        None -> chunks
      }
      let datoms = vectorized.chunks_to_datoms(updated_chunks)
      #(datoms, Some(dict.from_list([#(attr, updated_chunks)])))
    }
    Error(_) -> {
      let adapter_datoms = case storage.query_datoms(db_state.adapter, triple) {
        Ok(datoms) if datoms != [] -> datoms
        _ -> []
      }

      let base_datoms = case adapter_datoms {
        [] -> {
          let memory_datoms = lookup_memory(db_state, e_val, attr, v_val)
          let disk_datoms = lookup_ets(db_state, e_val, attr, v_val)
          list.append(memory_datoms, disk_datoms)
        }
        _ -> adapter_datoms
      }
      #(base_datoms, None)
    }
  }

  let active =
    base_datoms
    |> entity.filter_by_time(as_of_tx, as_of_valid)
    |> entity.filter_active(db_state)

  let results =
    morsel.execute_morsels(active, [ctx], e_p, v_p, db_state.config.batch_size)

  #(results, new_store)
}

pub fn positive(
  db_state: state.DbState,
  triple: ast.Clause,
  ctx: Dict(String, fact.Value),
  as_of_tx: Option(Int),
  as_of_valid: Option(Int),
) -> List(Dict(String, fact.Value)) {
  positive_with_state(db_state, triple, ctx, as_of_tx, as_of_valid).0
}

pub fn negative(
  db_state: state.DbState,
  triple: ast.Clause,
  ctx: Dict(String, fact.Value),
  as_of_tx: Option(Int),
  as_of_valid: Option(Int),
) -> List(Dict(String, fact.Value)) {
  case positive(db_state, triple, ctx, as_of_tx, as_of_valid) {
    [] -> [ctx]
    _ -> []
  }
}

fn lookup_memory(
  db_state: state.DbState,
  e_val: Option(fact.Value),
  attr: String,
  v_val: Option(fact.Value),
) -> List(fact.Datom) {
  case e_val, v_val {
    Some(fact.Ref(fact.EntityId(e))), Some(v) ->
      index.get_datoms_by_entity_attr_val(
        db_state.eavt,
        fact.EntityId(e),
        attr,
        v,
      )
    Some(fact.Ref(fact.EntityId(e))), None ->
      index.get_datoms_by_entity_attr(db_state.eavt, fact.EntityId(e), attr)
    Some(fact.Int(e)), Some(v) ->
      index.get_datoms_by_entity_attr_val(
        db_state.eavt,
        fact.EntityId(e),
        attr,
        v,
      )
    Some(fact.Int(e)), None ->
      index.get_datoms_by_entity_attr(db_state.eavt, fact.EntityId(e), attr)
    None, Some(v) -> index.get_datoms_by_val(db_state.aevt, attr, v)
    None, None -> index.get_all_datoms_for_attr(db_state.eavt, attr)
    Some(_), _ -> []
  }
}

fn lookup_ets(
  db_state: state.DbState,
  e_val: Option(fact.Value),
  attr: String,
  v_val: Option(fact.Value),
) -> List(fact.Datom) {
  case db_state.ets_name {
    Some(name) ->
      case e_val, v_val {
        Some(fact.Ref(fact.EntityId(e))), Some(v) ->
          ets_index.lookup_datoms(name <> "_eavt", fact.EntityId(e))
          |> list.filter(fn(d: fact.Datom) {
            d.attribute == attr && d.value == v
          })
        Some(fact.Ref(fact.EntityId(e))), None ->
          ets_index.lookup_datoms(name <> "_eavt", fact.EntityId(e))
          |> list.filter(fn(d: fact.Datom) { d.attribute == attr })
        Some(fact.Int(e)), Some(v) ->
          ets_index.lookup_datoms(name <> "_eavt", fact.EntityId(e))
          |> list.filter(fn(d: fact.Datom) {
            d.attribute == attr && d.value == v
          })
        Some(fact.Int(e)), None ->
          ets_index.lookup_datoms(name <> "_eavt", fact.EntityId(e))
          |> list.filter(fn(d: fact.Datom) { d.attribute == attr })
        None, Some(v) ->
          ets_index.lookup_datoms(name <> "_aevt", attr)
          |> list.filter(fn(d: fact.Datom) { d.value == v })
        None, None -> ets_index.lookup_datoms(name <> "_aevt", attr)
        Some(_), _ -> []
      }
    None -> []
  }
}
