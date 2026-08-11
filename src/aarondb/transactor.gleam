import aarondb/fact
import aarondb/global
import aarondb/index
import aarondb/index/art
import aarondb/index/ets as ets_index
import aarondb/process_extra
import aarondb/reactive
import aarondb/shared/ast
import aarondb/shared/state
import aarondb/storage
import aarondb/storage/mnesia
import aarondb/transactor/domain
import aarondb/transactor/lifecycle
import aarondb/transactor/messages
import aarondb/transactor/runtime
import aarondb/transactor/schema
import aarondb/vec_index
import gleam/dict
import gleam/erlang/process
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor

pub type Message {
  Transact(
    List(fact.Fact),
    Option(Int),
    process.Subject(Result(state.DbState, String)),
  )
  Retract(
    List(fact.Fact),
    Option(Int),
    process.Subject(Result(state.DbState, String)),
  )
  GetState(process.Subject(state.DbState))
  SetSchema(String, fact.AttributeConfig, process.Subject(Result(Nil, String)))
  RegisterFunction(String, fact.DbFunction(state.DbState), process.Subject(Nil))
  RegisterPredicate(String, fn(fact.Value) -> Bool, process.Subject(Nil))
  RegisterComposite(List(String), process.Subject(Result(Nil, String)))
  StoreRule(ast.Rule, process.Subject(Result(Nil, String)))
  SetReactive(process.Subject(state.ReactiveMessage))
  Join(process.Pid)
  SyncDatoms(List(fact.Datom))
  Compact(process.Subject(Nil))
  SetConfig(state.Config, process.Subject(Nil))
  Sync(process.Subject(Nil))
  Boot(
    Option(String),
    storage.StorageAdapter,
    process.Subject(Result(Nil, String)),
  )
  RegisterIndexAdapter(state.IndexAdapter, process.Subject(Nil))
  CreateIndex(String, String, String, process.Subject(Result(Nil, String)))
  CreateBM25Index(String, process.Subject(Result(Nil, String)))
  Subscribe(process.Subject(List(fact.Datom)))
  Prune(Int, List(String), process.Subject(Int))
  RetractEntity(fact.EntityId, process.Subject(Result(state.DbState, String)))
  Tick
  LogQuery(state.QueryContext, process.Subject(Nil))
}

pub type Db =
  process.Subject(Message)

pub fn start(
  store: storage.StorageAdapter,
) -> Result(process.Subject(Message), actor.StartError) {
  start_with_timeout(store, 1000)
}

pub fn start_named(
  name: String,
  store: storage.StorageAdapter,
) -> Result(process.Subject(Message), actor.StartError) {
  do_start_named(store, False, Some(name), 1000)
}

pub fn start_distributed(
  name: String,
  store: storage.StorageAdapter,
) -> Result(process.Subject(Message), actor.StartError) {
  do_start_named(store, True, Some(name), 1000)
}

pub fn start_with_timeout(
  store: storage.StorageAdapter,
  timeout_ms: Int,
) -> Result(process.Subject(Message), actor.StartError) {
  do_start_named(store, False, None, timeout_ms)
}

fn do_start_named(
  store: storage.StorageAdapter,
  is_distributed: Bool,
  ets_name: Option(String),
  timeout_ms: Int,
) -> Result(process.Subject(Message), actor.StartError) {
  case reactive.start_link() {
    Error(error) -> Error(error)
    Ok(reactive_subject) ->
      do_start_after_reactive(
        store,
        is_distributed,
        ets_name,
        timeout_ms,
        reactive_subject,
      )
  }
}

