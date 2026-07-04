import aarondb/engine/predicate
import aarondb/fact
import aarondb/shared/ast
import aarondb/storage/internal
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result

pub type ExecutionResult {
  ExecutionResult(
    rows: List(Dict(String, fact.Value)),
    store: Option(Dict(String, List(internal.StorageChunk))),
  )
}

pub type ClauseSolver =
  fn(
    ast.BodyClause,
    Dict(String, fact.Value),
    Option(Dict(String, List(internal.StorageChunk))),
  ) ->
    #(
      List(Dict(String, fact.Value)),
      Option(Dict(String, List(internal.StorageChunk))),
    )

pub fn execute(
  clauses: List(ast.BodyClause),
  initial_contexts: List(Dict(String, fact.Value)),
  initial_store: Option(Dict(String, List(internal.StorageChunk))),
  solve: ClauseSolver,
) -> ExecutionResult {
  let #(rows, store) =
    list.fold(clauses, #(initial_contexts, initial_store), fn(acc, clause) {
      let #(contexts, current_store) = acc
      case clause {
        ast.LimitClause(n) -> #(list.take(contexts, n), current_store)
        ast.OffsetClause(n) -> #(list.drop(contexts, n), current_store)
        ast.OrderByClause(var, dir) -> #(
          order_by_clause(contexts, var, dir),
          current_store,
        )
        ast.GroupBy(_) -> #(contexts, current_store)
        ast.Filter(expr) -> {
          let compiled_pred = predicate.compile(expr)
          #(
            list.filter(contexts, fn(ctx) { compiled_pred(ctx) }),
            current_store,
          )
        }
        _ -> solve_all_contexts(contexts, current_store, clause, solve)
      }
    })

  ExecutionResult(rows: rows, store: store)
}

pub fn merge_stores(
  s1: Option(Dict(String, List(internal.StorageChunk))),
  s2: Option(Dict(String, List(internal.StorageChunk))),
) -> Option(Dict(String, List(internal.StorageChunk))) {
  case s1, s2 {
    Some(m1), Some(m2) -> Some(dict.merge(m1, m2))
    Some(_), None -> s1
    None, Some(_) -> s2
    None, None -> None
  }
}

fn solve_all_contexts(
  contexts: List(Dict(String, fact.Value)),
  current_store: Option(Dict(String, List(internal.StorageChunk))),
  clause: ast.BodyClause,
  solve: ClauseSolver,
) -> #(
  List(Dict(String, fact.Value)),
  Option(Dict(String, List(internal.StorageChunk))),
) {
  list.fold(contexts, #([], current_store), fn(acc, ctx) {
    let #(acc_ctxs, acc_store) = acc
    let #(new_ctxs, clause_store) = solve(clause, ctx, acc_store)
    #(list.append(acc_ctxs, new_ctxs), merge_stores(acc_store, clause_store))
  })
}

fn order_by_clause(
  contexts: List(Dict(String, fact.Value)),
  var: String,
  dir: ast.OrderDirection,
) -> List(Dict(String, fact.Value)) {
  list.sort(contexts, fn(a, b) {
    let val_a = dict.get(a, var) |> result.unwrap(fact.Int(0))
    let val_b = dict.get(b, var) |> result.unwrap(fact.Int(0))
    let ord = fact.compare(val_a, val_b)
    case dir {
      ast.Asc -> ord
      ast.Desc -> reverse_order(ord)
    }
  })
}

fn reverse_order(ord: order.Order) -> order.Order {
  case ord {
    order.Lt -> order.Gt
    order.Gt -> order.Lt
    order.Eq -> order.Eq
  }
}
