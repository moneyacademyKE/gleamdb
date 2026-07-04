import aarondb/fact
import aarondb/shared/state
import aarondb/storage
import aarondb/transactor/apply
import gleam/erlang/process
import gleam/list
import gleam/option.{type Option}
import gleam/otp/actor

pub fn do_handle_transact(
  state: state.DbState,
  facts: List(fact.Fact),
  valid_time: Option(Int),
  op: fact.Operation,
  reply: process.Subject(Result(state.DbState, String)),
  compute_next_state: fn(
    state.DbState,
    List(fact.Fact),
    Option(Int),
    fact.Operation,
  ) -> Result(#(state.DbState, List(fact.Datom)), String),
) -> actor.Next(state.DbState, msg) {
  case compute_next_state(state, facts, valid_time, op) {
    Ok(#(final_state, datoms)) -> {
      let _ = storage.insert(final_state.adapter, datoms)
      let changed_attrs =
        list.map(datoms, fn(d) { d.attribute }) |> list.unique()
      process.send(
        state.reactive_actor,
        state.Notify(changed_attrs, final_state),
      )
      list.each(state.subscribers, fn(sub) { process.send(sub, datoms) })
      process.send(reply, Ok(final_state))
      actor.continue(final_state)
    }
    Error(e) -> {
      process.send(reply, Error(e))
      actor.continue(state)
    }
  }
}

pub fn recover_state(state: state.DbState) -> state.DbState {
  case storage.read_all(state.adapter) {
    Ok(datoms) -> {
      list.fold(datoms, state, fn(acc, d) {
        let #(s, _, _) = apply.apply_datom(acc, d, d.tx_index)
        s
      })
    }
    Error(_) -> state
  }
}
