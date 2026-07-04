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

pub fn build_collects_multiple_aggregates_test() {
  let query =
    ast.Query(
      find: [],
      where: [
        ast.Aggregate("total", ast.Sum, ast.Var("amount"), []),
        ast.Aggregate("count", ast.Count, ast.Var("eid"), []),
      ],
      order_by: None,
      limit: None,
      offset: None,
    )

  let plan = planner.build(query)

  dict.size(plan.aggregates) |> should.equal(2)
}

pub fn build_no_aggregates_test() {
  let query =
    ast.Query(
      find: [],
      where: [ast.Positive(#(ast.Var("e"), "name", ast.Var("n")))],
      order_by: None,
      limit: None,
      offset: None,
    )

  let plan = planner.build(query)

  dict.size(plan.aggregates) |> should.equal(0)
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

pub fn order_rows_asc_test() {
  let rows = [
    dict.from_list([#("score", fact.Int(3))]),
    dict.from_list([#("score", fact.Int(1))]),
    dict.from_list([#("score", fact.Int(2))]),
  ]

  let ordered = planner.order_rows(rows, Some(ast.OrderBy("score", ast.Asc)))

  list_scores(ordered) |> should.equal([1, 2, 3])
}

pub fn order_rows_none_test() {
  let rows = [
    dict.from_list([#("score", fact.Int(3))]),
    dict.from_list([#("score", fact.Int(1))]),
  ]

  let ordered = planner.order_rows(rows, None)

  list.length(ordered) |> should.equal(2)
}

pub fn page_rows_offset_only_test() {
  let rows = [
    dict.from_list([#("id", fact.Int(1))]),
    dict.from_list([#("id", fact.Int(2))]),
    dict.from_list([#("id", fact.Int(3))]),
  ]

  let paged = planner.page_rows(rows, Some(1), None)

  list_ids(paged) |> should.equal([2, 3])
}

pub fn page_rows_limit_only_test() {
  let rows = [
    dict.from_list([#("id", fact.Int(1))]),
    dict.from_list([#("id", fact.Int(2))]),
    dict.from_list([#("id", fact.Int(3))]),
  ]

  let paged = planner.page_rows(rows, None, Some(2))

  list_ids(paged) |> should.equal([1, 2])
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

pub fn page_rows_no_pagination_test() {
  let rows = [
    dict.from_list([#("id", fact.Int(1))]),
    dict.from_list([#("id", fact.Int(2))]),
  ]

  let paged = planner.page_rows(rows, None, None)

  list_ids(paged) |> should.equal([1, 2])
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
