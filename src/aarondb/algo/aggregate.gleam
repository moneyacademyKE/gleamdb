import aarondb/fact.{type Value, Float, Int}
import aarondb/shared/ast
import gleam/float
import gleam/int
import gleam/list
import gleam/order
import gleam/result
import gleam/string

pub fn aggregate(
  values: List(Value),
  op: ast.AggFunc,
) -> Result(Value, String) {
  case op {
    ast.Count -> Ok(Int(list.length(values)))
    ast.Sum -> sum(values)
    ast.Min -> min_val(values)
    ast.Max -> max_val(values)
    ast.Avg -> avg(values)
    ast.Median -> median(values)
  }
}

fn sum(values: List(Value)) -> Result(Value, String) {
  case values {
    [] -> Ok(Int(0))
    [first, ..rest] -> {
      list.try_fold(rest, first, fn(acc, v) {
        case acc, v {
          Int(a), Int(b) -> Ok(Int(a + b))
          Float(a), Float(b) -> Ok(Float(a +. b))
          Int(a), Float(b) -> Ok(Float(int.to_float(a) +. b))
          Float(a), Int(b) -> Ok(Float(a +. int.to_float(b)))
          _, _ -> Error("Cannot sum non-numeric values")
        }
      })
    }
  }
}

fn min_val(values: List(Value)) -> Result(Value, String) {
  case values {
    [] -> Error("Cannot compute min of empty list")
    [first, ..rest] -> {
      list.try_fold(rest, first, fn(acc, v) {
        compare_values(acc, v)
        |> result.map(fn(ord) {
          case ord {
            order.Lt -> acc
            _ -> v
          }
        })
      })
    }
  }
}

fn max_val(values: List(Value)) -> Result(Value, String) {
  case values {
    [] -> Error("Cannot compute max of empty list")
    [first, ..rest] -> {
      list.try_fold(rest, first, fn(acc, v) {
        compare_values(acc, v)
        |> result.map(fn(ord) {
          case ord {
            order.Gt -> acc
            _ -> v
          }
        })
      })
    }
  }
}

fn avg(values: List(Value)) -> Result(Value, String) {
  case values {
    [] -> Error("Cannot compute average of empty list")
    _ -> {
      use s <- result.try(sum(values))
      let count = list.length(values)
      case s {
        Int(i) -> Ok(Float(int.to_float(i) /. int.to_float(count)))
        Float(f) -> Ok(Float(f /. int.to_float(count)))
        _ -> Error("Cannot average non-numeric sum")
      }
    }
  }
}

fn median(values: List(Value)) -> Result(Value, String) {
  case values {
    [] -> Error("Cannot compute median of empty list")
    _ -> {
      // Sort first
      let sorted =
        list.sort(values, fn(a, b) {
          case compare_values(a, b) {
            Ok(o) -> o
            Error(_) -> order.Eq
            // Fallback for mixed types, though dangerous
          }
        })

      let len = list.length(sorted)
      let mid = len / 2

      case len % 2 {
        1 -> {
          // Odd: take middle
          list.drop(sorted, mid)
          |> list.first
          |> result.replace_error("Index error")
        }
        0 -> {
          // Even: average of two middle
          let m1 = list.drop(sorted, mid - 1) |> list.first
          let m2 = list.drop(sorted, mid) |> list.first

          case m1, m2 {
            Ok(v1), Ok(v2) -> avg([v1, v2])
            _, _ -> Error("Index error")
          }
        }
        _ -> Error("Math broken")
      }
    }
  }
}

fn compare_values(a: Value, b: Value) -> Result(order.Order, String) {
  case a, b {
    Int(i1), Int(i2) -> Ok(int.compare(i1, i2))
    Float(f1), Float(f2) -> Ok(float.compare(f1, f2))
    Int(i1), Float(f2) -> Ok(float.compare(int.to_float(i1), f2))
    Float(f1), Int(i2) -> Ok(float.compare(f1, int.to_float(i2)))
    fact.Str(s1), fact.Str(s2) -> Ok(string.compare(s1, s2))
    _, _ -> Error("Cannot compare incompatible types")
  }
}
