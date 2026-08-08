import aarondb/shared/ast.{type Rule}
import gleam/bit_array
import gleam/result

@external(erlang, "erlang", "term_to_binary")
fn term_to_binary(term: a) -> BitArray

@external(erlang, "aarondb_term_ffi", "decode_rule")
fn decode_rule(binary: BitArray) -> Result(Rule, Nil)

pub fn serialize(rule: Rule) -> String {
  let bits = term_to_binary(rule)
  bit_array.base64_encode(bits, False)
}

/// Decodes only serialized `ast.Rule` values, rejecting malformed, unsafe,
/// and wrong-shaped Erlang external terms.
pub fn deserialize(s: String) -> Result(Rule, Nil) {
  use bits <- result.try(bit_array.base64_decode(s))
  decode_rule(bits)
}
