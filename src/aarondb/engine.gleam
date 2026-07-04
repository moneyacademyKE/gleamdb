import aarondb/engine/cognitive
import aarondb/engine/entity
import aarondb/engine/executor
import aarondb/engine/navigator
import aarondb/engine/planner
import aarondb/engine/rules
import aarondb/engine/solver/bindings
import aarondb/engine/solver/core
import aarondb/engine/solver/derived
import aarondb/engine/solver/recursive
import aarondb/engine/solver_context
import aarondb/engine/traversal
import aarondb/fact
import aarondb/index
import aarondb/shared/ast
import aarondb/shared/query_types
import aarondb/shared/state
import aarondb/storage/internal

import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/set.{type Set}

// Rule moved to types.gleam to avoid cycle

// Pull types moved to shared/types.gleam to avoid cycles

pub fn run(
  db_state: state.DbState,
  query: ast.Query,
  rules: List(ast.Rule),
  as_of_tx: Option(Int),
  as_of_valid: Option(Int),
) -> query_types.QueryResult {
  let _clauses = query.where
  let as_of_v = case as_of_valid {
    Some(vt) -> Some(vt)
    None -> Some(2_147_483_647)
    // Max Int (v1.9.0 default: inclusive of future valid time)
  }
  let all_rules = list.append(rules, db_state.stored_rules)
  let all_derived =
    rules.derive_all_facts(
      db_state,
      all_rules,
      as_of_tx,
      as_of_v,
      solve_clause_with_derived,
      bindings.resolve_part_optional,
    )
  let solver =
    solver_context.SolverContext(
      db_state: db_state,
      rules: all_rules,
      derived: all_derived,
      as_of_tx: as_of_tx,
      as_of_valid: as_of_v,
    )
  let initial_context = [dict.new()]

  let plan = planner.build(query)
  let planned_clauses = plan.clauses

  // [Dogfood Learning] Graph Type Safety: check if graph edges are Refs
  list.each(planned_clauses, fn(c) {
    case c {
      ast.PageRank(_, edge, _, _, _)
      | ast.CycleDetect(edge, _)
      | ast.StronglyConnectedComponents(edge, _, _)
      | ast.TopologicalSort(edge, _, _) -> {
        let config = dict.get(db_state.schema, edge)
        case config {
          Ok(conf) if conf.cardinality != fact.Many -> {
            // In a real logger we'd use that, for now print to stdout
            // which is visible in Gswarm logs
            let _ =
              aarondb_io_println(
                "⚠️ Warning: Graph edge '"
                <> edge
                <> "' should be Ref(EntityId) for optimal performance.",
              )
          }
          _ -> Nil
        }
      }
      _ -> Nil
    }
  })

  let execution =
    executor.execute(planned_clauses, initial_context, None, fn(clause, ctx, _) {
      solve_with_context(solver, clause, ctx)
    })

  let rows =
    execution.rows
    |> planner.order_rows(plan.query.order_by)
    |> planner.page_rows(plan.query.offset, plan.query.limit)

  query_types.QueryResult(
    rows: rows |> list.unique(),
    metadata: query_types.QueryMetadata(
      tx_id: as_of_tx,
      valid_time: as_of_valid,
      execution_time_ms: 0,
      index_hits: 0,
      plan: "",
      shard_id: None,
      aggregates: plan.aggregates,
    ),
    updated_columnar_store: execution.store,
  )
}

@external(erlang, "io", "format")
fn aarondb_io_println(x: String) -> Nil

fn nested_solve(
  solver: solver_context.SolverContext,
  clauses: List(ast.BodyClause),
  contexts: List(Dict(String, fact.Value)),
) -> #(
  List(Dict(String, fact.Value)),
  Option(Dict(String, List(internal.StorageChunk))),
) {
  recursive.nested_solve(solver, clauses, contexts, solve_clause)
}

fn solve_clause(
  db_state: state.DbState,
  clause: ast.BodyClause,
  ctx: Dict(String, fact.Value),
  rules: List(ast.Rule),
  as_of_tx: Option(Int),
  as_of_valid: Option(Int),
) -> #(
  List(Dict(String, fact.Value)),
  Option(Dict(String, List(internal.StorageChunk))),
) {
  core.solve_clause(
    db_state,
    clause,
    ctx,
    rules,
    as_of_tx,
    as_of_valid,
    nested_solve,
    solve_clause_with_derived,
  )
}

