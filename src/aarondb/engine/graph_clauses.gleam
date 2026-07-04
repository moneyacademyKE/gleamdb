import aarondb/algo/graph
import aarondb/fact
import aarondb/shared/ast
import aarondb/shared/state
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, None, Some}

pub fn shortest_path(
  db_state: state.DbState,
  from: ast.Part,
  to: ast.Part,
  edge: String,
  path_var: String,
  cost_var: Option(String),
  max_depth: Option(Int),
  ctx: Dict(String, fact.Value),
) -> List(Dict(String, fact.Value)) {
  let from_eid = resolve_entity_id(from, ctx)
  let to_eid = resolve_entity_id(to, ctx)

  case from_eid, to_eid {
    Some(f), Some(t) -> {
      case graph.shortest_path(db_state, f, t, edge, max_depth) {
        Some(path) -> {
          let path_val = fact.List(list.map(path, fact.Ref))
          let ctx = dict.insert(ctx, path_var, path_val)
          let ctx = case cost_var {
            Some(cv) -> dict.insert(ctx, cv, fact.Int(list.length(path) - 1))
            None -> ctx
          }
          [ctx]
        }
        None -> []
      }
    }
    _, _ -> []
  }
}

pub fn pagerank(
  db_state: state.DbState,
  entity_var: String,
  edge: String,
  rank_var: String,
  damping: Float,
  iterations: Int,
  ctx: Dict(String, fact.Value),
) -> List(Dict(String, fact.Value)) {
  let ranks = graph.pagerank(db_state, edge, damping, iterations)
  bind_score_map(ranks, entity_var, rank_var, ctx)
}

pub fn reachable(
  db_state: state.DbState,
  from: ast.Part,
  edge: String,
  node_var: String,
  ctx: Dict(String, fact.Value),
) -> List(Dict(String, fact.Value)) {
  case resolve_entity_id(from, ctx) {
    Some(eid) -> {
      graph.reachable(db_state, eid, edge)
      |> list.map(fn(n) { dict.insert(ctx, node_var, fact.Ref(n)) })
    }
    None -> []
  }
}

pub fn connected_components(
  db_state: state.DbState,
  edge: String,
  entity_var: String,
  component_var: String,
  ctx: Dict(String, fact.Value),
) -> List(Dict(String, fact.Value)) {
  graph.connected_components(db_state, edge)
  |> bind_int_map(entity_var, component_var, ctx)
}

pub fn neighbors(
  db_state: state.DbState,
  from: ast.Part,
  edge: String,
  depth: Int,
  node_var: String,
  ctx: Dict(String, fact.Value),
) -> List(Dict(String, fact.Value)) {
  case resolve_entity_id(from, ctx) {
    Some(eid) -> {
      graph.neighbors_khop(db_state, eid, edge, depth)
      |> list.map(fn(n) { dict.insert(ctx, node_var, fact.Ref(n)) })
    }
    None -> []
  }
}

pub fn strongly_connected(
  db_state: state.DbState,
  edge: String,
  entity_var: String,
  component_var: String,
  ctx: Dict(String, fact.Value),
) -> List(Dict(String, fact.Value)) {
  graph.strongly_connected_components(db_state, edge)
  |> bind_int_map(entity_var, component_var, ctx)
}

pub fn cycle_detect(
  db_state: state.DbState,
  edge: String,
  cycle_var: String,
  ctx: Dict(String, fact.Value),
) -> List(Dict(String, fact.Value)) {
  graph.cycle_detect(db_state, edge)
  |> list.map(fn(cycle) {
    dict.insert(ctx, cycle_var, fact.List(list.map(cycle, fact.Ref)))
  })
}

pub fn betweenness(
  db_state: state.DbState,
  edge: String,
  entity_var: String,
  score_var: String,
  ctx: Dict(String, fact.Value),
) -> List(Dict(String, fact.Value)) {
  graph.betweenness_centrality(db_state, edge)
  |> bind_score_map(entity_var, score_var, ctx)
}

pub fn topological_sort(
  db_state: state.DbState,
  edge: String,
  entity_var: String,
  order_var: String,
  ctx: Dict(String, fact.Value),
) -> List(Dict(String, fact.Value)) {
  case graph.topological_sort(db_state, edge) {
    Ok(ordered) -> {
      list.index_map(ordered, fn(node, idx) {
        let new_ctx = dict.insert(ctx, entity_var, fact.Ref(node))
        dict.insert(new_ctx, order_var, fact.Int(idx))
      })
    }
    Error(_) -> []
  }
}

fn bind_int_map(
  values: Dict(fact.EntityId, Int),
  entity_var: String,
  value_var: String,
  ctx: Dict(String, fact.Value),
) -> List(Dict(String, fact.Value)) {
  case dict.get(ctx, entity_var) {
    Ok(fact.Ref(eid)) -> {
      case dict.get(values, eid) {
        Ok(value) -> [dict.insert(ctx, value_var, fact.Int(value))]
        Error(_) -> []
      }
    }
    Ok(fact.Int(eid_int)) -> {
      case dict.get(values, fact.EntityId(eid_int)) {
        Ok(value) -> [dict.insert(ctx, value_var, fact.Int(value))]
        Error(_) -> []
      }
    }
    Error(_) -> {
      dict.fold(values, [], fn(acc, eid, value) {
        let new_ctx = dict.insert(ctx, entity_var, fact.Ref(eid))
        let new_ctx = dict.insert(new_ctx, value_var, fact.Int(value))
        [new_ctx, ..acc]
      })
    }
    _ -> []
  }
}

fn bind_score_map(
  values: Dict(fact.EntityId, Float),
  entity_var: String,
  value_var: String,
  ctx: Dict(String, fact.Value),
) -> List(Dict(String, fact.Value)) {
  case dict.get(ctx, entity_var) {
    Ok(fact.Ref(eid)) -> {
      case dict.get(values, eid) {
        Ok(value) -> [dict.insert(ctx, value_var, fact.Float(value))]
        Error(_) -> []
      }
    }
    Ok(fact.Int(eid_int)) -> {
      case dict.get(values, fact.EntityId(eid_int)) {
        Ok(value) -> [dict.insert(ctx, value_var, fact.Float(value))]
        Error(_) -> []
      }
    }
    Error(_) -> {
      dict.fold(values, [], fn(acc, eid, value) {
        let new_ctx = dict.insert(ctx, entity_var, fact.Ref(eid))
        let new_ctx = dict.insert(new_ctx, value_var, fact.Float(value))
        [new_ctx, ..acc]
      })
    }
    _ -> []
  }
}

fn resolve_entity_id(
  part: ast.Part,
  ctx: Dict(String, fact.Value),
) -> Option(fact.EntityId) {
  case resolve_part(part, ctx) {
    Some(fact.Ref(eid)) -> Some(eid)
    Some(fact.Int(i)) -> Some(fact.EntityId(i))
    _ -> None
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
