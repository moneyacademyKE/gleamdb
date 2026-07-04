import aarondb/engine
import aarondb/fact.{type AttributeConfig, type Fact}
import aarondb/global
import aarondb/index
import aarondb/index/ets
import aarondb/process_extra
import aarondb/q.{type QueryBuilder}
import aarondb/raft
import aarondb/shared/ast
import aarondb/shared/query_types
import aarondb/shared/state
import aarondb/storage.{type StorageAdapter}
import aarondb/transactor
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/result

pub type Db =
  transactor.Db

pub type PullResult =
  query_types.PullResult

pub type PullPattern =
  ast.PullPattern

pub type DbState =
  state.DbState

pub type QueryResult =
  query_types.QueryResult

pub type BodyClause =
  ast.BodyClause

pub type SpeculativeResult {
  SpeculativeResult(state: state.DbState, datoms: List(fact.Datom))
}

pub fn new() -> Db {
  new_with_adapter(None)
}

pub fn new_with_adapter(adapter: Option(StorageAdapter)) -> Db {
  new_with_adapter_and_timeout(adapter, 5000)
}

pub fn new_with_adapter_and_timeout(
  adapter: Option(StorageAdapter),
  timeout_ms: Int,
) -> Db {
  let assert Ok(db) = start_link(adapter, timeout_ms)
  db
}

pub fn start_link(
  adapter: Option(StorageAdapter),
  timeout_ms: Int,
) -> Result(Subject(transactor.Message), actor.StartError) {
  let store = case adapter {
    Some(s) -> s
    None -> storage.ephemeral()
  }

  transactor.start_with_timeout(store, timeout_ms)
}

pub fn start_named(
  name: String,
  adapter: Option(StorageAdapter),
) -> Result(Subject(transactor.Message), actor.StartError) {
  let store = case adapter {
    Some(s) -> s
    None -> storage.ephemeral()
  }
  transactor.start_named(name, store)
}

pub fn start_distributed(
  name: String,
  adapter: Option(StorageAdapter),
) -> Result(Subject(transactor.Message), actor.StartError) {
  let store = case adapter {
    Some(s) -> s
    None -> storage.ephemeral()
  }
  transactor.start_distributed(name, store)
}

pub fn connect(name: String) -> Result(Db, String) {
  case global.whereis("aarondb_" <> name) {
    Ok(pid) -> Ok(process_extra.pid_to_subject(pid))
    Error(_) -> Error("Could not find database named " <> name)
  }
}

pub fn transact(db: Db, facts: List(Fact)) -> Result(DbState, String) {
  transactor.transact(db, facts)
}

pub fn transact_at(
  db: Db,
  facts: List(Fact),
  valid_time: Int,
) -> Result(DbState, String) {
  let reply = process.new_subject()
  process.send(db, transactor.Transact(facts, Some(valid_time), reply))
  case process.receive(reply, 5000) {
    Ok(res) -> res
    Error(_) -> Error("Timeout")
  }
}

pub fn transact_with_timeout(
  db: Db,
  facts: List(Fact),
  timeout_ms: Int,
) -> Result(DbState, String) {
  transactor.transact_with_timeout(db, facts, timeout_ms)
}

pub fn retract(db: Db, facts: List(Fact)) -> Result(DbState, String) {
  transactor.retract(db, facts)
}

pub fn retract_at(
  db: Db,
  facts: List(Fact),
  valid_time: Int,
) -> Result(DbState, String) {
  let reply = process.new_subject()
  process.send(db, transactor.Retract(facts, Some(valid_time), reply))
  case process.receive(reply, 5000) {
    Ok(res) -> res
    Error(_) -> Error("Timeout")
  }
}

pub fn prune(db: Db, threshold: Int, sovereign: List(String)) -> Int {
  let reply = process.new_subject()
  process.send(db, transactor.Prune(threshold, sovereign, reply))
  case process.receive(reply, 5000) {
    Ok(count) -> count
    Error(_) -> 0
  }
}

pub fn trigger_eviction(db: Db) -> Result(Nil, String) {
  process.send(db, transactor.Tick)
  Ok(Nil)
}

pub fn retract_entity(db: Db, eid: fact.Eid) -> Result(DbState, String) {
  case eid {
    fact.Uid(entity) -> {
      let reply = process.new_subject()
      process.send(db, transactor.RetractEntity(entity, reply))
      case process.receive(reply, 5000) {
        Ok(res) -> res
        Error(_) -> Error("Timeout")
      }
    }
    _ -> Error("Only Uid supported for retract_entity")
  }
}

pub fn with_facts(
  state: DbState,
  facts: List(Fact),
) -> Result(SpeculativeResult, String) {
  transactor.compute_next_state(state, facts, None, fact.Assert)
  |> result.map(fn(res) { SpeculativeResult(state: res.0, datoms: res.1) })
}

/// Provides a human-readable explanation of a speculative result or failure.
pub fn explain_speculation(res: Result(SpeculativeResult, String)) -> String {
  case res {
    Ok(s) ->
      "Speculation successful: "
      <> int.to_string(list.length(s.datoms))
      <> " datoms predicted."
    Error(e) -> "Speculation failed: " <> e
  }
}

