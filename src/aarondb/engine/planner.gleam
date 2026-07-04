import aarondb/fact
import aarondb/shared/ast
import aarondb/shared/optimizer
import gleam/dict.{type Dict}
import gleam/list
import gleam/option
import gleam/order
import gleam/result

pub type QueryPlan {
  QueryPlan(
    query: ast.Query,
    clauses: List(ast.BodyClause),
    aggregates: Dict(String, ast.AggFunc),
  )
}

pub fn build(query: ast.Query) -> QueryPlan {
  let optimized = optimizer.optimize(query)
  let clauses = optimized.where
  QueryPlan(
    query: optimized,
    clauses: clauses,
    aggregates: collect_aggregates(clauses),
  )
}

pub fn order_rows(
  rows: List(Dict(String, fact.Value)),
  order_by: option.Option(ast.OrderBy),
) -> List(Dict(String, fact.Value)) {
  case order_by {
    option.Some(ast.OrderBy(var, dir)) -> {
      list.sort(rows, fn(a, b) {
        let val_a = dict.get(a, var) |> result.unwrap(fact.Int(0))
        let val_b = dict.get(b, var) |> result.unwrap(fact.Int(0))
        let ord = fact.compare(val_a, val_b)
        case dir {
          ast.Asc -> ord
          ast.Desc -> reverse_order(ord)
        }
      })
    }
    option.None -> rows
  }
}

pub fn page_rows(
  rows: List(Dict(String, fact.Value)),
  offset: option.Option(Int),
  limit: option.Option(Int),
) -> List(Dict(String, fact.Value)) {
  let rows = case offset {
    option.Some(n) -> list.drop(rows, n)
    option.None -> rows
  }
  case limit {
    option.Some(n) -> list.take(rows, n)
    option.None -> rows
  }
}

fn collect_aggregates(
  clauses: List(ast.BodyClause),
) -> Dict(String, ast.AggFunc) {
  list.fold(clauses, dict.new(), fn(acc, clause) {
    case clause {
      ast.Aggregate(var, func, _, _) -> dict.insert(acc, var, func)
      _ -> acc
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
