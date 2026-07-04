import aarondb/engine/executor
import aarondb/fact
import aarondb/shared/ast
import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import gleeunit/should

pub fn execute_applies_filter_without_solver_test() {
  let contexts = [
    dict.from_list([#("age", fact.Int(20))]),
    dict.from_list([#("age", fact.Int(10))]),
  ]
  let clauses = [ast.Filter(ast.Gt(ast.Var("age"), ast.Val(fact.Int(18))))]

  let result = executor.execute(clauses, contexts, None, fake_solver)

  list_ages(result.rows) |> should.equal([20])
}

pub fn execute_uses_solver_for_generic_clause_test() {
  let contexts = [dict.new()]
  let clauses = [
    ast.Positive(#(ast.Var("e"), "user/name", ast.Val(fact.Str("Ada")))),
  ]

  let result = executor.execute(clauses, contexts, None, fake_solver)

  dict.get(result.rows |> first_row, "solved")
  |> should.equal(Ok(fact.Bool(True)))
}

pub fn execute_limit_clause_test() {
  let contexts = [
    dict.from_list([#("id", fact.Int(1))]),
    dict.from_list([#("id", fact.Int(2))]),
    dict.from_list([#("id", fact.Int(3))]),
  ]
  let clauses = [ast.LimitClause(2)]

  let result = executor.execute(clauses, contexts, None, fake_solver)

  list.length(result.rows) |> should.equal(2)
}

pub fn execute_offset_clause_test() {
  let contexts = [
    dict.from_list([#("id", fact.Int(1))]),
    dict.from_list([#("id", fact.Int(2))]),
    dict.from_list([#("id", fact.Int(3))]),
  ]
  let clauses = [ast.OffsetClause(1)]

  let result = executor.execute(clauses, contexts, None, fake_solver)

  list_ids(result.rows) |> should.equal([2, 3])
}

pub fn execute_order_by_clause_asc_test() {
  let contexts = [
    dict.from_list([#("v", fact.Int(3))]),
    dict.from_list([#("v", fact.Int(1))]),
    dict.from_list([#("v", fact.Int(2))]),
  ]
  let clauses = [ast.OrderByClause("v", ast.Asc)]

  let result = executor.execute(clauses, contexts, None, fake_solver)

  list_values(result.rows) |> should.equal([1, 2, 3])
}

pub fn execute_group_by_passes_through_test() {
  let contexts = [
    dict.from_list([#("k", fact.Str("a"))]),
    dict.from_list([#("k", fact.Str("b"))]),
  ]
  let clauses = [ast.GroupBy("k")]

  let result = executor.execute(clauses, contexts, None, fake_solver)

  list.length(result.rows) |> should.equal(2)
}

pub fn execute_empty_contexts_test() {
  let clauses = [
    ast.Positive(#(ast.Var("e"), "name", ast.Var("n"))),
  ]

  let result = executor.execute(clauses, [], None, fake_solver)

  list.length(result.rows) |> should.equal(0)
}

pub fn merge_stores_both_none_test() {
  executor.merge_stores(None, None) |> should.equal(None)
}

pub fn merge_stores_first_some_test() {
  let s = Some(dict.from_list([#("a", [])]))
  executor.merge_stores(s, None) |> should.equal(s)
}

pub fn merge_stores_both_some_test() {
  let s1 = dict.from_list([#("a", [])])
  let s2 = dict.from_list([#("b", [])])
  let merged = executor.merge_stores(Some(s1), Some(s2))

  case merged {
    Some(m) -> dict.size(m) |> should.equal(2)
    None -> should.fail()
  }
}

fn fake_solver(_clause, ctx, store) {
  #([dict.insert(ctx, "solved", fact.Bool(True))], store)
}

fn list_ages(rows) {
  list.map(rows, fn(row) {
    let assert Ok(fact.Int(age)) = dict.get(row, "age")
    age
  })
}

fn list_ids(rows) {
  list.map(rows, fn(row) {
    let assert Ok(fact.Int(id)) = dict.get(row, "id")
    id
  })
}

fn list_values(rows) {
  list.map(rows, fn(row) {
    let assert Ok(fact.Int(v)) = dict.get(row, "v")
    v
  })
}

fn first_row(rows) {
  let assert [row, ..] = rows
  row
}