pub fn get(db: Db, eid: fact.Eid, attr: String) -> List(fact.Value) {
  let state = transactor.get_state(db)
  let id = case eid {
    fact.Uid(i) -> i
    fact.Lookup(#(a, v)) -> {
      index.get_entity_by_av(state.avet, a, v)
      |> result.unwrap(fact.EntityId(0))
    }
  }
  case state.ets_name {
    Some(name) -> {
      ets.lookup_datoms(name <> "_eavt", id)
      |> list.filter(fn(d) { d.attribute == attr })
      |> list.map(fn(d) { d.value })
    }
    None -> {
      index.get_datoms_by_entity_attr(state.eavt, id, attr)
      |> list.map(fn(d) { d.value })
    }
  }
}

pub fn get_one(db: Db, eid: fact.Eid, attr: String) -> Result(fact.Value, Nil) {
  get(db, eid, attr) |> list.first()
}

pub fn set_schema(
  db: Db,
  attr: String,
  config: AttributeConfig,
) -> Result(Nil, String) {
  transactor.set_schema(db, attr, config)
}

pub fn set_schema_with_timeout(
  db: Db,
  attr: String,
  config: AttributeConfig,
  timeout_ms: Int,
) -> Result(Nil, String) {
  transactor.set_schema_with_timeout(db, attr, config, timeout_ms)
}

pub fn history(db: Db, eid: fact.Eid) -> List(fact.Datom) {
  let state = transactor.get_state(db)
  let id = case eid {
    fact.Uid(i) -> i
    fact.Lookup(#(a, v)) -> {
      index.get_entity_by_av(state.avet, a, v)
      |> result.unwrap(fact.EntityId(0))
    }
  }
  case state.ets_name {
    Some(name) -> ets.lookup_datoms(name <> "_eavt", id)
    None -> index.get_datoms_by_entity(state.eavt, id)
  }
}

fn extract_pull_attributes(pattern: PullPattern) -> List(String) {
  list.fold(pattern, [], fn(acc, p) {
    case p {
      ast.Attr(a) -> [a, ..acc]
      ast.Nested(a, inner) -> [
        a,
        ..list.append(extract_pull_attributes(inner), acc)
      ]
      _ -> acc
    }
  })
}

pub fn pull(db: Db, eid: fact.Eid, pattern: PullPattern) -> PullResult {
  let state = transactor.get_state(db)
  case state.config.prefetch_enabled {
    True -> {
      let attrs = extract_pull_attributes(pattern)
      let ctx =
        state.QueryContext(attributes: attrs, entities: [], timestamp: 0)
      transactor.log_query(db, ctx)
    }
    False -> Nil
  }
  let id = case eid {
    fact.Uid(i) -> i
    fact.Lookup(#(a, v)) -> {
      index.get_entity_by_av(state.avet, a, v)
      |> result.unwrap(fact.EntityId(0))
    }
  }
  engine.pull(state, id, pattern)
}

pub fn diff(db: Db, from_tx: Int, to_tx: Int) -> List(fact.Datom) {
  let state = transactor.get_state(db)
  engine.diff(state, from_tx, to_tx)
}

pub fn pull_all() -> PullPattern {
  [ast.Wildcard]
}

pub fn pull_attr(attr: String) -> PullPattern {
  [ast.Attr(attr)]
}

pub fn pull_except(exclusions: List(String)) -> PullPattern {
  [ast.Except(exclusions)]
}

pub fn pull_recursive(attr: String, depth: Int) -> PullPattern {
  [ast.PullRecursion(attr, depth)]
}

pub fn query(db: Db, q_clauses: List(BodyClause)) -> QueryResult {
  let state = transactor.get_state(db)
  let q =
    ast.Query(
      find: [],
      where: q_clauses,
      order_by: None,
      limit: None,
      offset: None,
    )
  engine.run(state, q, [], None, None)
}

pub fn q(db: Db, q_builder: QueryBuilder) -> QueryResult {
  let state = transactor.get_state(db)
  let q = q.to_query(q_builder)
  engine.run(state, q, [], None, None)
}

pub fn query_at(
  db: Db,
  q_clauses: List(BodyClause),
  as_of_tx: Option(Int),
  as_of_valid: Option(Int),
) -> QueryResult {
  let state = transactor.get_state(db)
  let q =
    ast.Query(
      find: [],
      where: q_clauses,
      order_by: None,
      limit: None,
      offset: None,
    )
  engine.run(state, q, state.stored_rules, as_of_tx, as_of_valid)
}

pub fn query_state(state: DbState, q_clauses: List(BodyClause)) -> QueryResult {
  let q =
    ast.Query(
      find: [],
      where: q_clauses,
      order_by: None,
      limit: None,
      offset: None,
    )
  engine.run(state, q, [], None, None)
}

