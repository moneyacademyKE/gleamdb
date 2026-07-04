import aarondb
import aarondb/fact.{Int}
import aarondb/shared/ast.{Rule} as types
import gleam/dict
import gleam/list
import gleam/result
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn recursive_ancestor_test() {
  let db = aarondb.new()

  // Facts: 1 parent 2, 2 parent 3 (1 -> 2 -> 3)
  let assert Ok(_) =
    aarondb.transact(db, [
      #(fact.Uid(fact.EntityId(1)), "parent", Int(2)),
      #(fact.Uid(fact.EntityId(2)), "parent", Int(3)),
    ])

  // Rules:
  // 1. ancestor(X, Y) :- parent(X, Y)
  // 2. ancestor(X, Z) :- parent(X, Y), ancestor(Y, Z)
  let rules = [
    Rule(head: #(types.Var("x"), "ancestor", types.Var("y")), body: [
      aarondb.p(#(types.Var("x"), "parent", types.Var("y"))),
    ]),
    Rule(head: #(types.Var("x"), "ancestor", types.Var("z")), body: [
      aarondb.p(#(types.Var("x"), "parent", types.Var("y"))),
      aarondb.p(#(types.Var("y"), "ancestor", types.Var("z"))),
    ]),
  ]

  // Query: Find all ancestors of 1
  let result =
    aarondb.query_with_rules(
      db,
      [aarondb.p(#(types.Val(Int(1)), "ancestor", types.Var("anc")))],
      rules,
    )

  // Should find 2 and 3
  should.equal(list.length(result.rows), 2)
  let expected = [
    dict.from_list([#("anc", Int(2))]),
    dict.from_list([#("anc", Int(3))]),
  ]
  // Ordering might vary
  should.be_true(list.contains(
    expected,
    list.first(result.rows) |> result.unwrap(dict.new()),
  ))
  should.be_true(list.contains(
    expected,
    list.last(result.rows) |> result.unwrap(dict.new()),
  ))
}
