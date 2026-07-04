import aarondb/fact
import aarondb/shared/ast
import gleam/dict.{type Dict}
import gleam/option.{type Option, Some}

pub fn resolve_part(
  part: ast.Part,
  ctx: Dict(String, fact.Value),
) -> Option(fact.Value) {
  case part {
    ast.Var(name) -> option.from_result(dict.get(ctx, name))
    ast.Val(val) -> Some(val)
    ast.Uid(uid) -> Some(fact.Ref(uid))
    ast.AttrVal(s) -> Some(fact.Str(s))
    ast.Lookup(#(_, val)) -> Some(val)
  }
}

pub fn resolve_part_optional(
  part: ast.Part,
  ctx: Dict(String, fact.Value),
) -> Option(fact.Value) {
  case part {
    ast.Var(name) -> option.from_result(dict.get(ctx, name))
    ast.Val(val) -> Some(val)
    ast.Uid(uid) -> Some(fact.Ref(uid))
    ast.AttrVal(s) -> Some(fact.Str(s))
    ast.Lookup(#(_, val)) -> Some(val)
  }
}
