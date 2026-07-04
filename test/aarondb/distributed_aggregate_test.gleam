import aarondb
import aarondb/fact
import aarondb/sharded
import aarondb/shared/ast as types
import gleam/dict
import gleam/erlang/process
import gleam/list
import gleam/option.{None}
import gleeunit/should

pub fn distributed_sum_test() {
  let assert Ok(sdb) = sharded.start_local_sharded("sum_cluster", 2, None)

  // Transact data into shards
  let _ =
    sharded.transact(sdb, [#(fact.Uid(fact.EntityId(1)), "val", fact.Int(10))])
  let _ =
    sharded.transact(sdb, [#(fact.Uid(fact.EntityId(2)), "val", fact.Int(20))])
  let _ =
    sharded.transact(sdb, [#(fact.Uid(fact.EntityId(3)), "val", fact.Int(30))])
  let _ =
    sharded.transact(sdb, [#(fact.Uid(fact.EntityId(4)), "val", fact.Int(40))])

  // Query global sum
  let q =
    types.Query(
      find: ["total"],
      where: [
        types.Aggregate("total", types.Sum, types.Var("v"), [
          types.Positive(#(types.Var("e"), "val", types.Var("v"))),
        ]),
      ],
      order_by: None,
      limit: None,
      offset: None,
    )

  let res = sharded.query(sdb, q)

  // Coordinate reduction should merge results from shards
  list.length(res.rows) |> should.equal(1)

  let assert Ok(row) = list.first(res.rows)
  dict.get(row, "total") |> should.equal(Ok(fact.Int(100)))

  sharded.stop(sdb)
}

pub fn distributed_count_test() {
  let assert Ok(sdb) = sharded.start_local_sharded("count_cluster", 2, None)

  let _ =
    sharded.transact(sdb, [#(fact.Uid(fact.EntityId(1)), "val", fact.Int(10))])
  let _ =
    sharded.transact(sdb, [#(fact.Uid(fact.EntityId(2)), "val", fact.Int(20))])
  let _ =
    sharded.transact(sdb, [#(fact.Uid(fact.EntityId(3)), "val", fact.Int(30))])

  // Query global count
  let q =
    types.Query(
      find: ["cnt"],
      where: [
        types.Aggregate("cnt", types.Count, types.Var("e"), [
          types.Positive(#(types.Var("e"), "val", types.Var("_"))),
        ]),
      ],
      order_by: None,
      limit: None,
      offset: None,
    )

  let res = sharded.query(sdb, q)

  list.length(res.rows) |> should.equal(1)
  let assert Ok(row) = list.first(res.rows)
  dict.get(row, "cnt") |> should.equal(Ok(fact.Int(3)))

  sharded.stop(sdb)
}

pub fn distributed_wal_test() {
  let db = aarondb.new()
  let self = process.new_subject()

  aarondb.subscribe_wal(db, self)

  let _ =
    aarondb.transact(db, [
      #(fact.Uid(fact.EntityId(1)), "test/wal", fact.Int(42)),
    ])

  let assert Ok(datoms) = process.receive(self, 5000)
  list.is_empty(datoms) |> should.be_false()
  let assert Ok(d) = list.first(datoms)
  d.attribute |> should.equal("test/wal")
  d.value |> should.equal(fact.Int(42))
}
