import aarondb/fact
import aarondb/shared/ast
import aarondb/shared/state
import aarondb/storage/internal
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, Some}
import gleam/set.{type Set}

pub type ClauseSolver =
  fn(
    state.DbState,
    ast.BodyClause,
    Dict(String, fact.Value),
    Set(fact.Datom),
    Option(Int),
    Option(Int),
  ) -> #(
    List(Dict(String, fact.Value)),
    Option(Dict(String, List(internal.StorageChunk))),
  )

pub type PartResolver =
  fn(ast.Part, Dict(String, fact.Value)) -> Option(fact.Value)

pub fn derive_all_facts(
  db_state: state.DbState,
  rules: List(ast.Rule),
  as_of_tx: Option(Int),
  as_of_valid: Option(Int),
  solve_clause_with_derived: ClauseSolver,
  resolve_part_optional: PartResolver,
) -> Set(fact.Datom) {
  do_derive(
    db_state,
    rules,
    as_of_tx,
    as_of_valid,
    set.new(),
    solve_clause_with_derived,
    resolve_part_optional,
  )
}

fn do_derive(
  db_state: state.DbState,
  rules: List(ast.Rule),
  as_of_tx: Option(Int),
  as_of_valid: Option(Int),
  derived: Set(fact.Datom),
  solve_clause_with_derived: ClauseSolver,
  resolve_part_optional: PartResolver,
) -> Set(fact.Datom) {
  do_derive_recursive(
    db_state,
    rules,
    as_of_tx,
    as_of_valid,
    derived,
    derived,
    True,
    solve_clause_with_derived,
    resolve_part_optional,
  )
}

fn do_derive_recursive(
  db_state: state.DbState,
  rules: List(ast.Rule),
  as_of_tx: Option(Int),
  as_of_valid: Option(Int),
  all_derived: Set(fact.Datom),
  last_new_derived: Set(fact.Datom),
  first_run: Bool,
  solve_clause_with_derived: ClauseSolver,
  resolve_part_optional: PartResolver,
) -> Set(fact.Datom) {
  case !first_run && set.size(last_new_derived) == 0 {
    True -> all_derived
    False -> {
      let next_new =
        list.fold(rules, set.new(), fn(acc, r) {
          let #(results, _store) =
            solve_rule_body_semi_naive(
              db_state,
              r.body,
              all_derived,
              as_of_tx,
              as_of_valid,
              solve_clause_with_derived,
            )

          list.fold(results, acc, fn(inner_acc, ctx) {
            let e = resolve_part_optional(r.head.0, ctx)
            let v = resolve_part_optional(r.head.2, ctx)
            case e, v {
              Some(fact.Ref(fact.EntityId(eid_val))), Some(val) ->
                insert_if_new(all_derived, inner_acc, r.head.1, eid_val, val)
              Some(fact.Int(eid_val)), Some(val) ->
                insert_if_new(all_derived, inner_acc, r.head.1, eid_val, val)
              _, _ -> inner_acc
            }
          })
        })

      case set.size(next_new) == 0 {
        True -> all_derived
        False ->
          do_derive_recursive(
            db_state,
            rules,
            as_of_tx,
            as_of_valid,
            set.union(all_derived, next_new),
            next_new,
            False,
            solve_clause_with_derived,
            resolve_part_optional,
          )
      }
    }
  }
}

fn solve_rule_body_semi_naive(
  db_state: state.DbState,
  body: List(ast.BodyClause),
  all_derived: Set(fact.Datom),
  as_of_tx: Option(Int),
  as_of_valid: Option(Int),
  solve_clause_with_derived: ClauseSolver,
) -> #(
  List(Dict(String, fact.Value)),
  Option(Dict(String, List(internal.StorageChunk))),
) {
  list.fold(body, #([dict.new()], option.None), fn(acc, clause_i) {
    let #(ctxs, current_store) = acc
    list.fold(ctxs, #([], current_store), fn(inner_acc, ctx) {
      let #(acc_ctxs, acc_store) = inner_acc
      let #(new_ctxs, clause_store) =
        solve_clause_with_derived(
          db_state,
          clause_i,
          ctx,
          all_derived,
          as_of_tx,
          as_of_valid,
        )
      #(
        list.append(acc_ctxs, new_ctxs),
        merge_stores(acc_store, clause_store),
      )
    })
  })
}

fn insert_if_new(
  all_derived: Set(fact.Datom),
  acc: Set(fact.Datom),
  attribute: String,
  eid_val: Int,
  val: fact.Value,
) -> Set(fact.Datom) {
  let d =
    fact.Datom(
      entity: fact.EntityId(eid_val),
      attribute: attribute,
      value: val,
      tx: 0,
      tx_index: 0,
      valid_time: 0,
      operation: fact.Assert,
    )
  case set.contains(all_derived, d) {
    True -> acc
    False -> set.insert(acc, d)
  }
}

fn merge_stores(
  s1: Option(Dict(String, List(internal.StorageChunk))),
  s2: Option(Dict(String, List(internal.StorageChunk))),
) -> Option(Dict(String, List(internal.StorageChunk))) {
  case s1, s2 {
    option.Some(m1), option.Some(m2) -> option.Some(dict.merge(m1, m2))
    option.Some(_), option.None -> s1
    option.None, option.Some(_) -> s2
    option.None, option.None -> option.None
  }
}
