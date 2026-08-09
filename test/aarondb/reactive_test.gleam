import aarondb
import aarondb/fact
import aarondb/q
import aarondb/shared/query_types
import gleam/erlang/process
import gleam/io
import gleam/list
import gleam/option.{None}
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn reactive_delta_test() {
  let db = aarondb.new_with_adapter_and_timeout(None, 1000)

  // 1. Setup Data
  let assert Ok(_) =
    aarondb.transact(db, [
      #(fact.Uid(fact.EntityId(1)), "chat/id", fact.Int(100)),
      #(fact.Uid(fact.EntityId(1)), "chat/msg", fact.Str("Hello")),
    ])

  // 2. Subscribe
  let query =
    q.select(["msg"])
    |> q.where(q.v("e"), "chat/id", q.i(100))
    |> q.where(q.v("e"), "chat/msg", q.v("msg"))
    |> q.to_query()

  let subject = process.new_subject()
  aarondb.subscribe(db, query, subject)

  // 3. Assert Initial State
  let assert Ok(msg) = process.receive(subject, 1000)
  case msg {
    query_types.Initial(results) -> {
      should.equal(list.length(results.rows), 1)
    }
    _ -> should.fail()
  }

  // 4. Transact New Item
  let assert Ok(_) =
    aarondb.transact(db, [
      #(fact.Uid(fact.EntityId(2)), "chat/id", fact.Int(100)),
      #(fact.Uid(fact.EntityId(2)), "chat/msg", fact.Str("World")),
    ])

  // 5. Assert Delta (Added)
  let assert Ok(msg2) = process.receive(subject, 1000)
  case msg2 {
    query_types.Delta(added, removed) -> {
      should.equal(list.length(added.rows), 1)
      should.equal(list.length(removed.rows), 0)
      io.println("Received Delta Added")
    }
    _ -> should.fail()
  }

  // 6. Retract Item
  let assert Ok(_) =
    aarondb.retract(db, [
      #(fact.Uid(fact.EntityId(2)), "chat/msg", fact.Str("World")),
    ])

  // 7. Assert Delta (Removed)
  let assert Ok(msg3) = process.receive(subject, 1000)
  case msg3 {
    query_types.Delta(added, removed) -> {
      should.equal(list.length(added.rows), 0)
      should.equal(list.length(removed.rows), 1)
      io.println("Received Delta Removed")
    }
    _ -> should.fail()
  }
}

pub fn unsubscribe_stops_later_deltas_test() {
  let db = aarondb.new_with_adapter_and_timeout(None, 1000)
  let query =
    q.select(["msg"])
    |> q.where(q.v("e"), "chat/id", q.i(100))
    |> q.where(q.v("e"), "chat/msg", q.v("msg"))
    |> q.to_query()
  let subject = process.new_subject()

  aarondb.subscribe(db, query, subject)
  let assert Ok(query_types.Initial(_)) = process.receive(subject, 1000)

  aarondb.unsubscribe(db, subject)
  let assert Ok(_) =
    aarondb.transact(db, [
      #(fact.Uid(fact.EntityId(3)), "chat/id", fact.Int(100)),
      #(fact.Uid(fact.EntityId(3)), "chat/msg", fact.Str("Not delivered")),
    ])

  case process.receive(subject, 100) {
    Ok(_) -> should.fail()
    Error(_) -> Nil
  }
}
