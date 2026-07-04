import aarondb/fact
import aarondb/shared/ast
import aarondb/shared/state
import aarondb/storage/internal
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, None, Some}
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

pub fn solve(
  db_state: state.DbState,
  type_: ast.TemporalType,
  time: Int,
  op: ast.TemporalOp,
  variable: String,
  entity_p: ast.Part,
  clauses: List(ast.BodyClause),
  ctx: Dict(String, fact.Value),
  solve_with_derived: ClauseSolver,
) -> List(Dict(String, fact.Value)) {
  let _e_val = resolve_part(entity_p, ctx)

  let as_of_tx = case type_ {
    ast.Tx ->
      case op {
        ast.At -> Some(time)
        ast.Since -> Some(time)
        ast.Until -> Some(time)
        _ -> None
      }
    _ -> None
  }

  let as_of_valid = case type_ {
    ast.Valid ->
      case op {
        ast.At -> Some(time)
        ast.Since -> Some(time)
        ast.Until -> Some(time)
        _ -> None
      }
    _ -> None
  }

  let initial_context = [ctx]
  let #(rows, _) =
    list.fold(clauses, #(initial_context, None), fn(acc, clause) {
      let #(contexts, current_store) = acc
      list.fold(contexts, #([], current_store), fn(inner_acc, c) {
        let #(acc_ctxs, acc_store) = inner_acc
        let #(new_ctxs, clause_store) =
          solve_with_derived(
            db_state,
            clause,
            c,
            set.new(),
            as_of_tx,
            as_of_valid,
          )
        #(
          list.append(acc_ctxs, new_ctxs),
          merge_stores(acc_store, clause_store),
        )
      })
    })

  list.map(rows, fn(r) { dict.insert(r, variable, fact.Int(time)) })
}

fn merge_stores(
  s1: Option(Dict(String, List(internal.StorageChunk))),
  s2: Option(Dict(String, List(internal.StorageChunk))),
) -> Option(Dict(String, List(internal.StorageChunk))) {
  case s1, s2 {
    Some(m1), Some(m2) -> Some(dict.merge(m1, m2))
    Some(_), None -> s1
    None, Some(_) -> s2
    None, None -> None
  }
}

fn resolve_part(
  part: ast.Part,
  ctx: Dict(String, fact.Value),
) -> Option(fact.Value) {
  case part {
    ast.Var(name) -> option_from_result(dict.get(ctx, name))
    ast.Val(val) -> Some(val)
    ast.Uid(uid) -> Some(fact.Ref(uid))
    ast.AttrVal(s) -> Some(fact.Str(s))
    ast.Lookup(#(_, val)) -> Some(val)
  }
}

fn option_from_result(res: Result(a, b)) -> Option(a) {
  case res {
    Ok(v) -> Some(v)
    Error(_) -> None
  }
}
