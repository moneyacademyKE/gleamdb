import aarondb.{type Db}
import aarondb/auth
import aarondb/fact
import aarondb/shared/ast

pub type GatewayError {
  Unauthorized(String)
  TransactError(String)
  QueryError(String)
}

/// Rich Hickey 🧙🏾‍♂️: The Gateway is a pure authorization boundary.
/// It verifies capabilities before any AST reaches the internal logic.
pub fn authorize_and_transact(
  db: Db,
  token_str: String,
  facts: List(fact.Fact),
  required_caps: List(auth.Capability),
) -> Result(Int, GatewayError) {
  case auth.decode_token(token_str) {
    Ok(token) -> {
      case auth.authorize(token, required_caps) {
        Ok(Nil) -> {
          case aarondb.transact(db, facts) {
            Ok(receipt) -> Ok(receipt.latest_tx)
            Error(e) -> Error(TransactError(e))
          }
        }
        Error(e) -> Error(Unauthorized("Insufficient Capabilities: " <> e))
      }
    }
    Error(_) -> Error(Unauthorized("Invalid Capability Token Format"))
  }
}

pub fn authorize_and_query(
  db: Db,
  token_str: String,
  query_ast: List(ast.BodyClause),
  required_caps: List(auth.Capability),
) -> Result(aarondb.QueryResult, GatewayError) {
  case auth.decode_token(token_str) {
    Ok(token) -> {
      case auth.authorize(token, required_caps) {
        Ok(Nil) -> {
          // In AaronDB, query errors are handled gracefully, but query returns raw Result
          Ok(aarondb.query(db, query_ast))
        }
        Error(e) -> Error(Unauthorized("Insufficient Capabilities: " <> e))
      }
    }
    Error(_) -> Error(Unauthorized("Invalid Capability Token Format"))
  }
}
