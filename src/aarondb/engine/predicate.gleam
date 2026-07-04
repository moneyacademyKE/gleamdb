import aarondb/fact
import aarondb/shared/ast
import gleam/dict.{type Dict}
import gleam/option.{Some}
import gleam/order

pub fn compile(
  expr: ast.Expression,
) -> fn(Dict(String, fact.Value)) -> Bool {
  case expr {
    ast.Eq(a, b) -> {
      fn(ctx) {
        let val_a = resolve_part(a, ctx)
        let val_b = resolve_part(b, ctx)
        val_a == val_b && option.is_some(val_a)
      }
    }
    ast.Neq(a, b) -> {
      fn(ctx) {
        let val_a = resolve_part(a, ctx)
        let val_b = resolve_part(b, ctx)
        val_a != val_b
      }
    }
    ast.Gt(a, b) -> {
      fn(ctx) {
        let val_a = resolve_part(a, ctx) |> option.unwrap(fact.Int(0))
        let val_b = resolve_part(b, ctx) |> option.unwrap(fact.Int(0))
        fact.compare(val_a, val_b) == order.Gt
      }
    }
    ast.Lt(a, b) -> {
      fn(ctx) {
        let val_a = resolve_part(a, ctx) |> option.unwrap(fact.Int(0))
        let val_b = resolve_part(b, ctx) |> option.unwrap(fact.Int(0))
        fact.compare(val_a, val_b) == order.Lt
      }
    }
    ast.And(l, r) -> {
      let compiled_l = compile(l)
      let compiled_r = compile(r)
      fn(ctx) { compiled_l(ctx) && compiled_r(ctx) }
    }
    ast.Or(l, r) -> {
      let compiled_l = compile(l)
      let compiled_r = compile(r)
      fn(ctx) { compiled_l(ctx) || compiled_r(ctx) }
    }
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