fn solve_with_context(
  solver: solver_context.SolverContext,
  clause: ast.BodyClause,
  ctx: Dict(String, fact.Value),
) -> #(
  List(Dict(String, fact.Value)),
  Option(Dict(String, List(internal.StorageChunk))),
) {
  derived.solve_with_context(solver, clause, ctx, solve_clause)
}

fn solve_clause_with_derived(
  db_state: state.DbState,
  clause: ast.BodyClause,
  ctx: Dict(String, fact.Value),
  all_derived: Set(fact.Datom),
  as_of_tx: Option(Int),
  as_of_valid: Option(Int),
) -> #(
  List(Dict(String, fact.Value)),
  Option(Dict(String, List(internal.StorageChunk))),
) {
  derived.solve_clause_with_derived(
    db_state,
    clause,
    ctx,
    all_derived,
    as_of_tx,
    as_of_valid,
    solve_clause,
  )
}

pub fn entity_history(
  db_state: state.DbState,
  eid: fact.EntityId,
) -> List(fact.Datom) {
  entity.entity_history(db_state, eid)
}

pub fn pull(
  db_state: state.DbState,
  eid: fact.EntityId,
  pattern: ast.PullPattern,
) -> query_types.PullResult {
  entity.pull(db_state, eid, pattern)
}

pub fn pull_result_to_value(res: query_types.PullResult) -> fact.Value {
  entity.pull_result_to_value(res)
}

pub fn traverse(
  db_state: state.DbState,
  start_id: Int,
  expr: query_types.TraversalExpr,
  max_depth: Int,
) -> Result(List(fact.Value), String) {
  traversal.traverse(db_state, start_id, expr, max_depth)
}

// `search_prefix` traverses the tree and collects values.
// In `art.gleam`, `collect_all_values` returns `List(fact.EntityId)`.
// It doesn't yield the implementation keys (the actual strings).

// Issue: The current ART implementation indexes Value -> EntityId.
// It efficiently finds Entities.
// But `StartsWith(var, "foo")` binds `var` to the *Value* string?
// Typically `var` is a Value in Datalog.

// If the query is:
// `Fact(e, "name", name), StartsWith(name, "Al")`
// We can use ART to find all Entities `e` where "name" starts with "Al".
// But `StartsWith` is a filter on `name`.

// If `name` is unbound, `StartsWith` acts as a generator?
// Infinite generator if not restricted?
// Usually `StartsWith` is used as a constraint on an existing bound variable or an attribute lookup.

// If we want to use ART for `StartsWith`, we need to iterate the ART keys.
// The current `art.gleam` `search_prefix` returns EntityIds, which means it found values matching.
// But it loses the actual value string.
// To bind `name` to "Alice", "Alan", etc., we need the keys from ART.

// OPTIMIZATION:
// For now, let's implement `StartsWith` as a filter only (requires bound variable).
// AND if we want to support efficient lookup, we'd need a `search_prefix_keys` in ART.
// Let's stick to Filter behavior for now, and maybe generator if simple.

// Wait, if I want to use the index, I should probably expose `search_prefix_keys`.
// Let's implement it as a Filter for now to be safe and correct.
pub fn diff(
  db_state: state.DbState,
  from_tx: Int,
  to_tx: Int,
) -> List(fact.Datom) {
  index.get_all_datoms(db_state.eavt)
  |> list.filter(fn(d) { d.tx > from_tx && d.tx <= to_tx })
}

pub fn explain(clauses: List(ast.BodyClause)) -> String {
  navigator.explain(clauses)
}

pub fn filter_by_time(
  datoms: List(fact.Datom),
  tx_limit: Option(Int),
  valid_limit: Option(Int),
) -> List(fact.Datom) {
  datoms
  |> list.filter(fn(d) {
    let tx_ok = case tx_limit {
      Some(tx) -> d.tx <= tx
      None -> True
    }
    let valid_ok = case valid_limit {
      Some(vt) -> d.valid_time <= vt
      None -> True
    }
    tx_ok && valid_ok
  })
}

pub fn solve_cognitive(
  db_state: state.DbState,
  concept: ast.Part,
  context: ast.Part,
  threshold: Float,
  engram_var: String,
  ctx: Dict(String, fact.Value),
  as_of_tx: Option(Int),
  as_of_valid: Option(Int),
) -> List(Dict(String, fact.Value)) {
  cognitive.solve(
    db_state,
    concept,
    context,
    threshold,
    engram_var,
    ctx,
    as_of_tx,
    as_of_valid,
  )
}
