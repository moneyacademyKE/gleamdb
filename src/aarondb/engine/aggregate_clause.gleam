import aarondb/algo/aggregate
import aarondb/algo/cracking
import aarondb/algo/vectorized
import aarondb/engine/solver_context
import aarondb/fact
import aarondb/shared/ast
import aarondb/shared/state
import aarondb/storage/internal
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}

pub type NestedSolver =
  fn(
    solver_context.SolverContext,
    List(ast.BodyClause),
    List(Dict(String, fact.Value)),
  ) -> #(
    List(Dict(String, fact.Value)),
    Option(Dict(String, List(internal.StorageChunk))),
  )

pub fn solve(
  ctx: Dict(String, fact.Value),
  var: String,
  func: ast.AggFunc,
  target_var: String,
  solver: solver_context.SolverContext,
  clauses: List(ast.BodyClause),
  nested_solve: NestedSolver,
) -> #(
  List(Dict(String, fact.Value)),
  Option(Dict(String, List(internal.StorageChunk))),
) {
  let config = schema_config(solver.db_state, target_var)

  case config.layout, clauses {
    fact.Columnar, filters -> {
      columnar_aggregate(
        ctx,
        var,
        func,
        target_var,
        solver,
        clauses,
        filters,
        nested_solve,
      )
    }
    _, _ -> {
      let target_values =
        get_values_row_based(solver, clauses, ctx, target_var, nested_solve)
      case aggregate.aggregate(target_values, func) {
        Ok(val) -> #([dict.insert(ctx, var, val)], None)
        Error(_) -> #([], None)
      }
    }
  }
}

fn columnar_aggregate(
  ctx: Dict(String, fact.Value),
  var: String,
  func: ast.AggFunc,
  target_var: String,
  solver: solver_context.SolverContext,
  clauses: List(ast.BodyClause),
  filters: List(ast.BodyClause),
  nested_solve: NestedSolver,
) -> #(
  List(Dict(String, fact.Value)),
  Option(Dict(String, List(internal.StorageChunk))),
) {
  let chunks =
    dict.get(solver.db_state.columnar_store, target_var) |> gleam_result_unwrap([])

  let cracking_pivots =
    list.filter_map(filters, fn(c) {
      case c {
        ast.Filter(ast.Gt(ast.Var(v), ast.Val(p))) if v == target_var -> Ok(p)
        ast.Filter(ast.Lt(ast.Var(v), ast.Val(p))) if v == target_var -> Ok(p)
        _ -> Error(Nil)
      }
    })

  let #(updated_chunks, was_cracked) = case cracking_pivots {
    [pivot, ..] -> {
      let nc = list.map(chunks, fn(c) { cracking.crack_chunk(c, pivot) })
      #(nc, True)
    }
    _ -> #(chunks, False)
  }

  let agg_val = case func {
    ast.Sum ->
      fact.Float(list.fold(updated_chunks, 0.0, fn(acc, c) {
        acc +. vectorized.sum_column(c)
      }))
    ast.Avg -> {
      let total_sum =
        list.fold(updated_chunks, 0.0, fn(acc, c) {
          acc +. vectorized.sum_column(c)
        })
      let total_count =
        list.fold(updated_chunks, 0, fn(acc, c) {
          acc + vectorized.count_node(c.values)
        })
      case total_count {
        0 -> fact.Float(0.0)
        _ -> fact.Float(total_sum /. int.to_float(total_count))
      }
    }
    _ -> {
      let target_values =
        get_values_row_based(solver, clauses, ctx, target_var, nested_solve)
      case aggregate.aggregate(target_values, func) {
        Ok(val) -> val
        Error(_) -> fact.Int(0)
      }
    }
  }

  let res_ctx = [dict.insert(ctx, var, agg_val)]
  let updated_store = case was_cracked {
    True -> Some(dict.from_list([#(target_var, updated_chunks)]))
    False -> None
  }
  #(res_ctx, updated_store)
}

fn get_values_row_based(
  solver: solver_context.SolverContext,
  clauses: List(ast.BodyClause),
  ctx: Dict(String, fact.Value),
  target_var: String,
  nested_solve: NestedSolver,
) -> List(fact.Value) {
  let #(sub_results, _store) = case clauses {
    [] -> #([ctx], None)
    _ -> nested_solve(solver, clauses, [ctx])
  }

  list.filter_map(sub_results, fn(res) { dict.get(res, target_var) })
}

fn schema_config(db_state: state.DbState, attribute: String) -> fact.AttributeConfig {
  dict.get(db_state.schema, attribute)
  |> gleam_result_unwrap(fact.AttributeConfig(
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

fn gleam_result_unwrap(res: Result(a, b), default: a) -> a {
  case res {
    Ok(v) -> v
    Error(_) -> default
  }
}
