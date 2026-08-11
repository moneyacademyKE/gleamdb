import aarondb
import aarondb/fact
import aarondb/index
import aarondb/shared/ast as types
import aarondb/shared/state
import gleam/dict
import gleam/list
import gleam/option
import gleeunit/should

pub fn transaction_function_inc_test() {
  let db = aarondb.new()

  // 1. Define 'increment' function
  let inc = fn(state: state.DbState, _tx: Int, _vt: Int, args: List(fact.Value)) {
    case args {
      [fact.Ref(eid), fact.Str(attr)] -> {
        let existing =
          index.get_datoms_by_entity_attr(state.eavt, eid, attr)
          |> list.first()
        let current_val = case existing {
          Ok(d) -> {
            case d.value {
              fact.Int(i) -> i
              _ -> 0
            }
          }
          _ -> 0
        }
        [#(fact.Uid(eid), attr, fact.Int(current_val + 1))]
      }
      _ -> []
    }
  }

  // 2. Register it
  aarondb.register_function(db, "inc", inc)

  // 3. Use it to increment counter
  let eid = fact.EntityId(101)
  let assert Ok(_) =
    aarondb.transact(db, [
      #(
        fact.Lookup(#("db/fn", fact.Str("inc"))),
        "",
        fact.List([fact.Ref(eid), fact.Str("user/counter")]),
      ),
    ])

  // 4. Verify result
  let assert Ok(fact.Int(1)) =
    aarondb.get_one(db, fact.Uid(eid), "user/counter")

  // 5. Increment again
  let assert Ok(_) =
    aarondb.transact(db, [
      #(
        fact.Lookup(#("db/fn", fact.Str("inc"))),
        "",
        fact.List([fact.Ref(eid), fact.Str("user/counter")]),
      ),
    ])

  let assert Ok(fact.Int(2)) =
    aarondb.get_one(db, fact.Uid(eid), "user/counter")
}

pub fn transaction_function_temporal_test() {
  let db = aarondb.new()

  // Define a function that asserts a fact ONLY if queried at a specific valid time
  let temporal_fn = fn(
    _state: state.DbState,
    _tx: Int,
    vt: Int,
    _args: List(fact.Value),
  ) {
    [#(fact.uid(1), "debug/valid-time", fact.Int(vt))]
  }

  aarondb.register_function(db, "log_vt", temporal_fn)

  // Transact at a specific valid time
  let vt_target = 999
  let assert Ok(_) =
    aarondb.transact_at(
      db,
      [#(fact.Lookup(#("db/fn", fact.Str("log_vt"))), "", fact.List([]))],
      vt_target,
    )

  // Verify that the fact was recorded with the correct valid time
  let _state = aarondb.get_state(db)
  let results =
    aarondb.as_of_valid(db, vt_target, [
      aarondb.p(#(
        types.Val(fact.Ref(fact.EntityId(1))),
        "debug/valid-time",
        types.Var("v"),
      )),
    ])

  results.rows |> list.first() |> should.be_ok()
  let binding =
    results.rows
    |> list.first()
    |> option.from_result()
    |> option.unwrap(dict.new())
  dict.get(binding, "v") |> should.equal(Ok(fact.Int(vt_target)))
}
