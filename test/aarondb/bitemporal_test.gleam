import aarondb
import aarondb/fact
import aarondb/shared/ast
import gleam/dict
import gleam/int
import gleam/list
import gleam/option
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn transaction_time_at_is_inclusive_and_update_aware_test() {
  let db = aarondb.new()
  let entity = fact.Uid(fact.EntityId(501))
  let assert Ok(_) =
    aarondb.set_schema(db, "account/status", cardinality_one_config())

  let assert Ok(state_one) =
    aarondb.transact(db, [#(entity, "account/status", fact.Str("draft"))])
  let assert Ok(state_two) =
    aarondb.transact(db, [#(entity, "account/status", fact.Str("active"))])

  let clause = aarondb.p(#(ast.Var("e"), "account/status", ast.Var("status")))
  should.equal(statuses(aarondb.as_of(db, state_one.latest_tx, [clause])), [
    "draft",
  ])
  should.equal(statuses(aarondb.as_of(db, state_two.latest_tx, [clause])), [
    "active",
  ])
  should.equal(statuses(aarondb.as_of(db, 0, [clause])), [])
}

pub fn valid_time_at_diverges_from_transaction_time_test() {
  let db = aarondb.new()
  let entity = fact.Uid(fact.EntityId(502))
  let assert Ok(_) =
    aarondb.set_schema(db, "contract/state", cardinality_one_config())

  let assert Ok(state_one) =
    aarondb.transact_at(
      db,
      [#(entity, "contract/state", fact.Str("draft"))],
      300,
    )
  let assert Ok(state_two) =
    aarondb.transact_at(
      db,
      [#(entity, "contract/state", fact.Str("active"))],
      100,
    )

  let clause = aarondb.p(#(ast.Var("e"), "contract/state", ast.Var("state")))
  should.equal(statuses(aarondb.as_of(db, state_one.latest_tx, [clause])), [
    "draft",
  ])
  should.equal(statuses(aarondb.as_of(db, state_two.latest_tx, [clause])), [
    "active",
  ])
  should.equal(statuses(aarondb.as_of_valid(db, 99, [clause])), [])
  should.equal(statuses(aarondb.as_of_valid(db, 100, [clause])), ["active"])
  should.equal(statuses(aarondb.as_of_valid(db, 299, [clause])), ["active"])
}

pub fn temporal_clause_at_matches_complete_query_snapshot_test() {
  let db = aarondb.new()
  let entity = fact.Uid(fact.EntityId(503))
  let assert Ok(_) =
    aarondb.set_schema(db, "profile/city", cardinality_one_config())
  let assert Ok(state_one) =
    aarondb.transact(db, [#(entity, "profile/city", fact.Str("London"))])
  let assert Ok(_) =
    aarondb.transact(db, [#(entity, "profile/city", fact.Str("Paris"))])

  let snapshot =
    aarondb.as_of(db, state_one.latest_tx, [
      aarondb.p(#(ast.Var("e"), "profile/city", ast.Var("city"))),
    ])
  let nested =
    aarondb.query(db, [
      ast.Temporal(ast.Tx, state_one.latest_tx, ast.At, "basis", ast.Var("e"), [
        aarondb.p(#(ast.Var("e"), "profile/city", ast.Var("city"))),
      ]),
    ])

  should.equal(statuses(snapshot), ["London"])
  should.equal(statuses(nested), ["London"])
}

pub fn retraction_is_visible_in_history_and_hidden_at_latest_basis_test() {
  let db = aarondb.new()
  let entity = fact.Uid(fact.EntityId(504))
  let assert Ok(state_one) =
    aarondb.transact(db, [#(entity, "note/text", fact.Str("keep me"))])
  let assert Ok(state_two) =
    aarondb.retract(db, [#(entity, "note/text", fact.Str("keep me"))])

  let clause = aarondb.p(#(ast.Var("e"), "note/text", ast.Var("text")))
  should.equal(statuses(aarondb.as_of(db, state_one.latest_tx, [clause])), [
    "keep me",
  ])
  should.equal(statuses(aarondb.as_of(db, state_two.latest_tx, [clause])), [])

  // `history` is index ordered, not chronological. Sort by transaction before
  // asserting the temporal lifecycle.
  let history =
    aarondb.history(db, entity)
    |> list.sort(fn(left, right) { int.compare(left.tx, right.tx) })
  should.equal(list.length(history), 2)
  let assert [assertion, retraction] = history
  should.equal(assertion.operation, fact.Assert)
  should.equal(retraction.operation, fact.Retract)
  should.be_true(assertion.tx < retraction.tx)
}

pub fn bounded_temporal_queries_return_typed_budget_errors_test() {
  let db = aarondb.new()
  let entity = fact.Uid(fact.EntityId(505))
  let assert Ok(_) =
    aarondb.transact(db, [#(entity, "event/name", fact.Str("launch"))])
  let second = fact.Uid(fact.EntityId(507))
  let assert Ok(_) =
    aarondb.transact(db, [#(second, "event/name", fact.Str("second"))])
  let clause = aarondb.p(#(ast.Var("e"), "event/name", ast.Var("name")))

  should.equal(
    aarondb.temporal_scan_limits(0),
    Error(aarondb.InvalidTemporalScanLimit),
  )
  let assert Ok(limits) = aarondb.temporal_scan_limits(1)
  should.equal(
    aarondb.as_of_bounded(db, 1, [clause], limits),
    Error(aarondb.TemporalScanBudgetExceeded),
  )
}

pub fn bounded_temporal_queries_match_legacy_snapshots_within_budget_test() {
  let db = aarondb.new()
  let entity = fact.Uid(fact.EntityId(506))
  let assert Ok(state) =
    aarondb.transact_at(db, [#(entity, "event/name", fact.Str("launch"))], 42)
  let clause = aarondb.p(#(ast.Var("e"), "event/name", ast.Var("name")))
  let assert Ok(limits) = aarondb.temporal_scan_limits(10)
  let assert Ok(result) =
    aarondb.as_of_bitemporal_bounded(db, state.latest_tx, 42, [clause], limits)

  should.equal(statuses(result), ["launch"])
}

fn statuses(result: aarondb.QueryResult) -> List(String) {
  result.rows
  |> list.filter_map(fn(row) {
    ["status", "state", "city", "text", "name"]
    |> list.find_map(fn(key) {
      case dict.get(row, key) {
        Ok(fact.Str(value)) -> Ok(value)
        _ -> Error(Nil)
      }
    })
  })
  |> list.sort(string.compare)
}

fn cardinality_one_config() -> fact.AttributeConfig {
  fact.AttributeConfig(
    unique: False,
    component: False,
    retention: fact.All,
    cardinality: fact.One,
    check: option.None,
    composite_group: option.None,
    layout: fact.Row,
    tier: fact.Memory,
    eviction: fact.AlwaysInMemory,
  )
}
