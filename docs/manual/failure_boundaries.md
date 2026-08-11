# Failure and Trust Boundaries

AaronDB's supported deployment is an embedded database and local stdio MCP
child process. This page separates ordinary, expected operational failures from
internal implementation invariants so callers know which APIs are total.

## Timeout-aware public APIs

New integrations should use these `Result`-returning APIs when an actor can be
slow, stopped, or unavailable:

- `aarondb.start_link(adapter, timeout_ms)`
- `transactor.get_state_with_timeout(db, timeout_ms)`
- `aarondb.transact_with_timeout(db, facts, timeout_ms)`
- `aarondb.register_function_with_timeout(db, name, function, timeout_ms)`
- `aarondb.register_predicate_with_timeout(db, name, predicate, timeout_ms)`
- `aarondb.set_config_with_timeout(db, config, timeout_ms)`

The older direct-return helpers (`new`, `get_state`, `register_function`,
`register_predicate`, and `set_config`) remain compatibility conveniences.
They use the default deadline and cannot report a timeout. They are not the
supported choice for supervision or fault-aware application code.

## External term and storage data

Erlang external-term bytes are decoded only through `aarondb_term_ffi` using
`binary_to_term(Binary, [safe])`. Malformed payloads and unexpected rule shapes
return `Error`, not a decoded term. Persisted data must still be treated as
trusted local storage: safe decoding prevents new atom creation but cannot make
an attacker-controlled persistence directory trustworthy.

Mnesia and storage adapters return typed startup, schema, and transaction
errors. See [Mnesia Recovery](mnesia_recovery.md) for the supported
single-node recovery boundary.

## Accepted internal invariants

The remaining production assertions are not public trust boundaries:

- Vector logarithm and magnitude operations operate on validated positive
  constants or values constrained by the vector contract.
- Bloom-filter and ART bit-pattern matches follow bounds checks performed in
  the same function.
- Transaction fold assertions follow `fold_until`'s `Ok` accumulator invariant.
- Benchmark executables may assert their fixture setup and measurement shape;
  they are evidence tooling, not library APIs.

Sharding remains Beta and its internal actor lookups are not a supported
fault-tolerant boundary. It must not be used to infer failover or distributed
transaction guarantees.

## Authentication boundary

`auth` is a local capability authorization model. It decodes capability-shaped
JSON but does not verify signatures, expiry, issuer trust, audience, replay, or
key rotation. There is no network listener in the supported product. Do not use
these tokens as network authentication credentials.
