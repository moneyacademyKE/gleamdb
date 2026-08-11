import aarondb/fact
import aarondb/index
import aarondb/index/art
import aarondb/reactive
import aarondb/shared/ownership
import aarondb/shared/ownership_test_support
import aarondb/shared/state as shared_state
import aarondb/storage
import aarondb/transactor/domain
import aarondb/transactor/lifecycle
import aarondb/transactor/schema
import aarondb/transactor/validation
import aarondb/vec_index
import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import gleeunit/should

pub fn ownership_projection_is_complete_and_absent_extensions_are_explicit_test() {
  let state = ownership_test_support.empty(storage.ephemeral(), False, None)
  let view = ownership.view(state)

  view.facts.latest_tx |> should.equal(0)
  index.get_all_datoms(view.facts.eavt) |> should.equal([])
  ownership_test_support.has_no_optional_extensions(state) |> should.equal(True)
}

pub fn ownership_projection_preserves_transaction_and_index_coherence_test() {
  let state = ownership_test_support.empty(storage.ephemeral(), False, None)
  let facts = [#(fact.Uid(fact.EntityId(42)), "person/name", fact.Str("Rich"))]

  let assert Ok(domain.Outcome(next_state, _datoms)) =
    domain.apply(state, domain.Transaction(facts, None, fact.Assert))
  let view = ownership.view(next_state)

  view.facts.latest_tx |> should.equal(1)
  list.length(index.get_all_datoms(view.facts.eavt)) |> should.equal(1)
  list.length(index.get_all_datoms_aevt(view.facts.aevt)) |> should.equal(1)
  list.length(index.get_all_datoms_avet(view.facts.avet)) |> should.equal(1)
}

pub fn domain_apply_preserves_fact_order_and_declares_datoms_test() {
  let state = base_state()
  let facts = [
    #(fact.Uid(fact.EntityId(7)), "person/name", fact.Str("Rich")),
    #(fact.Uid(fact.EntityId(7)), "person/role", fact.Str("programmer")),
  ]

  let assert Ok(domain.Outcome(next_state, datoms)) =
    domain.apply(state, domain.Transaction(facts, None, fact.Assert))

  next_state.latest_tx |> should.equal(1)
  list.map(datoms, fn(d) { d.attribute })
  |> should.equal(["person/name", "person/role"])
  list.map(datoms, fn(d) { d.tx_index }) |> should.equal([0, 1])
}

pub fn domain_apply_rejects_unresolved_lookup_without_effects_test() {
  let state = base_state()
  let facts = [
    #(
      fact.Lookup(#("person/email", fact.Str("missing@example.com"))),
      "person/name",
      fact.Str("Nope"),
    ),
  ]

  domain.apply(state, domain.Transaction(facts, None, fact.Assert))
  |> should.equal(Error("Lookup failed for person/email"))
}

pub fn schema_validate_unique_test() {
  let state =
    base_state()
    |> with_datoms([
      fact.Datom(
        entity: fact.EntityId(1),
        attribute: "user/email",
        value: fact.Str("dup@example.com"),
        tx: 1,
        tx_index: 0,
        valid_time: 0,
        operation: fact.Assert,
      ),
      fact.Datom(
        entity: fact.EntityId(2),
        attribute: "user/email",
        value: fact.Str("dup@example.com"),
        tx: 1,
        tx_index: 1,
        valid_time: 0,
        operation: fact.Assert,
      ),
    ])

  schema.validate_unique(state, "user/email")
  |> should.equal(Some(
    "Cannot make non-unique attribute unique: existing data has duplicates",
  ))
}

pub fn schema_validate_cardinality_one_test() {
  let state =
    base_state()
    |> with_datoms([
      fact.Datom(
        entity: fact.EntityId(1),
        attribute: "user/alias",
        value: fact.Str("Rich"),
        tx: 1,
        tx_index: 0,
        valid_time: 0,
        operation: fact.Assert,
      ),
      fact.Datom(
        entity: fact.EntityId(1),
        attribute: "user/alias",
        value: fact.Str("Hickey"),
        tx: 1,
        tx_index: 1,
        valid_time: 0,
        operation: fact.Assert,
      ),
    ])

  schema.validate_cardinality_one(state, "user/alias")
  |> should.equal(Some(
    "Cannot set cardinality to ONE: existing entities have multiple values",
  ))
}

pub fn lifecycle_handle_tick_evicts_disk_attrs_test() {
  let state =
    base_state()
    |> with_schema("cold/value", disk_schema())
    |> with_datoms([
      fact.Datom(
        entity: fact.EntityId(1),
        attribute: "cold/value",
        value: fact.Int(10),
        tx: 1,
        tx_index: 0,
        valid_time: 0,
        operation: fact.Assert,
      ),
    ])
    |> with_latest_tx(200)

  let next = lifecycle.handle_tick(state)

  list.length(index.get_all_datoms(next.eavt)) |> should.equal(0)
}

pub fn validation_validate_datom_unique_violation_test() {
  let state =
    base_state()
    |> with_schema("user/email", unique_schema())
    |> with_datoms([
      fact.Datom(
        entity: fact.EntityId(1),
        attribute: "user/email",
        value: fact.Str("rich@hickey.com"),
        tx: 1,
        tx_index: 0,
        valid_time: 0,
        operation: fact.Assert,
      ),
    ])

  let new_datom =
    fact.Datom(
      entity: fact.EntityId(2),
      attribute: "user/email",
      value: fact.Str("rich@hickey.com"),
      tx: 2,
      tx_index: 0,
      valid_time: 0,
      operation: fact.Assert,
    )

  validation.validate_datom(state, [new_datom], new_datom)
  |> should.equal(Error("Uniqueness violation for user/email"))
}

fn base_state() {
  let assert Ok(reactive_actor) = reactive.start_link()
  shared_state.DbState(
    adapter: storage.ephemeral(),
    eavt: dict.new(),
    aevt: dict.new(),
    avet: dict.new(),
    latest_tx: 0,
    subscribers: [],
    schema: dict.new(),
    functions: dict.new(),
    composites: [],
    reactive_actor: reactive_actor,
    followers: [],
    is_distributed: False,
    ets_name: None,
    vec_index: vec_index.new(),
    bm25_indices: dict.new(),
    art_index: art.new(),
    registry: dict.new(),
    extensions: dict.new(),
    predicates: dict.new(),
    stored_rules: [],
    virtual_predicates: dict.new(),
    columnar_store: dict.new(),
    config: shared_state.Config(
      parallel_threshold: 500,
      batch_size: 100,
      prefetch_enabled: False,
      zero_copy_threshold: 10_000,
    ),
    query_history: [],
  )
}

fn with_datoms(state, datoms) {
  let eavt =
    list.fold(datoms, dict.new(), fn(idx, d) {
      index.insert_eavt(idx, d, fact.All)
    })
  let aevt =
    list.fold(datoms, dict.new(), fn(idx, d) {
      index.insert_aevt(idx, d, fact.All)
    })
  let avet =
    list.fold(datoms, dict.new(), fn(idx, d) { index.insert_avet(idx, d) })
  shared_state.DbState(..state, eavt: eavt, aevt: aevt, avet: avet)
}

fn with_schema(state, attr, config) {
  shared_state.DbState(..state, schema: dict.insert(state.schema, attr, config))
}

fn with_latest_tx(state, latest_tx) {
  shared_state.DbState(..state, latest_tx: latest_tx)
}

fn unique_schema() {
  fact.AttributeConfig(
    unique: True,
    component: False,
    retention: fact.All,
    cardinality: fact.One,
    check: None,
    composite_group: None,
    layout: fact.Row,
    tier: fact.Memory,
    eviction: fact.AlwaysInMemory,
  )
}

fn disk_schema() {
  fact.AttributeConfig(
    unique: False,
    component: False,
    retention: fact.All,
    cardinality: fact.Many,
    check: None,
    composite_group: None,
    layout: fact.Row,
    tier: fact.Disk,
    eviction: fact.AlwaysInMemory,
  )
}
