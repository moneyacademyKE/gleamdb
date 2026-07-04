import aarondb/engine/executor
import aarondb/fact
import aarondb/shared/ast
import gleam/dict
import gleam/list
import gleam/option.{None}
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
  let clauses = [ast.Positive(#(ast.Var("e"), "user/name", ast.Val(fact.Str("Ada"))))]

  let result = executor.execute(clauses, contexts, None, fake_solver)

  dict.get(result.rows |> first_row, "solved")
  |> should.equal(Ok(fact.Bool(True)))
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

fn first_row(rows) {
  let assert [row, ..] = rows
  row
}
