import aarondb
import aarondb/fact.{Int, Str}
import gleam/list
import gleeunit/should

pub fn diff_test() {
  let db_actor = aarondb.new()

  let assert Ok(state1) =
    aarondb.transact(db_actor, [
      #(fact.Uid(fact.EntityId(1)), "name", Str("Alice")),
      #(fact.Uid(fact.EntityId(1)), "age", Int(30)),
    ])
  let tx1 = state1.latest_tx

  let assert Ok(state2) =
    aarondb.transact(db_actor, [
      #(fact.Uid(fact.EntityId(2)), "name", Str("Bob")),
      #(fact.Uid(fact.EntityId(2)), "age", Int(25)),
    ])
  let tx2 = state2.latest_tx

  let assert Ok(state3) =
    aarondb.transact(db_actor, [
      #(fact.Uid(fact.EntityId(1)), "age", Int(31)),
    ])
  let tx3 = state3.latest_tx

  let diff_total = aarondb.diff(db_actor, tx1, tx3)
  should.equal(list.length(diff_total), 3)

  let diff_2_3 = aarondb.diff(db_actor, tx2, tx3)
  should.equal(list.length(diff_2_3), 1)

  let assert [d] = diff_2_3
  should.equal(d.value, Int(31))
  should.equal(d.tx, tx3)
}

pub fn bounded_diff_has_typed_range_and_budget_errors_test() {
  let db = aarondb.new()
  let entity = fact.Uid(fact.EntityId(10))
  let assert Ok(state1) =
    aarondb.transact(db, [#(entity, "event/name", Str("first"))])
  let assert Ok(state2) =
    aarondb.transact(db, [#(entity, "event/name", Str("second"))])

  should.equal(aarondb.diff_scan_limits(0), Error(aarondb.InvalidDiffScanLimit))
  let assert Ok(limits) = aarondb.diff_scan_limits(1)
  should.equal(
    aarondb.diff_bounded(db, state1.latest_tx, state2.latest_tx, limits),
    Error(aarondb.DiffScanBudgetExceeded),
  )

  let assert Ok(generous_limits) = aarondb.diff_scan_limits(10)
  should.equal(
    aarondb.diff_bounded(
      db,
      state2.latest_tx,
      state1.latest_tx,
      generous_limits,
    ),
    Error(aarondb.InvalidDiffRange),
  )
  should.equal(
    aarondb.diff_bounded(
      db,
      state1.latest_tx,
      state1.latest_tx,
      generous_limits,
    ),
    Error(aarondb.InvalidDiffRange),
  )
}

pub fn bounded_diff_orders_assertions_retractions_and_handles_empty_ranges_test() {
  let db = aarondb.new()
  let entity = fact.Uid(fact.EntityId(11))
  let fact_to_change = #(entity, "note/text", Str("before"))
  let assert Ok(state1) = aarondb.transact(db, [fact_to_change])
  let assert Ok(state2) = aarondb.retract(db, [fact_to_change])
  let assert Ok(state3) =
    aarondb.transact(db, [#(entity, "note/text", Str("after"))])
  let assert Ok(limits) = aarondb.diff_scan_limits(10)

  let assert Ok(changes) =
    aarondb.diff_bounded(db, state1.latest_tx, state3.latest_tx, limits)
  should.equal(list.length(changes), 2)
  let assert [retraction, assertion] = changes
  should.equal(retraction.operation, fact.Retract)
  should.equal(retraction.tx, state2.latest_tx)
  should.equal(assertion.operation, fact.Assert)
  should.equal(assertion.tx, state3.latest_tx)
  let assert Ok(empty) =
    aarondb.diff_bounded(db, state3.latest_tx, state3.latest_tx + 1, limits)
  should.equal(empty, [])
}

pub fn bounded_diff_partitions_history_without_duplicates_or_gaps_test() {
  let db = aarondb.new()
  let entity = fact.Uid(fact.EntityId(12))
  let assert Ok(state_one) =
    aarondb.transact(db, [#(entity, "event/value", Str("one"))])
  let assert Ok(state_two) =
    aarondb.transact(db, [#(entity, "event/value", Str("two"))])
  let assert Ok(state_three) =
    aarondb.retract(db, [#(entity, "event/value", Str("two"))])
  let assert Ok(state_four) =
    aarondb.transact(db, [#(entity, "event/value", Str("three"))])
  let assert Ok(limits) = aarondb.diff_scan_limits(20)

  let assert Ok(whole) =
    aarondb.diff_bounded(db, state_one.latest_tx, state_four.latest_tx, limits)
  let assert Ok(first_half) =
    aarondb.diff_bounded(db, state_one.latest_tx, state_two.latest_tx, limits)
  let assert Ok(second_half) =
    aarondb.diff_bounded(db, state_two.latest_tx, state_four.latest_tx, limits)

  should.equal(whole, list.append(first_half, second_half))
  should.equal(list.length(whole), 3)
  let assert [first_change, second_change, third_change] = whole
  should.equal(first_change.tx, state_two.latest_tx)
  should.equal(second_change.tx, state_three.latest_tx)
  should.equal(third_change.tx, state_four.latest_tx)
}
