//// # mcp/tools — MCP tool registry
////
//// Tool definitions exposed to MCP clients: `all_tools/0` returns the
//// registry. Pure data over `gleam/json`; no side effects.

import gleam/json
import gleam/list

pub type Tool {
  Tool(
    name: String,
    description: String,
    input_schema: json.Json,
    // Represents the JSON schema as a JSON object
  )
}

pub fn precompiled_array(items: List(json.Json)) -> json.Json {
  json.array(items, of: fn(x) { x })
}

/// Only the three handlers below are executable in this build. The registry also
/// describes a larger Muninn-compatible surface, but advertising unsupported
/// operations would make `tools/list` lie to clients.
pub fn all_tools() -> List(Tool) {
  [
    remember_tool(),
    recall_tool(),
    read_tool(),
  ]
}

fn schema(
  properties: List(#(String, json.Json)),
  required: List(String),
) -> json.Json {
  json.object([
    #("type", json.string("object")),
    #("properties", json.object(properties)),
    #("required", precompiled_array(list.map(required, json.string))),
  ])
}

fn string_property(description: String) -> json.Json {
  json.object([
    #("type", json.string("string")),
    #("description", json.string(description)),
  ])
}

fn number_property(description: String) -> json.Json {
  json.object([
    #("type", json.string("number")),
    #("description", json.string(description)),
  ])
}

fn remember_tool() -> Tool {
  Tool(
    "muninn_remember",
    "Store a memory with optional concept and confidence.",
    schema(
      [
        #("content", string_property("The information to remember.")),
        #("concept", string_property("A concept label.")),
        #("confidence", number_property("Confidence from 0.0 to 1.0.")),
        #("capability_token", string_property("Write capability token.")),
      ],
      ["content", "capability_token"],
    ),
  )
}

fn recall_tool() -> Tool {
  Tool(
    "muninn_recall",
    "Search memories by concept and context.",
    schema(
      [
        #(
          "context",
          json.object([
            #("type", json.string("array")),
            #("items", json.object([#("type", json.string("string"))])),
          ]),
        ),
        #("capability_token", string_property("Read capability token.")),
      ],
      ["context", "capability_token"],
    ),
  )
}

fn read_tool() -> Tool {
  Tool(
    "muninn_read",
    "Fetch a memory by numeric ID.",
    schema(
      [
        #("id", json.object([#("type", json.string("integer"))])),
        #("capability_token", string_property("Read capability token.")),
      ],
      ["id", "capability_token"],
    ),
  )
}
