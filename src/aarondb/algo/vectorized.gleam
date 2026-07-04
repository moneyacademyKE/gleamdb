import aarondb/fact.{Float, Int}
import aarondb/storage/internal.{type StorageChunk}
import gleam/list

pub fn sum_column(chunk: StorageChunk) -> Float {
  sum_node(chunk.values)
}

pub fn chunks_to_datoms(
  chunks: List(internal.StorageChunk),
) -> List(fact.Datom) {
  list.flat_map(chunks, fn(chunk) {
    node_to_values(chunk.values)
    |> list.map(fn(v) {
      fact.Datom(
        entity: fact.EntityId(0),
        attribute: chunk.attribute,
        value: v,
        tx: 0,
        operation: fact.Assert,
        tx_index: 0,
        valid_time: 0,
      )
    })
  })
}

fn node_to_values(node: internal.CrackingNode) -> List(fact.Value) {
  case node {
    internal.Leaf(vs) -> vs
    internal.Branch(_, l, r) ->
      list.append(node_to_values(l), node_to_values(r))
  }
}

fn sum_node(node: internal.CrackingNode) -> Float {
  case node {
    internal.Leaf(values) -> {
      list.fold(values, 0.0, fn(acc, v) {
        case v {
          Int(i) -> acc +. int_to_float(i)
          Float(f) -> acc +. f
          _ -> acc
        }
      })
    }
    internal.Branch(_, left, right) -> {
      sum_node(left) +. sum_node(right)
    }
  }
}

pub fn avg_column(chunk: StorageChunk) -> Float {
  let len = count_node(chunk.values)
  case len {
    0 -> 0.0
    _ -> sum_node(chunk.values) /. int_to_float(len)
  }
}

pub fn count_node(node: internal.CrackingNode) -> Int {
  case node {
    internal.Leaf(values) -> list.length(values)
    internal.Branch(_, left, right) -> count_node(left) + count_node(right)
  }
}

@external(erlang, "erlang", "float")
fn int_to_float(i: Int) -> Float
