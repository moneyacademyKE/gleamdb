import aarondb.{type Db}
import aarondb/auth
import aarondb/fact.{Float, Str}
import aarondb/gateway
import aarondb/mcp/tools
import aarondb/rag
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
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

// Convert a JSON object to string and print to stdout
pub fn send_response(response: JsonRpcResponse) {
  let json_str =
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
    |> json.to_string()

  // In a real stdio MCP server, we would print this to stdout with a Content-Length header
  // For now, we print it directly.
  let _ = string.inspect(json_str)
  Nil
}

// Map the tool name to a Datalog query or transaction
pub fn execute_tool(
  db: Db,
  name: String,
  args: decode.Dynamic,
) -> Result(json.Json, String) {
  case name {
    "muninn_remember" -> handle_remember(db, args)
    "muninn_recall" -> handle_recall(db, args)
    "muninn_read" -> handle_read(db, args)
    _ -> Error("Tool not implemented yet in AaronDB: " <> name)
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
        #(fact.uid(id), "engram/content", Str(content)),
        #(fact.uid(id), "engram/concept", Str(concept_str)),
        #(fact.uid(id), "engram/relevance", Float(conf_val)),
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
        Ok(results) ->
          Ok(
            json.array(results.rows, fn(_) {
              json.string("TODO: format engram")
            }),
          )
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
              let _engram = aarondb.pull(db, fact.uid(id), aarondb.pull_all())
              Ok(json.string("TODO: PullResult to JSON"))
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

pub fn start(_db: Db) {
  process.sleep_forever()
}
