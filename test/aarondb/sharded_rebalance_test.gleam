import aarondb/fact.{EntityId, Str, Uid}
import aarondb/sharded
import aarondb/shared/ast as types
import gleam/list
import gleam/option.{None}
import gleeunit/should

pub fn rebalance_is_explicitly_unsupported_test() {
  let assert Ok(db) = sharded.start_local_sharded("test_cluster", 2, None)

  sharded.rebalance(db)
  |> should.equal(Error(
    "shard rebalancing is not supported — no atomic migration protocol",
  ))

  sharded.stop(db)
}

pub fn adding_a_shard_preserves_existing_local_reads_test() {
  let assert Ok(db) = sharded.start_local_sharded("test_cluster", 2, None)

  let facts = [
    #(Uid(EntityId(1)), "user/name", Str("Alice")),
    #(Uid(EntityId(2)), "user/name", Str("Bob")),
    #(Uid(EntityId(3)), "user/name", Str("Charlie")),
  ]
  let assert Ok(_) = sharded.transact(db, facts)
  let assert Ok(db2) = sharded.add_shard(db, None)
  db2.shard_count |> should.equal(3)

  let query =
    types.Query(
      find: ["e", "n"],
      where: [types.Positive(#(types.Var("e"), "user/name", types.Var("n")))],
      order_by: None,
      limit: None,
      offset: None,
    )
  let result = sharded.query(db2, query)
  list.length(result.rows) |> should.equal(3)

  sharded.stop(db2)
}
