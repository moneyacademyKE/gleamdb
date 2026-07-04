import aarondb/auth.{Admin, All, Capability, Database, Read, Shard, Token, Write}
import gleeunit/should

pub fn authorize_exact_match_test() {
  let token = Token("t1", [Capability(Read, Shard(1))], "iss")
  let required = [Capability(Read, Shard(1))]

  auth.authorize(token, required)
  |> should.be_ok
}

pub fn authorize_subsumes_action_test() {
  let token = Token("t1", [Capability(Admin, Database("main"))], "iss")

  // Admin on Database should subsume Write on Shard within that Database
  let required = [Capability(Write, Shard(1))]

  auth.authorize(token, required)
  |> should.be_ok
}

pub fn authorize_subsumes_resource_test() {
  let token = Token("t1", [Capability(Read, All)], "iss")
  let required = [Capability(Read, Shard(42))]

  auth.authorize(token, required)
  |> should.be_ok
}

pub fn authorize_fails_insufficient_resource_test() {
  let token = Token("t1", [Capability(Read, Shard(1))], "iss")
  let required = [Capability(Read, All)]

  auth.authorize(token, required)
  |> should.be_error
}

pub fn authorize_fails_insufficient_action_test() {
  let token = Token("t1", [Capability(Read, Shard(1))], "iss")
  let required = [Capability(Write, Shard(1))]

  auth.authorize(token, required)
  |> should.be_error
}

pub fn decode_token_test() {
  let payload =
    "{
    \"id\": \"123\",
    \"iss\": \"admin\",
    \"caps\": [
      {\"op\": \"read\", \"res\": \"all\"},
      {\"op\": \"write\", \"res\": \"shard:42\"}
    ]
  }"

  let assert Ok(token) = auth.decode_token(payload)

  token.id |> should.equal("123")
  token.issuer |> should.equal("admin")
  token.capabilities
  |> should.equal([
    Capability(Read, All),
    Capability(Write, Shard(42)),
  ])
}
