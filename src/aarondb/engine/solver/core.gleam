import aarondb/engine/aggregate_clause.{
  type NestedSolver, solve as solve_aggregate,
}
import aarondb/engine/cognitive
import aarondb/engine/entity
import aarondb/engine/graph_clauses
import aarondb/engine/predicate
import aarondb/engine/retrieval
import aarondb/engine/solver/bindings
import aarondb/engine/solver/positive
import aarondb/engine/solver/vector_input
import aarondb/engine/solver_context
import aarondb/engine/string_clause
import aarondb/engine/temporal_clause.{
  type ClauseSolver, solve as solve_temporal,
}
import aarondb/engine/virtual
import aarondb/fact
import aarondb/shared/ast
import aarondb/shared/state
import aarondb/storage/internal
import gleam/dict.{type Dict}
import gleam/option.{type Option, None, Some}
import gleam/set

pub fn solve_clause(
  db_state: state.DbState,
  clause: ast.BodyClause,
  ctx: Dict(String, fact.Value),
  rules: List(ast.Rule),
  as_of_tx: Option(Int),
  as_of_valid: Option(Int),
  nested_solve: NestedSolver,
  solve_clause_with_derived: ClauseSolver,
) -> #(
  List(Dict(String, fact.Value)),
  Option(Dict(String, List(internal.StorageChunk))),
) {
  case clause {
    ast.Positive(c) -> {
      let #(res, store) =
        positive.positive_with_state(db_state, c, ctx, as_of_tx, as_of_valid)
      #(res, store)
    }
    ast.Negative(c) -> #(
      positive.negative(db_state, c, ctx, as_of_tx, as_of_valid),
      None,
    )
    ast.Aggregate(var, func, target_p, filter_clauses) -> {
      let target_var = case target_p {
        ast.Var(n) -> n
        _ -> ""
      }
      solve_aggregate(
        ctx,
        var,
        func,
        target_var,
        solver_context.SolverContext(
          db_state: db_state,
          rules: rules,
          derived: set.new(),
          as_of_tx: as_of_tx,
          as_of_valid: as_of_valid,
        ),
        filter_clauses,
        nested_solve,
      )
    }
    ast.Similarity(variable: var, target: target_p, threshold: threshold) -> {
      let vec = vector_input.vector_from_part(target_p, ctx)
      #(
        retrieval.similarity(
          db_state,
          var,
          vec,
          threshold,
          ctx,
          as_of_tx,
          as_of_valid,
        ),
        None,
      )
    }
    ast.SimilarityEntity(variable: var, target: target_p, threshold: threshold) -> {
      let vec = vector_input.vector_from_part(target_p, ctx)
      #(retrieval.similarity_entity(db_state, var, vec, threshold, ctx), None)
    }
    ast.Cognitive(concept, context, threshold, engram_var) -> #(
      cognitive.solve(
        db_state,
        concept,
        context,
        threshold,
        engram_var,
        ctx,
        as_of_tx,
        as_of_valid,
      ),
      None,
    )
    ast.CustomIndex(variable: var, index_name: name, query: q, threshold: t) -> {
      let state_q = case q {
        ast.TextQuery(txt) -> state.TextQuery(txt)
        ast.NumericRange(min, max) -> state.NumericRange(min, max)
        ast.Custom(data) -> state.Custom(data)
      }
      #(
        retrieval.custom_index(
          db_state,
          var,
          name,
          state_q,
          t,
          ctx,
          as_of_tx,
          as_of_valid,
        ),
        None,
      )
    }
    ast.Filter(expr) -> {
      let compiled_pred = predicate.compile(expr)
      case compiled_pred(ctx) {
        True -> #([ctx], None)
        False -> #([], None)
      }
    }
    ast.Bind(var_p, val_p) -> {
      let var_name = case var_p {
        ast.Var(n) -> n
        _ -> ""
      }
      let val = bindings.resolve_part(val_p, ctx) |> option.unwrap(fact.Int(0))
      #([dict.insert(ctx, var_name, val)], None)
    }
    ast.Temporal(type_, time, op, var, entity_p, clauses) -> #(
      solve_temporal(
        db_state,
        type_,
        time,
        op,
        var,
        entity_p,
        clauses,
        ctx,
        solve_clause_with_derived,
      ),
      None,
    )
    ast.ShortestPath(from, to, edge, path_var, cost_var, max_depth) -> #(
      graph_clauses.shortest_path(
        db_state,
        from,
        to,
        edge,
        path_var,
        cost_var,
        max_depth,
        ctx,
      ),
      None,
    )
    ast.PageRank(entity_var, edge, rank_var, damping, iterations) -> #(
      graph_clauses.pagerank(
        db_state,
        entity_var,
        edge,
        rank_var,
        damping,
        iterations,
        ctx,
      ),
      None,
    )
    ast.Virtual(pred, args, outputs) -> #(
      virtual.solve(db_state, pred, args, outputs, ctx),
      None,
    )
    ast.Reachable(from, edge, node_var) -> #(
      graph_clauses.reachable(db_state, from, edge, node_var, ctx),
      None,
    )
    ast.ConnectedComponents(edge, entity_var, component_var) -> #(
      graph_clauses.connected_components(
        db_state,
        edge,
        entity_var,
        component_var,
        ctx,
      ),
      None,
    )
    ast.Neighbors(from, edge, depth, node_var) -> #(
      graph_clauses.neighbors(db_state, from, edge, depth, node_var, ctx),
      None,
    )
    ast.CycleDetect(edge, cycle_var) -> #(
      graph_clauses.cycle_detect(db_state, edge, cycle_var, ctx),
      None,
    )
    ast.BetweennessCentrality(edge, entity_var, score_var) -> #(
      graph_clauses.betweenness(db_state, edge, entity_var, score_var, ctx),
      None,
    )
    ast.TopologicalSort(edge, entity_var, order_var) -> #(
      graph_clauses.topological_sort(db_state, edge, entity_var, order_var, ctx),
      None,
    )
    ast.StronglyConnectedComponents(edge, entity_var, component_var) -> #(
      graph_clauses.strongly_connected(
        db_state,
        edge,
        entity_var,
        component_var,
        ctx,
      ),
      None,
    )
    ast.StartsWith(var, prefix) -> #(
      string_clause.starts_with(db_state, var, prefix, ctx),
      None,
    )
    ast.Pull(var, entity_p, pattern) -> {
      case bindings.resolve_part(entity_p, ctx) {
        Some(fact.Ref(eid)) -> {
          let res = entity.pull(db_state, eid, pattern)
          #([dict.insert(ctx, var, entity.pull_result_to_value(res))], None)
        }
        Some(fact.Int(eid_int)) -> {
          let res = entity.pull(db_state, fact.EntityId(eid_int), pattern)
          #([dict.insert(ctx, var, entity.pull_result_to_value(res))], None)
        }
        _ -> #([], None)
      }
    }
    _ -> #([ctx], None)
  }
}
