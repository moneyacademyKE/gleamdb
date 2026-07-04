import aarondb/fact
import aarondb/index/art
import aarondb/shared/state
import gleam/dict.{type Dict}
import gleam/list
import gleam/string

pub fn starts_with(
  db_state: state.DbState,
  var: String,
  prefix: String,
  ctx: Dict(String, fact.Value),
) -> List(Dict(String, fact.Value)) {
  case dict.get(ctx, var) {
    Ok(fact.Str(s)) -> {
      case string.starts_with(s, prefix) {
        True -> [ctx]
        False -> []
      }
    }
    Ok(_) -> []
    Error(_) -> {
      art.search_prefix_entries(db_state.art_index, prefix)
      |> list.map(fn(entry) {
        let #(val, _eid) = entry
        dict.insert(ctx, var, val)
      })
      |> list.unique()
    }
  }
}
