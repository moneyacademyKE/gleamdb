import aarondb
import aarondb/mcp/server
import aarondb/mcp/stdio
import gleam/dynamic/decode
import gleam/json
import gleam/option.{None, Some}
import gleeunit/should

pub fn stdio_parses_initialize_request_test() {
  let assert Ok(request) =
    stdio.parse_request(
      "{\"jsonrpc\":\"2.0\",\"id\":\"init-1\",\"method\":\"initialize\",\"params\":{}}",
    )

  request.jsonrpc |> should.equal("2.0")
  request.id |> should.equal(Some("init-1"))
  request.method |> should.equal("initialize")
}

pub fn stdio_rejects_malformed_json_test() {
  stdio.parse_request("{") |> should.be_error
}

pub fn initialize_returns_mcp_capabilities_test() {
  let db = aarondb.new()
  let response =
    server.handle_request(
      db,
      server.JsonRpcRequest("2.0", Some("init-1"), "initialize", None),
    )

  let assert Some(result) = response.result
  let decoded = json.parse(json.to_string(result), decode.dynamic)
  decoded |> should.be_ok
  response.error |> should.equal(None)
}

pub fn non_jsonrpc_2_request_is_rejected_test() {
  let db = aarondb.new()
  let response =
    server.handle_request(
      db,
      server.JsonRpcRequest("1.0", Some("old"), "tools/list", None),
    )

  let assert Some(error) = response.error
  error.code |> should.equal(-32_600)
}
