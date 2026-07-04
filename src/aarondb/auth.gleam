import gleam/json
import gleam/list
import gleam/string

/// Rich Hickey 🧙🏾‍♂️:
/// Identity is who you are. Authority is what you can do.
/// Capability-based security completely decomplects Identity from Authority.
/// This module implements an attenuable token verification layer.
pub type Action {
  Read
  Write
  Admin
}

pub type Resource {
  All
  Shard(Int)
  Database(String)
}

pub type Capability {
  Capability(action: Action, resource: Resource)
}

pub type Token {
  Token(id: String, capabilities: List(Capability), issuer: String)
}

/// Verifies if a given Token satisfies a list of required capabilities.
/// Time Complexity: O(R * P) where R is required caps, P is provided caps.
/// Space Complexity: O(1) auxiliary space.
pub fn authorize(
  token: Token,
  required: List(Capability),
) -> Result(Nil, String) {
  // All required capabilities must be satisfied by at least one provided capability.
  let is_authorized =
    list.all(required, fn(req: Capability) {
      list.any(token.capabilities, fn(prov: Capability) { subsumes(prov, req) })
    })

  case is_authorized {
    True -> Ok(Nil)
    False -> Error("Unauthorized: Insufficient capabilities in token.")
  }
}

/// Rich Hickey 🧙🏾‍♂️:
/// Subsumption is a logical property. A broader capability subsumes a narrower one.
/// e.g. Read(All) subsumes Read(Shard(1)).
fn subsumes(provided: Capability, required: Capability) -> Bool {
  case provided.action, required.action {
    // Admin action sweeps all other actions on the same resource
    Admin, _ -> subsumes_resource(provided.resource, required.resource)
    // Same actions delegate to resource subsumption
    p_act, r_act if p_act == r_act ->
      subsumes_resource(provided.resource, required.resource)
    // Otherwise fail
    _, _ -> False
  }
}

fn subsumes_resource(provided: Resource, required: Resource) -> Bool {
  case provided, required {
    All, _ -> True
    Database(p), Database(r) if p == r -> True
    // A database scope subsumes a shard scope within it (simplified for now)
    Database(_), Shard(_) -> True
    Shard(p), Shard(r) if p == r -> True
    _, _ -> False
  }
}

import gleam/dynamic/decode
import gleam/int

type RawCap {
  RawCap(op: String, res: String)
}

type RawToken {
  RawToken(id: String, caps: List(RawCap), iss: String)
}

/// Example simple parser from a JSON-like token format.
/// In a real UCAN, you'd verify proper base64 + EdDSA signatures here.
pub fn decode_token(payload: String) -> Result(Token, json.DecodeError) {
  let cap_decoder = {
    use op <- decode.field("op", decode.string)
    use res <- decode.field("res", decode.string)
    decode.success(RawCap(op, res))
  }

  let token_decoder = {
    use id <- decode.field("id", decode.string)
    use caps <- decode.field("caps", decode.list(cap_decoder))
    use iss <- decode.field("iss", decode.string)
    decode.success(RawToken(id, caps, iss))
  }

  case json.parse(payload, token_decoder) {
    Ok(raw) -> {
      let caps =
        list.filter_map(raw.caps, fn(c) {
          let action = case c.op {
            "read" -> Ok(Read)
            "write" -> Ok(Write)
            "admin" -> Ok(Admin)
            _ -> Error(Nil)
          }

          let resource = case c.res {
            "all" -> Ok(All)
            s ->
              case string.starts_with(s, "shard:") {
                True -> {
                  let num_str = string.replace(s, "shard:", "")
                  case int.parse(num_str) {
                    Ok(n) -> Ok(Shard(n))
                    Error(_) -> Error(Nil)
                  }
                }
                False ->
                  case string.starts_with(s, "db:") {
                    True -> Ok(Database(string.replace(s, "db:", "")))
                    False -> Error(Nil)
                  }
              }
          }

          case action, resource {
            Ok(a), Ok(r) -> Ok(Capability(a, r))
            _, _ -> Error(Nil)
          }
        })

      Ok(Token(raw.id, caps, raw.iss))
    }
    Error(e) -> Error(e)
  }
}