fn do_start_after_reactive(
  store: storage.StorageAdapter,
  is_distributed: Bool,
  ets_name: Option(String),
  timeout_ms: Int,
  reactive_subject: process.Subject(state.ReactiveMessage),
) -> Result(process.Subject(Message), actor.StartError) {
  let base_state =
    state.DbState(
      adapter: store,
      eavt: index.new_index(),
      aevt: index.new_aindex(),
      avet: index.new_avindex(),
      latest_tx: 0,
      subscribers: [],
      schema: dict.new(),
      functions: dict.new(),
      composites: [],
      reactive_actor: reactive_subject,
      followers: [],
      is_distributed: is_distributed,
      ets_name: ets_name,
      vec_index: vec_index.new(),
      bm25_indices: dict.new(),
      art_index: art.new(),
      registry: dict.new(),
      extensions: dict.new(),
      predicates: dict.new(),
      stored_rules: [],
      virtual_predicates: dict.new(),
      columnar_store: dict.new(),
      config: state.Config(
        parallel_threshold: 1000,
        batch_size: 1000,
        prefetch_enabled: False,
        zero_copy_threshold: 10_000,
      ),
      query_history: [],
    )

  let res =
    actor.new(base_state)
    |> actor.on_message(handle_message)
    |> actor.start()

  case res {
    Ok(started) -> {
      let subj = started.data
      let reply = process.new_subject()
      process.send(subj, Boot(ets_name, store, reply))
      case process.receive(reply, timeout_ms) {
        Error(_) -> Error(actor.InitTimeout)
        Ok(Error(_)) -> Error(actor.InitTimeout)
        Ok(Ok(Nil)) -> {
          let pid = process_extra.subject_to_pid(subj)
          let _ = case is_distributed {
            True -> Nil
            False -> {
              let _ = global.register("aarondb_leader", pid)
              Nil
            }
          }

          // Start lifecycle actor
          let _ = process.spawn(fn() { lifecycle_loop(subj) })
          Ok(subj)
        }
      }
    }
    Error(e) -> Error(e)
  }
}

fn lifecycle_loop(parent: process.Subject(Message)) {
  process.sleep(5000)
  process.send(parent, Tick)
  lifecycle_loop(parent)
}

pub fn retract_entity(
  subj: process.Subject(Message),
  eid: fact.EntityId,
  reply: process.Subject(Result(state.DbState, String)),
) -> Nil {
  process.send(subj, RetractEntity(eid, reply))
}

pub fn log_query(
  subj: process.Subject(Message),
  ctx: state.QueryContext,
) -> Nil {
  let reply = process.new_subject()
  process.send(subj, LogQuery(ctx, reply))
  // Fire and forget is okay, but we'll await with a short timeout to prevent mailbox overflow
  let _ = process.receive(reply, 100)
  Nil
}

/// Read the current state before an explicit caller-supplied deadline.
/// A non-positive deadline fails closed rather than hiding an invalid request.
pub fn get_state_with_timeout(
  subj: process.Subject(Message),
  timeout_ms: Int,
) -> Result(state.DbState, String) {
  case timeout_ms > 0 {
    False -> Error("Timeout getting database state")
    True -> {
      let reply = process.new_subject()
      process.send(subj, GetState(reply))
      case process.receive(reply, timeout_ms) {
        Ok(current_state) -> Ok(current_state)
        Error(_) -> Error("Timeout getting database state")
      }
    }
  }
}

/// **Compatibility read helper.** This function uses the default five-second
/// deadline and cannot report a timeout. New integrations should call
/// `get_state_with_timeout/2` and handle its `Result`.
pub fn get_state(subj: process.Subject(Message)) -> state.DbState {
  let reply = process.new_subject()
  process.send(subj, GetState(reply))
  let assert Ok(state) = process.receive(reply, 5000)
  state
}

pub fn set_schema(
  subj: process.Subject(Message),
  attr: String,
  config: fact.AttributeConfig,
) -> Result(Nil, String) {
  set_schema_with_timeout(subj, attr, config, 5000)
}

pub fn set_schema_with_timeout(
  subj: process.Subject(Message),
  attr: String,
  config: fact.AttributeConfig,
  timeout_ms: Int,
) -> Result(Nil, String) {
  let reply = process.new_subject()
  process.send(subj, SetSchema(attr, config, reply))
  case process.receive(reply, timeout_ms) {
    Ok(res) -> res
    Error(_) -> Error("Timeout setting schema")
  }
}

