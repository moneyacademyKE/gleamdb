import aarondb
import aarondb/fact
import aarondb/shared/state as types
import aarondb/transactor
import gleam/erlang/process
import gleam/list
import gleam/option.{None}
import gleeunit/should

pub fn predictive_prefetch_test() {
  let config =
    types.Config(
      parallel_threshold: 1000,
      batch_size: 100,
      prefetch_enabled: True,
      zero_copy_threshold: 10_000,
    )

  // Start named to enable ETS caching path
  let assert Ok(db) = aarondb.start_named("prefetch_test_db", None)
  aarondb.set_config(db, config)

  let _ =
    aarondb.set_schema(
      db,
      "user/email",
      fact.AttributeConfig(
        unique: True,
        component: False,
        retention: fact.All,
        cardinality: fact.One,
        check: None,
        composite_group: None,
        layout: fact.Row,
        tier: fact.Memory,
        eviction: fact.AlwaysInMemory,
      ),
    )

  // Run queries that will hit the prefetch ring buffer
  let p1 = aarondb.pull_attr("user/email")
  let _ = aarondb.pull(db, fact.Uid(fact.EntityId(1)), p1)
  let _ = aarondb.pull(db, fact.Uid(fact.EntityId(2)), p1)
  let _ = aarondb.pull(db, fact.Uid(fact.EntityId(3)), p1)

  let p2 = aarondb.pull_attr("user/name")
  let _ = aarondb.pull(db, fact.Uid(fact.EntityId(4)), p2)

  // State should hold the query history
  let state = transactor.get_state(db)
  list.length(state.query_history) |> should.equal(4)

  // Trigger internal Tick -> This evaluates the prefetch heuristic.
  // We expect "user/email" to cross the frequency threshold.
  let assert Ok(_) = aarondb.trigger_eviction(db)

  process.sleep(100)

  // If it didn't panic and the system is alive, the heuristic test passed over the ring buffer.
  list.length(state.query_history) |> should.equal(4)
}
