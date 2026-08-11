import aarondb
import aarondb/fact
import aarondb/q
import aarondb/shared/ast
import aarondb/shared/state
import aarondb/transactor
import gleam/erlang/process
import gleam/io
import gleam/option.{None}
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn supervision_test() {
  io.println("Running supervision_test")
  // Verify child_spec compiles and works in a supervisor
  // We can't easily run a supervisor in test without blocking, but we can verify start_link

  let db = aarondb.new_with_adapter_and_timeout(None, 1000)

  // Test DSL
  let query =
    q.select(["e"])
    |> q.where(q.v("e"), "attr", q.i(42))
    |> q.to_clauses()

  // Verify query execution (even if empty db)
  let _results = aarondb.query(db, query)

  // Test Public Types (compilation check)
  let _p: aarondb.PullPattern = aarondb.pull_all()

  should.be_true(True)
}

pub fn timeout_aware_management_apis_test() {
  let db = aarondb.new()
  let config =
    state.Config(
      parallel_threshold: 1,
      batch_size: 1,
      prefetch_enabled: False,
      zero_copy_threshold: 1,
    )

  aarondb.register_function_with_timeout(db, "no_op", no_op, 1000)
  |> should.equal(Ok(Nil))
  aarondb.register_predicate_with_timeout(db, "always", fn(_) { True }, 1000)
  |> should.equal(Ok(Nil))
  aarondb.set_config_with_timeout(db, config, 1000)
  |> should.equal(Ok(Nil))
}

pub fn timeout_aware_management_apis_report_dead_actor_test() {
  let subject = process.new_subject()
  let config =
    state.Config(
      parallel_threshold: 1,
      batch_size: 1,
      prefetch_enabled: False,
      zero_copy_threshold: 1,
    )

  transactor.register_function_with_timeout(subject, "no_op", no_op, 1)
  |> should.equal(Error("Timeout registering function"))
  transactor.register_predicate_with_timeout(
    subject,
    "always",
    fn(_) { True },
    1,
  )
  |> should.equal(Error("Timeout registering predicate"))
  transactor.set_config_with_timeout(subject, config, 1)
  |> should.equal(Error("Timeout setting configuration"))
}

pub fn timeout_aware_composite_and_rule_apis_report_dead_actor_test() {
  let subject = process.new_subject()
  let rule =
    ast.Rule(#(ast.Var("e"), "person/name", ast.Var("name")), [
      ast.Positive(#(ast.Var("e"), "person/name", ast.Var("name"))),
    ])

  transactor.register_composite_with_timeout(subject, ["person/email"], 1)
  |> should.equal(Error("Timeout registering composite"))
  transactor.store_rule_with_timeout(subject, rule, 1)
  |> should.equal(Error("Timeout storing rule"))
  transactor.get_state_with_timeout(subject, 0)
  |> should.equal(Error("Timeout getting database state"))
}

fn no_op(
  _state: state.DbState,
  _tx: Int,
  _valid_time: Int,
  _args: List(fact.Value),
) -> List(fact.Fact) {
  []
}

pub fn dsl_test() {
  let _query =
    q.new()
    |> q.where(q.v("e"), "name", q.s("Sly"))
    |> q.negate(q.v("e"), "status", q.s("offline"))
    |> q.to_clauses()

  // Check structure (this is internal detail but good to verify DSL logic)
  // We just ensure it compiles and runs.
  should.be_true(True)
}
