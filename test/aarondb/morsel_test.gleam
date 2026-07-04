import aarondb
import aarondb/fact
import aarondb/q
import gleam/int
import gleam/list
import gleeunit/should

pub fn expected_morsel_test() {
  // 1. Initialize DB
  let db = aarondb.new()

  // 2. Ingest Dataset
  let data =
    int.range(from: 1, to: 251, with: [], run: list.prepend)
    |> list.reverse()
    |> list.flat_map(fn(i) {
      let eid = fact.deterministic_uid(i)
      [#(eid, "item/type", fact.Str("parallel_item"))]
    })
  let assert Ok(_) = aarondb.transact(db, data)

  // 3. Run Query
  let query =
    q.new()
    |> q.where(q.v("e"), "item/type", q.v("parallel_item"))
    |> q.to_clauses()

  let results = aarondb.query(db, query)

  // Verify 250 items were correctly map-reduced across chunks
  results.rows |> list.length() |> should.equal(250)
}
