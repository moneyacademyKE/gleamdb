# Embedded Core Module Boundaries

`embedded-core-v1` is a **structural certification profile**, not a claim that every repository module is pure.

| Layer | Responsibility | May depend on |
|---|---|---|
| Pure core | Facts, AST/query construction, deterministic command/Raft models, vector oracle/validation, sharding semantics | Data modules and Gleam standard-library modules only |
| Runtime adapter | Actors, process subjects, storage, transport, MCP, distribution, compatibility entry points | Pure core plus runtime services |

The executable manifest is `docs/certification/module-boundaries.edn`. The verifier rejects a pure module importing any of:

- `gleam/erlang/process` or `gleam/otp`
- `aarondb/storage*`, `aarondb/transactor*`
- `aarondb/cluster_*`, `aarondb/distributed_*`, or `aarondb/mcp/*`

Run the complete certification gate with `sh scripts/verify_embedded_core_v1.sh`. It runs the boundary checker and its approved/forbidden fixture regression before formatting, type checking, documentation generation, the test suite, and diff hygiene.

`aarondb/shared/ownership` is the explicit projection of the public `DbState`
record. It separates deterministic facts, derived indexes, runtime handles,
optional extensions, and operational state without a single breaking rewrite.
See [DbState ownership](dbstate-ownership.md) and the final
[certification evidence](../reviews/rich-hickey-certification-evidence-2026-08-11.md).
