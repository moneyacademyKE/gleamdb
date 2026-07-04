import aarondb/engine/solver/triple
import aarondb/engine/solver_context
import aarondb/fact
import aarondb/shared/ast
import aarondb/shared/state
import aarondb/storage/internal
import gleam/dict.{type Dict}
import gleam/option.{type Option, None}
import gleam/set.{type Set}

pub type ClauseSolver =
  fn(
    state.DbState,
    ast.BodyClause,
    Dict(String, fact.Value),
    List(ast.Rule),
    Option(Int),
    Option(Int),
  ) ->
    #(
      List(Dict(String, fact.Value)),
      Option(Dict(String, List(internal.StorageChunk))),
    )

pub fn solve_with_context(
  solver: solver_context.SolverContext,
  clause: ast.BodyClause,
  ctx: Dict(String, fact.Value),
  solve_clause: ClauseSolver,
) -> #(
  List(Dict(String, fact.Value)),
  Option(Dict(String, List(internal.StorageChunk))),
) {
  solve_clause_with_derived(
    solver.db_state,
    clause,
    ctx,
    solver.derived,
    solver.as_of_tx,
    solver.as_of_valid,
    solve_clause,
  )
}

pub fn solve_clause_with_derived(
  db_state: state.DbState,
  clause: ast.BodyClause,
  ctx: Dict(String, fact.Value),
  all_derived: Set(fact.Datom),
  as_of_tx: Option(Int),
  as_of_valid: Option(Int),
  solve_clause: ClauseSolver,
) -> #(
  List(Dict(String, fact.Value)),
  Option(Dict(String, List(internal.StorageChunk))),
) {
  case clause {
    ast.Positive(trip) -> #(
      triple.solve(db_state, trip, ctx, all_derived, as_of_tx, as_of_valid),
      None,
    )
    ast.Negative(trip) -> {
      case
        triple.solve(db_state, trip, ctx, all_derived, as_of_tx, as_of_valid)
      {
        [] -> #([ctx], None)
        _ -> #([], None)
      }
    }
    _ ->
      solve_clause(
        db_state,
        clause,
        ctx,
        db_state.stored_rules,
        as_of_tx,
        as_of_valid,
      )
  }
}
