import aarondb/engine/solver/bindings
import aarondb/fact
import aarondb/shared/ast
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{Some}

pub fn vector_from_part(
  target_p: ast.Part,
  ctx: Dict(String, fact.Value),
) -> List(Float) {
  case bindings.resolve_part(target_p, ctx) {
    Some(fact.Vec(vs)) -> vs
    Some(fact.List(vs)) ->
      list.filter_map(vs, fn(v) {
        case v {
          fact.Float(f) -> Ok(f)
          _ -> Error(Nil)
        }
      })
    _ -> []
  }
}
