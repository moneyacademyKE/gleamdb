import aarondb/index/ets
import aarondb/rule_serde
import aarondb/shared/ast
import gleam/bit_array
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

pub fn rule_serde_rejects_invalid_base64_test() {
  should.equal(Error(Nil), rule_serde.deserialize("not-base64!"))
}

pub fn rule_serde_rejects_non_rule_term_test() {
  let serialized_int = ets.serialize_term(42) |> bit_array.base64_encode(False)
  should.equal(Error(Nil), rule_serde.deserialize(serialized_int))
}
