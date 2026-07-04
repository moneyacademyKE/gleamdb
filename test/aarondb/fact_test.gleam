import aarondb/fact
import gleeunit/should

pub fn encode_decode_value_test() {
  let v1 = fact.Int(42)
  let assert Ok(#(res1, _)) = fact.decode_compact(fact.encode_compact(v1))
  should.equal(v1, res1)

  let v2 = fact.Str("hello")
  let assert Ok(#(res2, _)) = fact.decode_compact(fact.encode_compact(v2))
  should.equal(v2, res2)

  let v3 = fact.Bool(True)
  let assert Ok(#(res3, _)) = fact.decode_compact(fact.encode_compact(v3))
  should.equal(v3, res3)

  let v4 = fact.List([fact.Int(1), fact.Int(2)])
  let assert Ok(#(res4, _)) = fact.decode_compact(fact.encode_compact(v4))
  should.equal(v4, res4)

  let v5 = fact.Vec([1.0, 2.0, 3.0])
  let assert Ok(#(res5, _)) = fact.decode_compact(fact.encode_compact(v5))
  should.equal(v5, res5)
}

pub fn encode_decode_datom_test() {
  let d =
    fact.Datom(
      entity: fact.EntityId(1),
      attribute: "name",
      value: fact.Str("Alice"),
      tx: 100,
      tx_index: 0,
      valid_time: 0,
      operation: fact.Assert,
    )
  let assert Ok(#(d2, _)) = fact.decode_datom(fact.encode_datom(d))
  should.equal(d, d2)
}
