import aarondb/fact
import aarondb/global
import aarondb/index
import aarondb/index/art
import aarondb/index/ets as ets_index
import aarondb/process_extra
import aarondb/raft
import aarondb/reactive
import aarondb/shared/ast
import aarondb/shared/state
import aarondb/storage
import aarondb/storage/mnesia
import aarondb/transactor/apply
import aarondb/transactor/lifecycle
import aarondb/transactor/messages
import aarondb/transactor/runtime
import aarondb/transactor/schema
import aarondb/transactor/validation
import aarondb/vec_index
import gleam/dict
import gleam/erlang/process
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/result
import gleam/string

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
  RaftMsg(raft.RaftMessage)
  Compact(process.Subject(Nil))
  SetConfig(state.Config, process.Subject(Nil))
  Sync(process.Subject(Nil))
  Boot(Option(String), storage.StorageAdapter, process.Subject(Nil))
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
  do_start_named(store, False, Some(name))
}

pub fn start_distributed(
  name: String,
  store: storage.StorageAdapter,
) -> Result(process.Subject(Message), actor.StartError) {
  do_start_named(store, True, Some(name))
}

pub fn start_with_timeout(
  store: storage.StorageAdapter,
  _timeout_ms: Int,
) -> Result(process.Subject(Message), actor.StartError) {
  do_start_named(store, False, None)
}

fn do_start_named(
  store: storage.StorageAdapter,
  is_distributed: Bool,
  ets_name: Option(String),
) -> Result(process.Subject(Message), actor.StartError) {
  let assert Ok(reactive_subject) = reactive.start_link()

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
      raft_state: raft.new([]),
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
      let _ = process.receive(reply, 600_000)

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
  let reply = process.new_subject()
  process.send(subj, SetSchema(attr, config, reply))
  let assert Ok(res) = process.receive(reply, 5000)
  res
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

pub fn register_function(
  subj: process.Subject(Message),
  name: String,
  func: fact.DbFunction(state.DbState),
) -> Nil {
  let reply = process.new_subject()
  process.send(subj, RegisterFunction(name, func, reply))
  let assert Ok(Nil) = process.receive(reply, 5000)
  Nil
}

pub fn register_composite(
  subj: process.Subject(Message),
  attrs: List(String),
) -> Result(Nil, String) {
  let reply = process.new_subject()
  process.send(subj, RegisterComposite(attrs, reply))
  let assert Ok(res) = process.receive(reply, 5000)
  res
}

pub fn register_predicate(
  subj: process.Subject(Message),
  name: String,
  pred: fn(fact.Value) -> Bool,
) -> Nil {
  let reply = process.new_subject()
  process.send(subj, RegisterPredicate(name, pred, reply))
  let assert Ok(Nil) = process.receive(reply, 5000)
  Nil
}

pub fn store_rule(
  subj: process.Subject(Message),
  rule: ast.Rule,
) -> Result(Nil, String) {
  let reply = process.new_subject()
  process.send(subj, StoreRule(rule, reply))
  let assert Ok(res) = process.receive(reply, 5000)
  res
}

pub fn set_config(subj: process.Subject(Message), config: state.Config) -> Nil {
  let reply = process.new_subject()
  process.send(subj, SetConfig(config, reply))
  let assert Ok(Nil) = process.receive(reply, 5000)
  Nil
}

pub fn transact(
  subj: process.Subject(Message),
  facts: List(fact.Fact),
) -> Result(state.DbState, String) {
  let reply = process.new_subject()
  process.send(subj, Transact(facts, None, reply))
  let assert Ok(res) = process.receive(reply, 5000)
  res
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
  let assert Ok(res) = process.receive(reply, 5000)
  res
}

pub fn compute_next_state(
  state: state.DbState,
  facts: List(fact.Fact),
  valid_time: Option(Int),
  op: fact.Operation,
) -> Result(#(state.DbState, List(fact.Datom)), String) {
  let tx_id = state.latest_tx + 1
  let vt = option.unwrap(valid_time, tx_id)

  // 1. Resolve transaction functions
  let resolved_facts =
    apply.resolve_transaction_functions(state, tx_id, vt, facts)

  // 2. Generate datoms
  let datoms_res =
    list.fold_until(resolved_facts, Ok([]), fn(acc_res, f) {
      let assert Ok(acc) = acc_res
      let eid_res = case f.0 {
        fact.Uid(id) -> Ok(id)
        fact.Lookup(lu) -> {
          let #(a, v) = lu
          case a == "db/fn" {
            True ->
              Error("Unresolved transaction function: " <> string.inspect(v))
            False -> {
              index.get_entity_by_av(state.avet, a, v)
              |> result.replace_error("Lookup failed for " <> a)
            }
          }
        }
      }

      case eid_res {
        Ok(eid) -> {
          let d =
            fact.Datom(
              entity: eid,
              attribute: f.1,
              value: f.2,
              tx: tx_id,
              tx_index: list.length(acc),
              valid_time: vt,
              operation: op,
            )
          list.Continue(Ok([d, ..acc]))
        }
        Error(e) -> list.Stop(Error(e))
      }
    })

  case datoms_res {
    Ok(datoms) -> {
      // 3. APPLY TO STATE AND GENERATE SIDE-EFFECTS
      // We must reverse because they were prepended
      let datoms = list.reverse(datoms)

      let #(final_state, all_datoms, _) =
        list.fold(datoms, #(state, [], 0), fn(acc, d) {
          let #(curr_state, collected, next_idx) = acc
          let #(new_state, side_effects, updated_idx) =
            apply.apply_datom(
              curr_state,
              fact.Datom(..d, tx_index: next_idx),
              next_idx,
            )
          #(new_state, list.append(side_effects, collected), updated_idx)
        })

      let all_datoms = list.reverse(all_datoms)

      // 4. APPLY VALIDATIONS
      let validate_res =
        list.fold_until(all_datoms, Ok(Nil), fn(_, d) {
          // Use INITIAL state for validation, but include IN-FLIGHT datoms
          case validation.validate_datom(state, all_datoms, d) {
            Ok(_) -> list.Continue(Ok(Nil))
            Error(e) -> list.Stop(Error(e))
          }
        })

      case validate_res {
        Ok(_) -> {
          Ok(#(state.DbState(..final_state, latest_tx: tx_id), all_datoms))
        }
        Error(e) -> Error(e)
      }
    }
    Error(e) -> Error(e)
  }
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
      // Initialize Mnesia
      let _ = mnesia.init_mnesia()

      let new_state = runtime.recover_state(state)
      process.send(reply, Nil)
      actor.continue(new_state)
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
