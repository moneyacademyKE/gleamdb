/// The transaction domain is the deterministic planning and application boundary.
///
/// It accepts only the current database value plus transaction data and returns either
/// an explicit error or the next value together with the ordered datoms to persist.
/// Actor messaging, storage writes, notifications, and reply translation deliberately
/// live in `transactor/runtime`. `state.DbState` is a compatibility-shaped state
/// container; its runtime-owned fields are preserved but not interpreted here.
import aarondb/fact
import aarondb/index
import aarondb/shared/state
import aarondb/transactor/apply
import aarondb/transactor/validation
import gleam/list
import gleam/option.{type Option}
import gleam/result
import gleam/string

pub type Transaction {
  Transaction(
    facts: List(fact.Fact),
    valid_time: Option(Int),
    operation: fact.Operation,
  )
}

pub type Outcome {
  Outcome(state: state.DbState, datoms: List(fact.Datom))
}

pub fn apply(
  database: state.DbState,
  transaction: Transaction,
) -> Result(Outcome, String) {
  let Transaction(facts, valid_time, operation) = transaction
  let tx_id = database.latest_tx + 1
  let vt = option.unwrap(valid_time, tx_id)
  let resolved_facts =
    apply.resolve_transaction_functions(database, tx_id, vt, facts)

  let datoms_result =
    list.fold_until(resolved_facts, Ok([]), fn(acc_result, fact_input) {
      let assert Ok(acc) = acc_result
      let entity_result = case fact_input.0 {
        fact.Uid(id) -> Ok(id)
        fact.Lookup(lookup) -> {
          let #(attribute, value) = lookup
          case attribute == "db/fn" {
            True ->
              Error(
                "Unresolved transaction function: " <> string.inspect(value),
              )
            False ->
              index.get_entity_by_av(database.avet, attribute, value)
              |> result.replace_error("Lookup failed for " <> attribute)
          }
        }
      }

      case entity_result {
        Ok(entity) ->
          list.Continue(
            Ok([
              fact.Datom(
                entity: entity,
                attribute: fact_input.1,
                value: fact_input.2,
                tx: tx_id,
                tx_index: list.length(acc),
                valid_time: vt,
                operation: operation,
              ),
              ..acc
            ]),
          )
        Error(error) -> list.Stop(Error(error))
      }
    })

  case datoms_result {
    Error(error) -> Error(error)
    Ok(datoms) -> {
      let datoms = list.reverse(datoms)
      let #(final_state, all_datoms, _) =
        list.fold(datoms, #(database, [], 0), fn(acc, datom) {
          let #(current_state, collected, next_index) = acc
          let #(next_state, side_effect_datoms, updated_index) =
            apply.apply_datom(
              current_state,
              fact.Datom(..datom, tx_index: next_index),
              next_index,
            )
          #(
            next_state,
            list.append(side_effect_datoms, collected),
            updated_index,
          )
        })
      let all_datoms = list.reverse(all_datoms)

      let validation_result =
        list.fold_until(all_datoms, Ok(Nil), fn(_, datom) {
          case validation.validate_datom(database, all_datoms, datom) {
            Ok(_) -> list.Continue(Ok(Nil))
            Error(error) -> list.Stop(Error(error))
          }
        })

      case validation_result {
        Ok(_) ->
          Ok(Outcome(state.DbState(..final_state, latest_tx: tx_id), all_datoms))
        Error(error) -> Error(error)
      }
    }
  }
}

pub fn compute_next_state(
  database: state.DbState,
  facts: List(fact.Fact),
  valid_time: Option(Int),
  operation: fact.Operation,
) -> Result(#(state.DbState, List(fact.Datom)), String) {
  apply(database, Transaction(facts, valid_time, operation))
  |> result.map(fn(outcome) {
    let Outcome(next_state, datoms) = outcome
    #(next_state, datoms)
  })
}
