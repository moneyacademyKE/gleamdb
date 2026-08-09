//// # mcp/stdio — local MCP stdio transport
////
//// Runs the supported MCP surface as newline-delimited JSON-RPC over stdin and
//// stdout. stdout carries protocol responses only; diagnostics use stderr.
////
//// ## Lifecycle and flow control
////
//// This is a local child-process adapter. It accepts one complete line, handles
//// it synchronously, writes at most one response, then reads the next line.
//// There is no request queue, concurrent execution, or partial-result mode: a
//// slow tool call applies backpressure through stdin. EOF is the supported
//// shutdown signal. `notifications/initialized` and
//// `notifications/cancelled` are accepted notifications and deliberately write
//// no response. Cancellation cannot interrupt an already-running synchronous
//// call; hosts should stop the child process if they need hard cancellation.

import aarondb.{type Db, new}
import aarondb/mcp/server
import gleam/dynamic/decode
import gleam/io
import gleam/json
import gleam/option.{type Option, None, Some}

/// Start a local MCP server with a fresh in-memory AaronDB instance.
pub fn main() {
  new() |> serve
}

/// Serve one JSON-RPC request per stdin line until EOF.
pub fn serve(db: Db) {
  io.println_error("AaronDB local MCP stdio server started")
  serve_loop(db)
}

fn serve_loop(db: Db) {
  case get_line("") {
    Ok(line) -> {
      case serve_line(db, line) {
        Some(response) -> server.send_response(response)
        None -> Nil
      }
      serve_loop(db)
    }
    Error(_) -> Nil
  }
}

/// Decode and synchronously handle one stdin line.
///
/// A request produces `Some(response)`. JSON-RPC notifications intentionally
/// produce `None`, including malformed notifications only when they cannot be
/// identified as notifications.
pub fn serve_line(db: Db, line: String) -> Option(server.JsonRpcResponse) {
  case parse_request(line) {
    Ok(request) -> {
      case request.id {
        None -> {
          let _ = server.handle_request(db, request)
          None
        }
        Some(_) -> Some(server.handle_request(db, request))
      }
    }
    Error(_) -> Some(malformed_request())
  }
}

@external(erlang, "aarondb_mcp_stdio_ffi", "get_line")
fn get_line(prompt: String) -> Result(String, Nil)

fn malformed_request() -> server.JsonRpcResponse {
  server.JsonRpcResponse(
    "2.0",
    None,
    None,
    Some(server.JsonRpcError(-32_700, "Parse error", None)),
  )
}

pub fn parse_request(
  line: String,
) -> Result(server.JsonRpcRequest, json.DecodeError) {
  let request_decoder = {
    use jsonrpc <- decode.field("jsonrpc", decode.string)
    use id <- decode.optional_field("id", None, decode.optional(decode.string))
    use method <- decode.field("method", decode.string)
    use params <- decode.optional_field(
      "params",
      None,
      decode.optional(decode.dynamic),
    )
    decode.success(server.JsonRpcRequest(jsonrpc, id, method, params))
  }

  json.parse(line, request_decoder)
}
