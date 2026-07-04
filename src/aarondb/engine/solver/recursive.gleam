import aarondb/engine/solver/stores
import aarondb/engine/solver_context
import aarondb/fact
import aarondb/shared/ast
import aarondb/shared/state
import aarondb/storage/internal
import gleam/dict.{type Dict}
import gleam/erlang/process
import gleam/list
import gleam/option.{type Option}

pub type ClauseSolver =
  fn(
    state.DbState,
    ast.BodyClause,
    Dict(String, fact.Value),
    List(ast.Rule),
    Option(Int),
    Option(Int),
  ) -> #(
    List(Dict(String, fact.Value)),
    Option(Dict(String, List(internal.StorageChunk))),
  )

pub fn solve_clauses(
  solver: solver_context.SolverContext,
  clauses: List(ast.BodyClause),
  contexts: List(Dict(String, fact.Value)),
  initial_store: Option(Dict(String, List(internal.StorageChunk))),
  solve: ClauseSolver,
) -> #(
  List(Dict(String, fact.Value)),
  Option(Dict(String, List(internal.StorageChunk))),
) {
  case clauses {
    [] -> #(contexts, initial_store)
    [first, ..rest] -> {
      let #(next_contexts, next_store) = case
        list.length(contexts) > solver.db_state.config.parallel_threshold
      {
        True -> {
          let subject = process.new_subject()
          process.spawn(fn() {
            let res =
              list.fold(contexts, #([], initial_store), fn(acc, ctx) {
                let #(acc_ctxs, acc_store) = acc
                let #(new_ctxs, clause_store) =
                  solve(
                    solver.db_state,
                    first,
                    ctx,
                    solver.rules,
                    solver.as_of_tx,
                    solver.as_of_valid,
                  )
                #(
                  list.append(acc_ctxs, new_ctxs),
                  stores.merge_optional_stores(acc_store, clause_store),
                )
              })
            process.send(subject, res)
          })
          let assert Ok(res) = process.receive(subject, 60_000)
          res
        }
        False -> {
          list.fold(contexts, #([], initial_store), fn(acc, ctx) {
            let #(acc_ctxs, acc_store) = acc
            let #(new_ctxs, clause_store) =
              solve(
                solver.db_state,
                first,
                ctx,
                solver.rules,
                solver.as_of_tx,
                solver.as_of_valid,
              )
            #(
              list.append(acc_ctxs, new_ctxs),
              stores.merge_optional_stores(acc_store, clause_store),
            )
          })
        }
      }
      solve_clauses(solver, rest, next_contexts, next_store, solve)
    }
  }
}

pub fn nested_solve(
  solver: solver_context.SolverContext,
  clauses: List(ast.BodyClause),
  contexts: List(Dict(String, fact.Value)),
  solve: ClauseSolver,
) -> #(
  List(Dict(String, fact.Value)),
  Option(Dict(String, List(internal.StorageChunk))),
) {
  solve_clauses(solver, clauses, contexts, option.None, solve)
}
