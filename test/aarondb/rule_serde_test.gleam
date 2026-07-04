import aarondb/rule_serde
import aarondb/shared/ast
import gleeunit/should

pub fn rule_serde_test() {
  let rule =
    ast.Rule(head: #(ast.Var("X"), "grandparent", ast.Var("Y")), body: [
      ast.Positive(#(ast.Var("X"), "parent", ast.Var("Z"))),
      ast.Positive(#(ast.Var("Z"), "parent", ast.Var("Y"))),
    ])

  let serialized = rule_serde.serialize(rule)
  let assert Ok(deserialized) = rule_serde.deserialize(serialized)

  should.equal(rule, deserialized)
}
