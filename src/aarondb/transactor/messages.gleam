import aarondb/fact
import aarondb/shared/ast
import aarondb/shared/state as shared_state
import aarondb/storage
import gleam/dict
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/actor
import gleam/string

pub fn log_query(
  db_state: shared_state.DbState,
  ctx: shared_state.QueryContext,
  reply: process.Subject(Nil),
) -> actor.Next(shared_state.DbState, msg) {
  let history = list.append(db_state.query_history, [ctx])
  let trimmed = case list.length(history) > 100 {
    True -> list.drop(history, list.length(history) - 100)
    False -> history
  }
  process.send(reply, Nil)
  actor.continue(shared_state.DbState(..db_state, query_history: trimmed))
}

pub fn set_schema(
  db_state: shared_state.DbState,
  attr: String,
  config: fact.AttributeConfig,
  error: option.Option(String),
  reply_to: process.Subject(Result(Nil, String)),
) -> actor.Next(shared_state.DbState, msg) {
  case error {
    Some(e) -> {
      process.send(reply_to, Error(e))
      actor.continue(db_state)
    }
    None -> {
      let new_schema = dict.insert(db_state.schema, attr, config)
      process.send(reply_to, Ok(Nil))
      actor.continue(shared_state.DbState(..db_state, schema: new_schema))
    }
  }
}

pub fn register_function(
  db_state: shared_state.DbState,
  name: String,
  func: fact.DbFunction(shared_state.DbState),
  reply_to: process.Subject(Nil),
) -> actor.Next(shared_state.DbState, msg) {
  let new_funcs = dict.insert(db_state.functions, name, func)
  process.send(reply_to, Nil)
  actor.continue(shared_state.DbState(..db_state, functions: new_funcs))
}

pub fn register_predicate(
  db_state: shared_state.DbState,
  name: String,
  pred: fn(fact.Value) -> Bool,
  reply_to: process.Subject(Nil),
) -> actor.Next(shared_state.DbState, msg) {
  let new_preds = dict.insert(db_state.predicates, name, pred)
  process.send(reply_to, Nil)
  actor.continue(shared_state.DbState(..db_state, predicates: new_preds))
}

pub fn register_composite(
  db_state: shared_state.DbState,
  attrs: List(String),
  has_violations: Bool,
  reply_to: process.Subject(Result(Nil, String)),
) -> actor.Next(shared_state.DbState, msg) {
  case has_violations {
    True -> {
      process.send(
        reply_to,
        Error(
          "Existing data violates new composite: "
          <> string.inspect(list.sort(attrs, string.compare)),
        ),
      )
      actor.continue(db_state)
    }
    False -> {
      let new_composites = [attrs, ..db_state.composites]
      process.send(reply_to, Ok(Nil))
      actor.continue(
        shared_state.DbState(..db_state, composites: new_composites),
      )
    }
  }
}

pub fn store_rule(
  db_state: shared_state.DbState,
  rule: ast.Rule,
  reply_to: process.Subject(Result(Nil, String)),
  compute_next_state: fn(
    shared_state.DbState,
    List(fact.Fact),
    option.Option(Int),
    fact.Operation,
  ) -> Result(#(shared_state.DbState, List(fact.Datom)), String),
) -> actor.Next(shared_state.DbState, msg) {
  let new_rules = [rule, ..db_state.stored_rules]
  let rule_fact = #(
    fact.Uid(fact.EntityId(int.random(1_000_000_000))),
    "_rule/content",
    fact.Str(string.inspect(rule)),
  )

  case compute_next_state(db_state, [rule_fact], None, fact.Assert) {
    Ok(#(final_state, datoms)) -> {
      let _ = storage.insert(final_state.adapter, datoms)
      let final_state_with_rules =
        shared_state.DbState(..final_state, stored_rules: new_rules)
      process.send(reply_to, Ok(Nil))
      actor.continue(final_state_with_rules)
    }
    Error(e) -> {
      process.send(reply_to, Error(e))
      actor.continue(db_state)
    }
  }
}

pub fn subscribe(
  db_state: shared_state.DbState,
  reply_to: process.Subject(List(fact.Datom)),
) -> actor.Next(shared_state.DbState, msg) {
  let new_subscribers = [reply_to, ..db_state.subscribers]
  actor.continue(shared_state.DbState(..db_state, subscribers: new_subscribers))
}

pub fn set_config(
  db_state: shared_state.DbState,
  config: shared_state.Config,
  reply_to: process.Subject(Nil),
) -> actor.Next(shared_state.DbState, msg) {
  let new_state = shared_state.DbState(..db_state, config: config)
  process.send(reply_to, Nil)
  actor.continue(new_state)
}
