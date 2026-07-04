import aarondb/engine/planner
import aarondb/fact
import aarondb/shared/ast
import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import gleeunit/should

pub fn build_collects_aggregates_test() {
  let query =
    ast.Query(
      find: [],
      where: [ast.Aggregate("total", ast.Sum, ast.Var("amount"), [])],
      order_by: None,
      limit: None,
      offset: None,
    )

  let plan = planner.build(query)

  dict.get(plan.aggregates, "total")
  |> should.equal(Ok(ast.Sum))
}

pub fn order_rows_desc_test() {
  let rows = [
    dict.from_list([#("score", fact.Int(1))]),
    dict.from_list([#("score", fact.Int(3))]),
    dict.from_list([#("score", fact.Int(2))]),
  ]

  let ordered = planner.order_rows(rows, Some(ast.OrderBy("score", ast.Desc)))

  list_scores(ordered) |> should.equal([3, 2, 1])
}

pub fn page_rows_test() {
  let rows = [
    dict.from_list([#("id", fact.Int(1))]),
    dict.from_list([#("id", fact.Int(2))]),
    dict.from_list([#("id", fact.Int(3))]),
  ]

  let paged = planner.page_rows(rows, Some(1), Some(1))

  list_ids(paged) |> should.equal([2])
}

fn list_scores(rows) {
  list.map(rows, fn(row) {
    let assert Ok(fact.Int(score)) = dict.get(row, "score")
    score
  })
}

fn list_ids(rows) {
  list.map(rows, fn(row) {
    let assert Ok(fact.Int(id)) = dict.get(row, "id")
    id
  })
}
