import aarondb/fact.{type Datom}
import aarondb/index
import aarondb/shared/ast
import aarondb/shared/state.{type DbState}
import aarondb/storage

/// Retrieves datoms matching a pattern from the database indices.
/// Rich Hickey alignment: "The index is an implementation detail of the fact store."
pub fn find_datoms(db_state: DbState, pattern: ast.Clause) -> List(Datom) {
  // Try adapter first
  case storage.query_datoms(db_state.adapter, pattern) {
    Ok(datoms) if datoms != [] -> datoms
    _ -> {
      let #(e, a, v) = pattern

      case e, a, v {
        // E A V bound
        ast.Uid(eid), attr, ast.Val(val) -> {
          index.get_datoms_by_entity_attr_val(db_state.eavt, eid, attr, val)
        }
        ast.Lookup(_l), _attr, ast.Val(_val) -> {
          // Resolve lookup first (simplified for now)
          []
        }

        // E A bound
        ast.Uid(eid), attr, ast.Var(_) -> {
          index.get_datoms_by_entity_attr(db_state.eavt, eid, attr)
        }

        // A V bound
        ast.Var(_), attr, ast.Val(val) -> {
          // Use AVET or AEVT depending on availability
          index.get_datoms_by_val(db_state.aevt, attr, val)
        }

        // A bound
        ast.Var(_), attr, ast.Var(_) -> {
          index.filter_by_attribute(db_state.aevt, attr)
        }

        // E bound
        ast.Uid(eid), _, _ -> {
          index.filter_by_entity(db_state.eavt, eid)
        }

        // Fallback: full scan (rarely intended in planning)
        ast.Var(_), _, _ -> {
          index.get_all_datoms(db_state.eavt)
        }

        _, _, _ -> []
      }
    }
  }
}
