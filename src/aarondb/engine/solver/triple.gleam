import aarondb/engine/entity
import aarondb/engine/solver/bindings
import aarondb/fact
import aarondb/index
import aarondb/index/ets as ets_index
import aarondb/shared/ast
import aarondb/shared/state
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/set.{type Set}

pub fn solve(
  db_state: state.DbState,
  triple: ast.Clause,
  ctx: Dict(String, fact.Value),
  derived: Set(fact.Datom),
  as_of_tx: Option(Int),
  as_of_valid: Option(Int),
) -> List(Dict(String, fact.Value)) {
  let #(e_p, attr, v_p) = triple
  let e_val = bindings.resolve_part(e_p, ctx)
  let v_val = bindings.resolve_part(v_p, ctx)

  let base_datoms = lookup_base_datoms(db_state, e_val, attr, v_val)
  let derived_datoms = filter_derived(derived, attr, e_val, v_val)
  let all = list.append(base_datoms, derived_datoms)

  let active =
    all
    |> entity.filter_by_time(as_of_tx, as_of_valid)
    |> entity.filter_active(db_state)
    |> list.filter(fn(d) { d.operation == fact.Assert })

  list.map(active, fn(d: fact.Datom) {
    let b = ctx
    let b = case e_p {
      ast.Var(n) -> dict.insert(b, n, fact.Ref(d.entity))
      _ -> b
    }
    let b = case v_p {
      ast.Var(n) -> dict.insert(b, n, d.value)
      _ -> b
    }
    b
  })
}

fn lookup_base_datoms(
  db_state: state.DbState,
  e_val: Option(fact.Value),
  attr: String,
  v_val: Option(fact.Value),
) -> List(fact.Datom) {
  case db_state.ets_name {
    Some(name) -> lookup_ets(name, e_val, attr, v_val)
    None -> lookup_memory(db_state, e_val, attr, v_val)
  }
}

fn lookup_ets(
  name: String,
  e_val: Option(fact.Value),
  attr: String,
  v_val: Option(fact.Value),
) -> List(fact.Datom) {
  case e_val, v_val {
    Some(fact.Ref(fact.EntityId(e))), Some(v) ->
      ets_index.lookup_datoms(name <> "_eavt", fact.EntityId(e))
      |> list.filter(fn(d: fact.Datom) { d.attribute == attr && d.value == v })
    Some(fact.Ref(fact.EntityId(e))), None ->
      ets_index.lookup_datoms(name <> "_eavt", fact.EntityId(e))
      |> list.filter(fn(d: fact.Datom) { d.attribute == attr })
    Some(fact.Int(e)), Some(v) ->
      ets_index.lookup_datoms(name <> "_eavt", fact.EntityId(e))
      |> list.filter(fn(d: fact.Datom) { d.attribute == attr && d.value == v })
    Some(fact.Int(e)), None ->
      ets_index.lookup_datoms(name <> "_eavt", fact.EntityId(e))
      |> list.filter(fn(d: fact.Datom) { d.attribute == attr })
    None, Some(v) ->
      ets_index.lookup_datoms(name <> "_aevt", attr)
      |> list.filter(fn(d: fact.Datom) { d.value == v })
    None, None -> ets_index.lookup_datoms(name <> "_aevt", attr)
    Some(_), _ -> []
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

fn filter_derived(
  derived: Set(fact.Datom),
  attr: String,
  e_val: Option(fact.Value),
  v_val: Option(fact.Value),
) -> List(fact.Datom) {
  set.to_list(derived)
  |> list.filter(fn(d) {
    let attr_match = d.attribute == attr
    let e_match = case e_val {
      Some(fact.Ref(fact.EntityId(e))) -> {
        let fact.EntityId(eid_int) = d.entity
        eid_int == e
      }
      Some(fact.Int(e)) -> {
        let fact.EntityId(eid_int) = d.entity
        eid_int == e
      }
      _ -> True
    }
    let v_match = case v_val {
      Some(v) -> d.value == v
      _ -> True
    }
    attr_match && e_match && v_match
  })
}
