import aarondb
import aarondb/fact
import aarondb/shared/ast
import gleam/dict
import gleam/int
import gleam/list
import gleeunit/should

pub fn cognitive_relevance_lifecycle_test() {
  let db = aarondb.new()
  let engram = fact.Uid(fact.EntityId(801))
  let assert Ok(_) =
    aarondb.transact(db, [
      #(engram, "engram/concept", fact.Str("release")),
      #(engram, "engram/context", fact.Str("release")),
      #(engram, "engram/relevance", fact.Float(0.2)),
      #(engram, "engram/relevance", fact.Float(0.9)),
    ])

  should.equal(cognitive_ids(db, 0.5), [801])

  let assert Ok(_) =
    aarondb.retract(db, [
      #(engram, "engram/relevance", fact.Float(0.9)),
    ])
  should.equal(cognitive_ids(db, 0.5), [])
}

pub fn cognitive_default_and_numeric_contract_test() {
  let db = aarondb.new()
  let defaulted = fact.Uid(fact.EntityId(802))
  let numeric = fact.Uid(fact.EntityId(803))
  let invalid = fact.Uid(fact.EntityId(804))
  let assert Ok(_) =
    aarondb.transact(db, [
      #(defaulted, "engram/concept", fact.Str("local")),
      #(defaulted, "engram/context", fact.Str("local")),
      #(numeric, "engram/concept", fact.Str("local")),
      #(numeric, "engram/context", fact.Str("local")),
      #(numeric, "engram/relevance", fact.Int(1)),
      #(invalid, "engram/concept", fact.Str("local")),
      #(invalid, "engram/context", fact.Str("local")),
      #(invalid, "engram/relevance", fact.Str("high")),
    ])

  should.equal(cognitive_ids_for(db, "local", 1.0), [802, 803])
}

fn cognitive_ids(db: aarondb.Db, threshold: Float) -> List(Int) {
  cognitive_ids_for(db, "release", threshold)
}

fn cognitive_ids_for(
  db: aarondb.Db,
  context: String,
  threshold: Float,
) -> List(Int) {
  let result =
    aarondb.query(db, [
      ast.Cognitive(
        ast.Val(fact.Str(context)),
        ast.Val(fact.Str(context)),
        threshold,
        "engram",
      ),
    ])

  result.rows
  |> list.filter_map(fn(row) {
    case dict.get(row, "engram") {
      Ok(fact.Ref(fact.EntityId(id))) -> Ok(id)
      _ -> Error(Nil)
    }
  })
  |> list.sort(int.compare)
}
