import aarondb/engine/entity
import aarondb/fact
import aarondb/index
import aarondb/shared/state
import aarondb/vec_index
import aarondb/vector
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option}

pub fn similarity(
  db_state: state.DbState,
  var: String,
  vec: List(Float),
  threshold: Float,
  ctx: Dict(String, fact.Value),
  as_of_tx: Option(Int),
  as_of_valid: Option(Int),
) -> List(Dict(String, fact.Value)) {
  case dict.get(ctx, var) {
    Ok(fact.Vec(v)) -> {
      let dist =
        vector.cosine_similarity(vector.normalize(vec), vector.normalize(v))
      case dist >=. threshold {
        True -> [ctx]
        False -> []
      }
    }
    Ok(_) -> []
    Error(Nil) -> unbound_similarity(db_state, var, vec, threshold, ctx, as_of_tx, as_of_valid)
  }
}

pub fn custom_index(
  db_state: state.DbState,
  var: String,
  index_name: String,
  query: state.IndexQuery,
  threshold: Float,
  ctx: Dict(String, fact.Value),
  as_of_tx: Option(Int),
  as_of_valid: Option(Int),
) -> List(Dict(String, fact.Value)) {
  case dict.get(db_state.extensions, index_name) {
    Ok(instance) -> {
      case dict.get(db_state.registry, instance.adapter_name) {
        Ok(adapter) -> {
          adapter.search(instance.data, query, threshold)
          |> list.filter_map(fn(eid) {
            let active =
              index.get_datoms_by_entity(db_state.eavt, eid)
              |> entity.filter_by_time(as_of_tx, as_of_valid)
              |> entity.filter_active(db_state)

            case active {
              [d, ..] -> bind(ctx, var, fact.Ref(d.entity))
              [] -> Error(Nil)
            }
          })
        }
        Error(_) -> []
      }
    }
    Error(_) -> []
  }
}

pub fn similarity_entity(
  db_state: state.DbState,
  var: String,
  vec: List(Float),
  threshold: Float,
  ctx: Dict(String, fact.Value),
) -> List(Dict(String, fact.Value)) {
  case vec_index.size(db_state.vec_index) > 0 {
    True -> {
      let norm_vec = vector.normalize(vec)
      vec_index.search(db_state.vec_index, norm_vec, threshold, 100)
      |> list.filter_map(fn(r) { bind(ctx, var, fact.Ref(r.entity)) })
    }
    False -> []
  }
}

fn unbound_similarity(
  db_state: state.DbState,
  var: String,
  vec: List(Float),
  threshold: Float,
  ctx: Dict(String, fact.Value),
  as_of_tx: Option(Int),
  as_of_valid: Option(Int),
) -> List(Dict(String, fact.Value)) {
  case vec_index.size(db_state.vec_index) > 0 {
    True -> {
      let norm_vec = vector.normalize(vec)
      vec_index.search(db_state.vec_index, norm_vec, threshold, 100)
      |> list.filter_map(fn(r) {
        case
          index.filter_by_entity(db_state.eavt, r.entity)
          |> entity.filter_by_time(as_of_tx, as_of_valid)
          |> entity.filter_active(db_state)
          |> list.filter(fn(d: fact.Datom) {
            case d.value {
              fact.Vec(_) -> d.operation == fact.Assert
              _ -> False
            }
          })
        {
          [d, ..] -> Ok(dict.insert(ctx, var, d.value))
          [] -> Error(Nil)
        }
      })
    }
    False -> {
      index.get_all_datoms_avet(db_state.avet)
      |> entity.filter_by_time(as_of_tx, as_of_valid)
      |> entity.filter_active(db_state)
      |> list.filter_map(fn(d: fact.Datom) {
        case d.value {
          fact.Vec(v) -> {
            let dist = vector.cosine_similarity(vec, v)
            case dist >=. threshold {
              True -> Ok(d)
              False -> Error(Nil)
            }
          }
          _ -> Error(Nil)
        }
      })
      |> list.map(fn(d: fact.Datom) { dict.insert(ctx, var, d.value) })
    }
  }
}

fn bind(
  ctx: Dict(String, fact.Value),
  var: String,
  val: fact.Value,
) -> Result(Dict(String, fact.Value), Nil) {
  case dict.get(ctx, var) {
    Ok(existing) if existing == val -> Ok(ctx)
    Ok(_) -> Error(Nil)
    Error(Nil) -> Ok(dict.insert(ctx, var, val))
  }
}
