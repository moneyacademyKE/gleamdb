//// # mcp/server — Model Context Protocol entry point
////
//// JSON-RPC MCP server: `handle_request/2` dispatches tool calls through the
//// `gateway` (which enforces `auth`) and the `rag` semantic-intent layer.
//// `start/1` exposes a typed actor for request/response integration.

import aarondb.{type Db}
import aarondb/auth
import aarondb/fact
import aarondb/gateway
import aarondb/mcp/tools
import aarondb/rag
import aarondb/shared/query_types
import gleam/bit_array
import gleam/dict
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/result
import gleam/string

pub type JsonRpcRequest {
  JsonRpcRequest(
    jsonrpc: String,
    id: Option(String),
    method: String,
    params: Option(json.Json),
  )
}

pub type JsonRpcResponse {
  JsonRpcResponse(
    jsonrpc: String,
    id: Option(String),
    result: Option(json.Json),
    error: Option(JsonRpcError),
  )
}

pub type JsonRpcError {
  JsonRpcError(code: Int, message: String, data: Option(json.Json))
}

pub type ServerMessage {
  Request(JsonRpcRequest, process.Subject(JsonRpcResponse))
  Stop
}

// Convert a JSON-RPC response to a JSON line and write it to stdout.
pub fn send_response(response: JsonRpcResponse) {
  response_to_json(response) |> json.to_string() |> io.println()
}

fn response_to_json(response: JsonRpcResponse) -> json.Json {
  json.object([
    #("jsonrpc", json.string(response.jsonrpc)),
    #("id", json.nullable(response.id, json.string)),
    #("result", json.nullable(response.result, fn(x) { x })),
    #(
      "error",
      json.nullable(response.error, fn(e) {
        json.object([
          #("code", json.int(e.code)),
          #("message", json.string(e.message)),
          #("data", json.nullable(e.data, fn(x) { x })),
        ])
      }),
    ),
  ])
}

// Dispatch the supported tool set. Other registry entries are advertised as
// metadata only until their database semantics exist.
pub fn execute_tool(
  db: Db,
  name: String,
  args: decode.Dynamic,
) -> Result(json.Json, String) {
  case name {
    "muninn_remember" -> handle_remember(db, args)
    "muninn_recall" -> handle_recall(db, args)
    "muninn_read" -> handle_read(db, args)
    _ -> Error("Unsupported MCP tool in AaronDB: " <> name)
  }
}

