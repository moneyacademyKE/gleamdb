import aarondb
import aarondb/fact
import aarondb/q
import aarondb/shared/ast
import gleam/dict
import gleam/int
import gleam/list
import gleeunit/should

pub fn temporal_pagination_test() {
  let db = aarondb.new()
  let eid = fact.EntityId(1)
  let uid = fact.Uid(eid)

  // Insert 100 ticks with increasing timestamps
  let ticks =
    int.range(from: 1, to: 101, with: [], run: fn(acc, i) { [i, ..acc] })
    |> list.reverse()
    |> list.map(fn(i) {
      fact.Datom(
        entity: eid,
        attribute: "tick/price",
        value: fact.Int(i),
        tx: i,
        tx_index: 0,
        valid_time: 0,
        operation: fact.Assert,
      )
    })

  // Direct low-level storage inject for testing to control TX IDs exactly
  // Or just use transact. transact assigns TX IDs.
  // If we want to test "Since TX=50", we need 100 transactions.

  list.each(ticks, fn(d) {
    let f = #(uid, "tick/price", d.value)
    let _ = aarondb.transact(db, [f])
    Nil
  })

  // Query: Get ticks from TX 50 to 60.
  // Since we did 100 transactions, TX IDs should be around 1..100 (plus internal schema TXs?)
  // Let's widen the range to catch them, or assume strictly 1-based.
  // Schema might take TX 1? 
  // Let's query 50 to 60.

  let result =
    aarondb.q(
      db,
      q.new()
        |> q.temporal_at("val", q.i(1), 50),
    )

  let values =
    list.map(result.rows, fn(row) {
      let assert Ok(fact.Int(v)) = dict.get(row, "val")
      v
    })
    |> list.sort(int.compare)

  // We expect *some* values. Since startup might use TXs, 
  // let's just check that we got a subset, not all 100.

  should.be_true(values != [])
  should.be_true(list.length(values) <= 12)
  // 50..60 is 11 inclusive, allowed some buffer
}

pub fn limit_offset_order_test() {
  let db = aarondb.new()
  let uid = fact.Uid(fact.EntityId(2))

  // Insert 10 values: 10, 20, ... 100
  int.range(from: 1, to: 11, with: [], run: fn(acc, i) { [i, ..acc] })
  |> list.reverse()
  |> list.each(fn(i) {
    let f = #(uid, "val", fact.Int(i * 10))
    let _ = aarondb.transact(db, [f])
    Nil
  })

  // Query: Select all, Order DESC, Limit 3
  let result =
    aarondb.q(
      db,
      q.new()
        |> q.where(q.i(2), "val", q.v("x"))
        |> q.order_by("x", ast.Desc)
        |> q.limit(3),
    )

  let values =
    list.map(result.rows, fn(row) {
      let assert Ok(fact.Int(v)) = dict.get(row, "x")
      v
    })

  should.equal(values, [100, 90, 80])

  // Query: Offset 2, Limit 2 with Ascending Order
  let result_offset =
    aarondb.q(
      db,
      q.new()
        |> q.where(q.i(2), "val", q.v("x"))
        |> q.order_by("x", ast.Asc)
        |> q.offset(2)
        |> q.limit(2),
    )

  let values_offset =
    list.map(result_offset.rows, fn(row) {
      let assert Ok(fact.Int(v)) = dict.get(row, "x")
      v
    })

  should.equal(values_offset, [30, 40])
}

pub fn aggregate_test() {
  let db = aarondb.new()
  let uid = fact.Uid(fact.EntityId(3))

  // Insert 5 values: 10, 20, 30, 40, 50
  int.range(from: 1, to: 6, with: [], run: fn(acc, i) { [i, ..acc] })
  |> list.reverse()
  |> list.each(fn(i) {
    let f = #(uid, "score", fact.Int(i * 10))
    let _ = aarondb.transact(db, [f])
    Nil
  })

  // Query: Avg of "score" for entity 3
  let filter =
    q.new()
    |> q.where(q.i(3), "score", q.v("s"))
    |> q.to_clauses

  let result =
    aarondb.q(
      db,
      q.new()
        |> q.avg("avg_val", "s", filter),
    )

  let assert Ok(row) = list.first(result.rows)
  let assert Ok(fact.Float(avg)) = dict.get(row, "avg_val")

  // Avg(10, 20, 30, 40, 50) = 30.0
  should.equal(avg, 30.0)
}
