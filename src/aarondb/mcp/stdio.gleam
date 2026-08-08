//// # mcp/stdio — local MCP stdio transport
////
//// Runs the supported MCP surface as newline-delimited JSON-RPC over stdin and
//// stdout. stdout carries protocol responses only; diagnostics use stderr.

import aarondb.{type Db, new}
import aarondb/mcp/server
import gleam/dynamic/decode
import gleam/io
import gleam/json
import gleam/option.{None, Some}

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
      case parse_request(line) {
        Ok(request) ->
          server.handle_request(db, request) |> server.send_response
        Error(_) -> malformed_request() |> server.send_response
      }
      serve_loop(db)
    }
    Error(_) -> Nil
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
