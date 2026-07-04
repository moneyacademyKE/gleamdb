import aarondb/fact
import aarondb/shared/ast
import aarondb/shared/state
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{Some}

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

  case resolved_args {
    Ok(vals) -> {
      case dict.get(db_state.virtual_predicates, predicate) {
        Ok(adapter) -> {
          adapter(vals)
          |> list.filter_map(fn(row) { bind_outputs(ctx, outputs, row) })
        }
        Error(_) -> []
      }
    }
    Error(_) -> []
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