/// **Compatibility registration helper.** This function cannot surface an
/// actor timeout. New integrations should use `register_function_with_timeout/4`.
pub fn register_function(
  subj: process.Subject(Message),
  name: String,
  func: fact.DbFunction(state.DbState),
) -> Nil {
  let _ = register_function_with_timeout(subj, name, func, 5000)
  Nil
}

pub fn register_function_with_timeout(
  subj: process.Subject(Message),
  name: String,
  func: fact.DbFunction(state.DbState),
  timeout_ms: Int,
) -> Result(Nil, String) {
  let reply = process.new_subject()
  process.send(subj, RegisterFunction(name, func, reply))
  case process.receive(reply, timeout_ms) {
    Ok(Nil) -> Ok(Nil)
    Error(_) -> Error("Timeout registering function")
  }
}

pub fn register_composite(
  subj: process.Subject(Message),
  attrs: List(String),
) -> Result(Nil, String) {
  register_composite_with_timeout(subj, attrs, 5000)
}

pub fn register_composite_with_timeout(
  subj: process.Subject(Message),
  attrs: List(String),
  timeout_ms: Int,
) -> Result(Nil, String) {
  case timeout_ms > 0 {
    False -> Error("Timeout registering composite")
    True -> {
      let reply = process.new_subject()
      process.send(subj, RegisterComposite(attrs, reply))
      case process.receive(reply, timeout_ms) {
        Ok(res) -> res
        Error(_) -> Error("Timeout registering composite")
      }
    }
  }
}

pub fn register_predicate(
  subj: process.Subject(Message),
  name: String,
  pred: fn(fact.Value) -> Bool,
) -> Nil {
  let _ = register_predicate_with_timeout(subj, name, pred, 5000)
  Nil
}

pub fn register_predicate_with_timeout(
  subj: process.Subject(Message),
  name: String,
  pred: fn(fact.Value) -> Bool,
  timeout_ms: Int,
) -> Result(Nil, String) {
  let reply = process.new_subject()
  process.send(subj, RegisterPredicate(name, pred, reply))
  case process.receive(reply, timeout_ms) {
    Ok(Nil) -> Ok(Nil)
    Error(_) -> Error("Timeout registering predicate")
  }
}

pub fn store_rule(
  subj: process.Subject(Message),
  rule: ast.Rule,
) -> Result(Nil, String) {
  store_rule_with_timeout(subj, rule, 5000)
}

pub fn store_rule_with_timeout(
  subj: process.Subject(Message),
  rule: ast.Rule,
  timeout_ms: Int,
) -> Result(Nil, String) {
  case timeout_ms > 0 {
    False -> Error("Timeout storing rule")
    True -> {
      let reply = process.new_subject()
      process.send(subj, StoreRule(rule, reply))
      case process.receive(reply, timeout_ms) {
        Ok(res) -> res
        Error(_) -> Error("Timeout storing rule")
      }
    }
  }
}

/// **Compatibility configuration helper.** This function cannot surface an
/// actor timeout. New integrations should use `set_config_with_timeout/3`.
pub fn set_config(subj: process.Subject(Message), config: state.Config) -> Nil {
  let _ = set_config_with_timeout(subj, config, 5000)
  Nil
}

pub fn set_config_with_timeout(
  subj: process.Subject(Message),
  config: state.Config,
  timeout_ms: Int,
) -> Result(Nil, String) {
  let reply = process.new_subject()
  process.send(subj, SetConfig(config, reply))
  case process.receive(reply, timeout_ms) {
    Ok(Nil) -> Ok(Nil)
    Error(_) -> Error("Timeout setting configuration")
  }
}

pub fn transact(
  subj: process.Subject(Message),
  facts: List(fact.Fact),
) -> Result(state.DbState, String) {
  transact_with_timeout(subj, facts, 5000)
}

pub fn transact_with_timeout(
  subj: process.Subject(Message),
  facts: List(fact.Fact),
  timeout_ms: Int,
) -> Result(state.DbState, String) {
  let reply = process.new_subject()
  process.send(subj, Transact(facts, None, reply))
  case process.receive(reply, timeout_ms) {
    Ok(res) -> res
    Error(_) -> Error("Transaction timeout")
  }
}