pub fn query_state_at(
  state: DbState,
  q_clauses: List(BodyClause),
  as_of_tx: Option(Int),
  as_of_valid: Option(Int),
) -> QueryResult {
  let q =
    ast.Query(
      find: [],
      where: q_clauses,
      order_by: None,
      limit: None,
      offset: None,
    )
  engine.run(state, q, [], as_of_tx, as_of_valid)
}

pub fn execute(db: Db, query: ast.Query) -> QueryResult {
  let state = transactor.get_state(db)
  engine.run(state, query, [], None, None)
}

pub fn query_state_with_rules(
  state: DbState,
  q_clauses: List(BodyClause),
  rules: List(ast.Rule),
) -> QueryResult {
  let q =
    ast.Query(
      find: [],
      where: q_clauses,
      order_by: None,
      limit: None,
      offset: None,
    )
  engine.run(state, q, rules, None, None)
}

pub fn query_with_rules(
  db: Db,
  q_clauses: List(BodyClause),
  rules: List(ast.Rule),
) -> QueryResult {
  let state = transactor.get_state(db)
  let q =
    ast.Query(
      find: [],
      where: q_clauses,
      order_by: None,
      limit: None,
      offset: None,
    )
  engine.run(state, q, rules, None, None)
}

pub fn as_of(db: Db, tx: Int, q_clauses: List(BodyClause)) -> QueryResult {
  let state = transactor.get_state(db)
  let q =
    ast.Query(
      find: [],
      where: q_clauses,
      order_by: None,
      limit: None,
      offset: None,
    )
  engine.run(state, q, state.stored_rules, Some(tx), None)
}

pub fn as_of_valid(
  db: Db,
  valid_time: Int,
  q_clauses: List(BodyClause),
) -> QueryResult {
  let state = transactor.get_state(db)
  let q =
    ast.Query(
      find: [],
      where: q_clauses,
      order_by: None,
      limit: None,
      offset: None,
    )
  engine.run(state, q, state.stored_rules, None, Some(valid_time))
}

pub fn as_of_bitemporal(
  db: Db,
  tx: Int,
  valid_time: Int,
  q_clauses: List(BodyClause),
) -> QueryResult {
  let state = transactor.get_state(db)
  let q =
    ast.Query(
      find: [],
      where: q_clauses,
      order_by: None,
      limit: None,
      offset: None,
    )
  engine.run(state, q, state.stored_rules, Some(tx), Some(valid_time))
}

pub fn p(triple: ast.Clause) -> BodyClause {
  ast.Positive(triple)
}

pub fn register_function(
  db: Db,
  name: String,
  func: fact.DbFunction(state.DbState),
) -> Nil {
  transactor.register_function(db, name, func)
}

pub fn register_composite(db: Db, attrs: List(String)) -> Result(Nil, String) {
  transactor.register_composite(db, attrs)
}

pub fn register_predicate(
  db: Db,
  name: String,
  pred: fn(fact.Value) -> Bool,
) -> Nil {
  transactor.register_predicate(db, name, pred)
}

pub fn store_rule(db: Db, rule: ast.Rule) -> Result(Nil, String) {
  transactor.store_rule(db, rule)
}

pub fn set_config(db: Db, config: state.Config) -> Nil {
  transactor.set_config(db, config)
}

pub fn subscribe(
  db: Db,
  query: ast.Query,
  subscriber: Subject(query_types.ReactiveDelta),
) -> Nil {
  let state = transactor.get_state(db)
  let results = engine.run(state, query, [], None, None)

  let attrs =
    list.filter_map(query.where, fn(c) {
      case c {
        ast.Positive(#(_, a, _)) -> Ok(a)
        ast.Negative(#(_, a, _)) -> Ok(a)
        _ -> Error(Nil)
      }
    })

  let msg = state.Subscribe(query, attrs, subscriber, results)
  process.send(state.reactive_actor, msg)
  process.send(subscriber, query_types.Initial(results))
  Nil
}

pub fn subscribe_wal(db: Db, subscriber: Subject(List(fact.Datom))) -> Nil {
  process.send(db, transactor.Subscribe(subscriber))
}

pub fn get_state(db: Db) -> DbState {
  transactor.get_state(db)
}

pub fn sync(db: Db) -> Nil {
  let reply = process.new_subject()
  process.send(db, transactor.Sync(reply))
  let _ = process.receive(reply, 5000)
  Nil
}

pub fn is_leader(db: Db) -> Bool {
  let state = transactor.get_state(db)
  raft.is_leader(state.raft_state)
}

pub fn traverse(
  db: Db,
  eid: fact.Eid,
  path: List(ast.Step),
  max_depth: Int,
) -> Result(List(fact.Value), String) {
  let state = transactor.get_state(db)
  let id = case eid {
    fact.Uid(fact.EntityId(i)) -> i
    fact.Lookup(#(a, v)) -> {
      index.get_entity_by_av(state.avet, a, v)
      |> result.unwrap(fact.EntityId(0))
      |> fact.eid_to_integer
    }
  }

  let engine_path =
    list.map(path, fn(s) {
      case s {
        ast.In(a) -> query_types.In(a)
        ast.Out(a) -> query_types.Out(a)
      }
    })

  engine.traverse(state, id, engine_path, max_depth)
}
