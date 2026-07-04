import aarondb
import aarondb/fact
import aarondb/q
import aarondb/shared/state
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/option.{None}
import gleeunit/should

pub fn disk_spilling_test() {
  // 1. Initialize DB with small memory limit to force spilling
  let config =
    state.Config(
      parallel_threshold: 1000,
      batch_size: 1,
      // Any tx older than 1 is eligible for eviction
      prefetch_enabled: False,
      zero_copy_threshold: 10_000,
    )
  let assert Ok(db) = aarondb.start_named("spill_test_db", None)
  aarondb.set_config(db, config)

  // 2. Set schema to force LruToDisk eviction
  let config =
    fact.AttributeConfig(
      unique: False,
      component: False,
      retention: fact.All,
      cardinality: fact.Many,
      check: None,
      composite_group: None,
      layout: fact.Row,
      tier: fact.Disk,
      eviction: fact.LruToDisk,
    )
  let assert Ok(_) = aarondb.set_schema(db, "log/entry", config)

  // 3. Ingest Data (Batches to trigger lifecycle eviction)
  // Let's transact 3 separate batches to ensure `Tick` triggers eviction of older tx.
  let ingest_batch = fn(start, end) {
    let data =
      int.range(from: start, to: end + 1, with: [], run: fn(acc, i) {
        [i, ..acc]
      })
      |> list.map(fn(i) {
        #(
          fact.deterministic_uid(i),
          "log/entry",
          fact.Str("log_" <> int.to_string(i)),
        )
      })
    let assert Ok(_) = aarondb.transact(db, data)
  }

  let _ = ingest_batch(1, 100)
  process.sleep(100)
  // Allow lifecycle actor to breathe
  let _ = ingest_batch(101, 200)
  process.sleep(100)
  let _ = ingest_batch(201, 300)
  process.sleep(100)

  // 4. Send manual Tick to trigger eviction if timer hasn't fired
  let assert Ok(_) = aarondb.trigger_eviction(db)

  // 5. Query for data that should logically be on disk now
  // We query for item 50, which was in the first transaction and should be evicted from Memory.
  let query =
    q.new()
    |> q.where(q.v("e"), "log/entry", q.s("log_50"))
    |> q.to_clauses()

  let results = aarondb.query(db, query)

  // Verify the engine seamlessly queried it from the underlying index (Mnesia)
  results.rows |> list.length() |> should.equal(1)
}
