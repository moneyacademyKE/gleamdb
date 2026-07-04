import aarondb/fact
import aarondb/shared/ast
import aarondb/shared/state
import gleam/option.{type Option}
import gleam/set.{type Set}

pub type SolverContext {
  SolverContext(
    db_state: state.DbState,
    rules: List(ast.Rule),
    derived: Set(fact.Datom),
    as_of_tx: Option(Int),
    as_of_valid: Option(Int),
  )
}
