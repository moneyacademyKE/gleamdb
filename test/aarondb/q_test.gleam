import aarondb/fact
import aarondb/q
import aarondb/shared/ast
import gleam/option.{Some}
import gleeunit/should

pub fn query_builder_test() {
  let builder =
    q.select(["x", "y"])
    |> q.where(q.v("e"), "attr", q.v("x"))
    |> q.negate(q.v("e"), "missing", q.s("val"))
    |> q.limit(10)
    |> q.offset(5)

  let query = q.to_query(builder)

  should.equal(query.find, ["x", "y"])
  should.equal(query.limit, Some(10))
  should.equal(query.offset, Some(5))

  let assert [
    ast.Positive(#(ast.Var("e"), "attr", ast.Var("x"))),
    ast.Negative(#(ast.Var("e"), "missing", ast.Val(fact.Str("val")))),
  ] = query.where
}

pub fn similar_emits_similarity_clause_test() {
  let query =
    q.select(["x"])
    |> q.similar("x", [0.9, 0.1, 0.0], 0.85)
    |> q.to_query

  should.equal(query.where, [
    ast.Similarity("x", ast.Val(fact.Vec([0.9, 0.1, 0.0])), 0.85),
  ])
}

pub fn temporal_at_emits_exact_tx_clause_test() {
  let query =
    q.select(["basis"])
    |> q.temporal_at("basis", q.i(7), 42)
    |> q.to_query

  should.equal(query.where, [
    ast.Temporal(ast.Tx, 42, ast.At, "basis", ast.Val(fact.Int(7)), []),
  ])
}

pub fn valid_temporal_at_emits_exact_valid_clause_test() {
  let query =
    q.select(["basis"])
    |> q.valid_temporal_at("basis", q.i(7), 2042)
    |> q.to_query

  should.equal(query.where, [
    ast.Temporal(ast.Valid, 2042, ast.At, "basis", ast.Val(fact.Int(7)), []),
  ])
}
