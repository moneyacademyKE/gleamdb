import aarondb
import aarondb/auth
import aarondb/mcp/server
import gleam/dynamic/decode
import gleam/json
import gleeunit/should

pub fn mcp_security_test() {
  // Setup an in-memory database
  let db = aarondb.new()

  // Generate a valid capability token with Write access but no Read access
  let _valid_write_token =
    auth.Token(
      id: "test-token-write",
      capabilities: [auth.Capability(auth.Write, auth.All)],
      issuer: "system",
    )
  let write_token_str =
    "{\"id\":\"test-token-write\",\"caps\":[{\"op\":\"write\",\"res\":\"all\"}],\"iss\":\"system\"}"

  // Generate a valid capability token with Read access but no Write access  
  let read_token_str =
    "{\"id\":\"test-token-read\",\"caps\":[{\"op\":\"read\",\"res\":\"all\"}],\"iss\":\"system\"}"

  // Create an invalid token format
  let invalid_token_str = "not-a-token"

  // 1. Test muninn_remember (Requires Write) with invalid token
  let remember_invalid_args =
    json.object([
      #("content", json.string("MCP security test")),
      #("capability_token", json.string(invalid_token_str)),
    ])

  let invalid_req =
    json.parse(json.to_string(remember_invalid_args), decode.dynamic) |> unwrap
  let res1 = server.execute_tool(db, "muninn_remember", invalid_req)
  should.be_error(res1)

  // 2. Test muninn_remember (Requires Write) with missing capability (using read token)
  let remember_no_cap_args =
    json.object([
      #("content", json.string("MCP security test")),
      #("capability_token", json.string(read_token_str)),
    ])

  let no_cap_req =
    json.parse(json.to_string(remember_no_cap_args), decode.dynamic) |> unwrap
  let res2 = server.execute_tool(db, "muninn_remember", no_cap_req)
  should.be_error(res2)

  // 3. Test muninn_remember (Requires Write) with valid token
  let remember_valid_args =
    json.object([
      #("content", json.string("MCP security test")),
      #("capability_token", json.string(write_token_str)),
    ])

  let valid_req =
    json.parse(json.to_string(remember_valid_args), decode.dynamic) |> unwrap
  let res3 = server.execute_tool(db, "muninn_remember", valid_req)
  should.be_ok(res3)

  // 4. Test muninn_recall (Requires Read) with write token (missing read cap)
  let recall_no_cap_args =
    json.object([
      #("context", json.array([json.string("security")], of: fn(x) { x })),
      #("capability_token", json.string(write_token_str)),
    ])

  let recall_req_no_cap =
    json.parse(json.to_string(recall_no_cap_args), decode.dynamic) |> unwrap
  let res4 = server.execute_tool(db, "muninn_recall", recall_req_no_cap)
  should.be_error(res4)

  // 5. Test muninn_recall (Requires Read) with valid read token
  let recall_valid_args =
    json.object([
      #("context", json.array([json.string("security")], of: fn(x) { x })),
      #("capability_token", json.string(read_token_str)),
    ])
  let recall_valid_req =
    json.parse(json.to_string(recall_valid_args), decode.dynamic) |> unwrap
  let res5 = server.execute_tool(db, "muninn_recall", recall_valid_req)
  should.be_ok(res5)
}

fn unwrap(res) {
  case res {
    Ok(v) -> v
    Error(_) -> panic as "Unwrap failed in test"
  }
}
