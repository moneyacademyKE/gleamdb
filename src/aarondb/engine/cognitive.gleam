import aarondb/engine/entity
import aarondb/fact
import aarondb/index
import aarondb/shared/ast
import aarondb/shared/state
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/set

/// Solve AaronDB's local cognitive clause over explicit engram facts.
///
/// An entity matches only when it has active `engram/concept` and
/// `engram/context` facts matching the supplied parts. Its relevance is the
/// maximum active numeric `engram/relevance` value; an entity with no relevance
/// fact has relevance `1.0`, while one with only non-numeric relevance facts has
/// relevance `0.0`. The threshold comparison is inclusive.
///
/// This module performs no learning, decay, vector embedding, or external
/// retrieval. Relevance changes only through ordinary fact assertions and
/// retractions, and temporal bases select the active facts visible at that
/// basis.
pub fn solve(
  db_state: state.DbState,
  concept: ast.Part,
  context: ast.Part,
  threshold: Float,
  engram_var: String,
  ctx: Dict(String, fact.Value),
  as_of_tx: Option(Int),
  as_of_valid: Option(Int),
) -> List(Dict(String, fact.Value)) {
  let concept_val = resolve_part(concept, ctx)
  let context_val = resolve_part(context, ctx)

  let active_concept =
    case concept_val {
      Some(v) -> index.get_datoms_by_val(db_state.aevt, "engram/concept", v)
      None -> index.get_all_datoms_for_attr(db_state.eavt, "engram/concept")
    }
    |> entity.filter_by_time(as_of_tx, as_of_valid)
    |> entity.filter_active(db_state)

  let active_context =
    case context_val {
      Some(v) -> index.get_datoms_by_val(db_state.aevt, "engram/context", v)
      None -> index.get_all_datoms_for_attr(db_state.eavt, "engram/context")
    }
    |> entity.filter_by_time(as_of_tx, as_of_valid)
    |> entity.filter_active(db_state)

  let concept_eids =
    list.map(active_concept, fn(d) { d.entity }) |> set.from_list()
  let context_eids =
    list.map(active_context, fn(d) { d.entity }) |> set.from_list()

  set.intersection(concept_eids, context_eids)
  |> set.to_list()
  |> list.filter_map(fn(eid) {
    let relevance_datoms =
      index.get_datoms_by_entity_attr(db_state.eavt, eid, "engram/relevance")
      |> entity.filter_by_time(as_of_tx, as_of_valid)
      |> entity.filter_active(db_state)

    let score = case relevance_datoms {
      [] -> 1.0
      datoms ->
        case max_numeric_relevance(datoms) {
          Some(value) -> value
          None -> 0.0
        }
    }

    case score >=. threshold {
      True -> Ok(dict.insert(ctx, engram_var, fact.Ref(eid)))
      False -> Error(Nil)
    }
  })
}

fn max_numeric_relevance(datoms: List(fact.Datom)) -> Option(Float) {
  datoms
  |> list.filter_map(relevance_value)
  |> list.fold(None, fn(best, value) {
    case best {
      None -> Some(value)
      Some(previous) ->
        case value >. previous {
          True -> Some(value)
          False -> Some(previous)
        }
    }
  })
}

fn relevance_value(datom: fact.Datom) -> Result(Float, Nil) {
  case datom.value {
    fact.Float(value) -> Ok(value)
    fact.Int(value) -> Ok(int.to_float(value))
    _ -> Error(Nil)
  }
}

fn resolve_part(
  part: ast.Part,
  ctx: Dict(String, fact.Value),
) -> Option(fact.Value) {
  case part {
    ast.Var(name) -> option.from_result(dict.get(ctx, name))
    ast.Val(val) -> Some(val)
    ast.Uid(uid) -> Some(fact.Ref(uid))
    ast.AttrVal(s) -> Some(fact.Str(s))
    ast.Lookup(#(_, val)) -> Some(val)
  }
}