pub fn retract(
  subj: process.Subject(Message),
  facts: List(fact.Fact),
) -> Result(state.DbState, String) {
  let reply = process.new_subject()
  process.send(subj, Retract(facts, None, reply))
  case process.receive(reply, 5000) {
    Ok(res) -> res
    Error(_) -> Error("Retraction timeout")
  }
}

pub fn compute_next_state(
  state: state.DbState,
  facts: List(fact.Fact),
  valid_time: Option(Int),
  op: fact.Operation,
) -> Result(#(state.DbState, List(fact.Datom)), String) {
  domain.compute_next_state(state, facts, valid_time, op)
}

fn handle_message(
  state: state.DbState,
  msg: Message,
) -> actor.Next(state.DbState, Message) {
  case msg {
    LogQuery(ctx, reply) -> {
      messages.log_query(state, ctx, reply)
    }
    Tick -> {
      actor.continue(lifecycle.handle_tick(state))
    }
    Boot(ets_name, _store, reply) -> {
      case ets_name {
        Some(name) -> ets_index.init_tables(name)
        None -> Nil
      }
      // Initialize Mnesia without ever rewriting incompatible persisted state.
      let initialized = mnesia.init_mnesia()
      case initialized {
        Ok(Nil) -> {
          let new_state = runtime.recover_state(state)
          process.send(reply, Ok(Nil))
          actor.continue(new_state)
        }
        Error(error) -> {
          process.send(reply, Error(error))
          actor.continue(state)
        }
      }
    }
    Transact(facts, vt, reply_to) -> {
      runtime.do_handle_transact(
        state,
        facts,
        vt,
        fact.Assert,
        reply_to,
        compute_next_state,
      )
    }
    Retract(facts, vt, reply_to) -> {
      runtime.do_handle_transact(
        state,
        facts,
        vt,
        fact.Retract,
        reply_to,
        compute_next_state,
      )
    }
    RetractEntity(eid, reply_to) -> {
      let datoms = case state.ets_name {
        Some(name) -> ets_index.lookup_datoms(name <> "_eavt", eid)
        None -> index.filter_by_entity(state.eavt, eid)
      }
      let facts =
        list.map(datoms, fn(d) { #(fact.Uid(d.entity), d.attribute, d.value) })
      runtime.do_handle_transact(
        state,
        facts,
        option.None,
        fact.Retract,
        reply_to,
        compute_next_state,
      )
    }
    GetState(reply_to) -> {
      process.send(reply_to, state)
      actor.continue(state)
    }
    SetSchema(attr, config, reply_to) -> {
      let error = case config.unique {
        True -> schema.validate_unique(state, attr)
        False -> None
      }
      let error = case error {
        None ->
          case config.cardinality == fact.One {
            True -> schema.validate_cardinality_one(state, attr)
            False -> None
          }
        Some(e) -> Some(e)
      }
      messages.set_schema(state, attr, config, error, reply_to)
    }
    RegisterFunction(name, func, reply_to) -> {
      messages.register_function(state, name, func, reply_to)
    }
    RegisterPredicate(name, pred, reply_to) -> {
      messages.register_predicate(state, name, pred, reply_to)
    }
    RegisterComposite(attrs, reply_to) -> {
      messages.register_composite(
        state,
        attrs,
        schema.validate_composite(state, attrs),
        reply_to,
      )
    }
    StoreRule(rule, reply_to) -> {
      messages.store_rule(state, rule, reply_to, compute_next_state)
    }
    Subscribe(reply_to) -> {
      messages.subscribe(state, reply_to)
    }
    SetConfig(config, reply_to) -> {
      messages.set_config(state, config, reply_to)
    }
    _ -> actor.continue(state)
  }
}

pub fn subscribe(
  subj: process.Subject(Message),
) -> process.Subject(List(fact.Datom)) {
  let reply = process.new_subject()
  process.send(subj, Subscribe(reply))
  reply
}
