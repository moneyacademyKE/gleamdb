import aarondb/fact
import aarondb/shared/ast
import aarondb/shared/state
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{Some}

/// Run a bounded local adapter. Rows retain the adapter's order; an adapter
/// failure, invalid row limit, or row-limit overflow makes this clause produce
/// no rows. Query execution is intentionally fail-closed at this boundary.
pub fn solve(
  db_state: state.DbState,
  predicate: String,
  args: List(ast.Part),
  outputs: List(String),
  ctx: Dict(String, fact.Value),
) -> List(Dict(String, fact.Value)) {
  let resolved_args =
    list.try_map(args, fn(arg) {
      resolve_part(arg, ctx)
      |> option.to_result(Nil)
    })

  case resolved_args, dict.get(db_state.virtual_predicates, predicate) {
    Ok(vals), Ok(state.VirtualAdapter(execute: execute, max_rows: max_rows)) ->
      case execute(vals) {
        Ok(rows) ->
          case list.length(rows) <= max_rows {
            True ->
              rows
              |> list.filter_map(fn(row) { bind_outputs(ctx, outputs, row) })
            False -> []
          }
        Error(_) -> []
      }
    _, _ -> []
  }
}

fn bind_outputs(
  ctx: Dict(String, fact.Value),
  outputs: List(String),
  row: List(fact.Value),
) -> Result(Dict(String, fact.Value), Nil) {
  case list.length(outputs) == list.length(row) {
    True -> {
      list.zip(outputs, row)
      |> list.try_fold(ctx, fn(acc, pair) {
        let #(var, val) = pair
        case dict.get(acc, var) {
          Ok(existing) ->
            case existing == val {
              True -> Ok(acc)
              False -> Error(Nil)
            }
          Error(_) -> Ok(dict.insert(acc, var, val))
        }
      })
    }
    False -> Error(Nil)
  }
}

fn resolve_part(
  part: ast.Part,
  ctx: Dict(String, fact.Value),
) -> option.Option(fact.Value) {
  case part {
    ast.Var(name) -> option.from_result(dict.get(ctx, name))
    ast.Val(val) -> Some(val)
    ast.Uid(uid) -> Some(fact.Ref(uid))
    ast.AttrVal(s) -> Some(fact.Str(s))
    ast.Lookup(#(_, val)) -> Some(val)
  }
}
