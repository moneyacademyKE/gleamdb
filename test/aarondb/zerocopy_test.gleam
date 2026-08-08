import aarondb
import aarondb/fact
import aarondb/index/ets as ets_index
import aarondb/shared/query_types.{PullRawBinary}
import aarondb/shared/state
import gleam/option.{None}
import gleeunit/should

pub fn zerocopy_binary_test() {
  let config =
    state.Config(
      parallel_threshold: 1000,
      batch_size: 100,
      prefetch_enabled: False,
      zero_copy_threshold: 5,
      // Trigger fallback serialization over 5 datoms
    )

  let assert Ok(db) = aarondb.start_named("zerocopy_test_db", None)
  aarondb.set_config(db, config)

  let _ =
    aarondb.set_schema(
      db,
      "sensor/reading",
      fact.AttributeConfig(
        unique: False,
        component: False,
        retention: fact.All,
        cardinality: fact.Many,
        check: None,
        composite_group: None,
        layout: fact.Row,
        tier: fact.Memory,
        eviction: fact.AlwaysInMemory,
      ),
    )

  // Create 10 facts (exceeds zero_copy_threshold of 5)
  // use modern gleam int padding rather than list.range if it's deprecated, but list.range is fine for a quick test if we ignore the warning. Wait, I will use custom loop.
  let facts = aarondb_create_facts(10, [])

  let assert Ok(_) = aarondb.transact(db, facts)

  // Pull all from Entity 100. Should return PullRawBinary!
  let res = aarondb.pull(db, fact.Uid(fact.EntityId(100)), aarondb.pull_all())

  case res {
    PullRawBinary(bin) -> {
      let assert Ok(_dyn) = ets_index.deserialize_term(bin)
      Nil
    }
    _ -> should.fail()
    // Should not follow standard PullMap path when threshold exceeded
  }
}

pub fn zerocopy_rejects_malformed_binary_test() {
  let malformed = <<255, 255, 255>>
  should.equal(Error(Nil), ets_index.deserialize_term(malformed))
}

fn aarondb_create_facts(n: Int, acc: List(fact.Fact)) -> List(fact.Fact) {
  case n {
    0 -> acc
    _ -> {
      let f = #(fact.uid(100), "sensor/reading", fact.Int(n))
      aarondb_create_facts(n - 1, [f, ..acc])
    }
  }
}