fn handle_remember(db: Db, args: decode.Dynamic) -> Result(json.Json, String) {
  let decoder = {
    use content <- decode.field("content", decode.string)
    use concept <- decode.optional_field(
      "concept",
      None,
      decode.optional(decode.string),
    )
    use confidence <- decode.optional_field(
      "confidence",
      None,
      decode.optional(decode.float),
    )
    use capability_token <- decode.field("capability_token", decode.string)
    decode.success(#(content, concept, confidence, capability_token))
  }

  case decode.run(args, decoder) {
    Ok(#(content, concept, confidence, capability_token)) -> {
      let id = fact.phash2(content)
      let concept_str = option.unwrap(concept, "unclassified")
      let conf_val = option.unwrap(confidence, 1.0)

      let facts = [
        #(fact.uid(id), "engram/content", fact.Str(content)),
        #(fact.uid(id), "engram/concept", fact.Str(concept_str)),
        #(fact.uid(id), "engram/context", fact.Str(concept_str)),
        #(fact.uid(id), "engram/relevance", fact.Float(conf_val)),
      ]

      let required_caps = [auth.Capability(auth.Write, auth.All)]
      case
        gateway.authorize_and_transact(
          db,
          capability_token,
          facts,
          required_caps,
        )
      {
        Ok(_) -> Ok(json.object([#("id", json.int(id))]))
        Error(gateway.Unauthorized(e)) -> Error("Unauthorized: " <> e)
        Error(gateway.TransactError(e)) -> Error("Transaction failed: " <> e)
        Error(gateway.QueryError(e)) -> Error("Query failed: " <> e)
      }
    }
    Error(e) -> Error("Invalid params: " <> string.inspect(e))
  }
}

fn handle_recall(db: Db, args: decode.Dynamic) -> Result(json.Json, String) {
  let decoder = {
    use contexts <- decode.field("context", decode.list(decode.string))
    use capability_token <- decode.field("capability_token", decode.string)
    decode.success(#(contexts, capability_token))
  }

  case decode.run(args, decoder) {
    Ok(#(contexts, capability_token)) -> {
      let ctx_str = result.unwrap(list.first(contexts), "unclassified")
      let intent = rag.ConceptRecall(ctx_str, 0.5, 10)
      let query_ast = rag.build_query(intent)
      let required_caps = [auth.Capability(auth.Read, auth.All)]

      case
        gateway.authorize_and_query(
          db,
          capability_token,
          query_ast.where,
          required_caps,
        )
      {
        Ok(results) -> Ok(json.array(results.rows, row_to_json))
        Error(gateway.Unauthorized(e)) -> Error("Unauthorized: " <> e)
        Error(gateway.TransactError(e)) -> Error("Transaction failed: " <> e)
        Error(gateway.QueryError(e)) -> Error("Query failed: " <> e)
      }
    }
    Error(e) -> Error("Invalid params: " <> string.inspect(e))
  }
}

fn handle_read(db: Db, args: decode.Dynamic) -> Result(json.Json, String) {
  let decoder = {
    use id <- decode.field("id", decode.int)
    use capability_token <- decode.field("capability_token", decode.string)
    decode.success(#(id, capability_token))
  }
  case decode.run(args, decoder) {
    Ok(#(id, capability_token)) -> {
      case auth.decode_token(capability_token) {
        Ok(token) -> {
          case auth.authorize(token, [auth.Capability(auth.Read, auth.All)]) {
            Ok(Nil) -> {
              Ok(
                json.object([
                  #("id", json.int(id)),
                  #(
                    "engram",
                    pull_result_to_json(aarondb.pull(
                      db,
                      fact.uid(id),
                      aarondb.pull_all(),
                    )),
                  ),
                ]),
              )
            }
            Error(e) -> Error("Unauthorized: " <> e)
          }
        }
        Error(_) -> Error("Unauthorized: Invalid token format")
      }
    }
    Error(e) -> Error("Invalid params: " <> string.inspect(e))
  }
}

pub fn handle_request(db: Db, req: JsonRpcRequest) -> JsonRpcResponse {
  case req.method {
    "tools/list" -> {
      let result =
        json.object([
          #(
            "tools",
            tools.precompiled_array(
              list.map(tools.all_tools(), fn(t: tools.Tool) {
                json.object([
                  #("name", json.string(t.name)),
                  #("description", json.string(t.description)),
                  #("inputSchema", t.input_schema),
                ])
              }),
            ),
          ),
        ])
      JsonRpcResponse("2.0", req.id, Some(result), None)
    }
    "tools/call" -> {
      case req.params {
        Some(params) -> {
          let call_decoder = {
            use name <- decode.field("name", decode.string)
            use arguments <- decode.field("arguments", decode.dynamic)
            decode.success(#(name, arguments))
          }

          case json.parse(json.to_string(params), call_decoder) {
            Ok(#(name, args)) -> {
              case execute_tool(db, name, args) {
                Ok(res) -> JsonRpcResponse("2.0", req.id, Some(res), None)
                Error(e) ->
                  JsonRpcResponse(
                    "2.0",
                    req.id,
                    None,
                    Some(JsonRpcError(-32_000, e, None)),
                  )
              }
            }
            Error(_) ->
              JsonRpcResponse(
                "2.0",
                req.id,
                None,
                Some(JsonRpcError(-32_602, "Invalid tool call params", None)),
              )
          }
        }
        None ->
          JsonRpcResponse(
            "2.0",
            req.id,
            None,
            Some(JsonRpcError(-32_602, "Missing params", None)),
          )
      }
    }
    _ -> {
      JsonRpcResponse(
        "2.0",
        req.id,
        None,
        Some(JsonRpcError(-32_601, "Method not found", None)),
      )
    }
  }
}

fn value_to_json(value: fact.Value) -> json.Json {
  case value {
    fact.Str(value) -> json.string(value)
    fact.Int(value) -> json.int(value)
    fact.Float(value) -> json.float(value)
    fact.Bool(value) -> json.bool(value)
    fact.List(values) -> json.array(values, value_to_json)
    fact.Vec(values) -> json.array(values, json.float)
    fact.Ref(fact.EntityId(id)) -> json.object([#("ref", json.int(id))])
    fact.Map(values) ->
      json.object(
        dict.to_list(values)
        |> list.map(fn(pair) {
          let #(key, value) = pair
          #(key, value_to_json(value))
        }),
      )
    fact.Blob(value) ->
      json.object([
        #("blob_base64", json.string(bit_array.base64_encode(value, True))),
      ])
  }
}

fn pull_result_to_json(value: query_types.PullResult) -> json.Json {
  case value {
    query_types.PullMap(values) ->
      json.object(
        dict.to_list(values)
        |> list.map(fn(pair) {
          let #(key, value) = pair
          #(key, pull_result_to_json(value))
        }),
      )
    query_types.PullSingle(value) -> value_to_json(value)
    query_types.PullMany(values) -> json.array(values, value_to_json)
    query_types.PullNestedMany(values) ->
      json.array(values, pull_result_to_json)
    query_types.PullRawBinary(value) ->
      json.object([
        #("blob_base64", json.string(bit_array.base64_encode(value, True))),
      ])
  }
}

fn row_to_json(row: dict.Dict(String, fact.Value)) -> json.Json {
  json.object(
    dict.to_list(row)
    |> list.map(fn(pair) {
      let #(key, value) = pair
      #(key, value_to_json(value))
    }),
  )
}

/// Start the MCP request actor and return its typed message subject.
pub fn start(
  db: Db,
) -> Result(process.Subject(ServerMessage), actor.StartError) {
  actor.new(db)
  |> actor.on_message(fn(current_db, message) {
    case message {
      Request(request, reply) -> {
        process.send(reply, handle_request(current_db, request))
        actor.continue(current_db)
      }
      Stop -> actor.stop()
    }
  })
  |> actor.start()
  |> result.map(fn(started) { started.data })
}
