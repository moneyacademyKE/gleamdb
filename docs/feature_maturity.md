# Feature Maturity

This document separates implemented capability from vision. The goal is to keep adoption decisions tied to the strongest, most testable parts of the codebase.

## Levels

- Stable: core API is coherent, tested, and aligns with repository reality.
- Beta: implemented and useful, but still carries boundary or operational risk.
- Experimental: promising or partially implemented, but not yet a strong contract.

## Matrix

| Feature Area | Level | Evidence | Main Risk |
| --- | --- | --- | --- |
| Core transactor and DB state | Stable | `src/aarondb.gleam`, `src/aarondb/transactor.gleam`, broad tests | Core orchestration files are still moderately large |
| Fact and datom model | Stable | `src/aarondb/fact.gleam` | None beyond normal API evolution |
| Query DSL and query execution | Stable | `src/aarondb/q.gleam`, planner/executor/solver modules, direct tests | Solver dispatch remains the densest remaining core logic |
| Pull, history, diff, with_facts | Stable | Public API plus dedicated tests | Pull and query behavior share a large execution surface |
| Schema constraints | Stable | Uniqueness, cardinality, check, composite validation in transactor | Validation cost may grow with data size |
| Temporal querying | Beta | `query_at`, valid-time fields, temporal tests | Temporal semantics are coupled to general engine execution |
| Graph algorithms | Beta | Query DSL support and tests | Execution complexity and planner boundaries |
| Vector and BM25 search | Beta | Separate modules and tests | Hybrid retrieval story is broader than current interfaces |
| Federation and virtual predicates | Beta | AST and tests exist | Operational contracts are still thin |
| Reactive subscriptions and WAL-style hooks | Beta | Reactive module and tests | Behavior depends on actor interactions and timing |
| Sharding | Beta | `src/aarondb/sharded.gleam`, tests | Distributed query path is still scatter/gather full scan; cross-shard average/median are approximate (avg-of-averages / median-of-medians); migration helper returns an explicit not-implemented error |
| Raft / HA | Inactive stub | Pure election-only state machine in `src/aarondb/raft.gleam` | Deliberately dormant; no log replication, transport, or runtime integration |
| MCP server | Beta | Three real tools (remember, recall, read) with JSON serialization and a typed actor entry point in `src/aarondb/mcp/server.gleam` | No production transport (stdio/network) yet; auth tokens are decoded but not signature-verified |
| Cognitive memory layer | Experimental | Pure `erf`/`scoring` modules are unit-tested (`cognitive_test.gleam`); engine has its own working `Cognitive` clause solver | The pure modules are not yet integrated with the engine solver — decide integration vs removal |

## Adoption Guidance

Use the stable set when evaluating AaronDB as infrastructure:

- `aarondb`
- `aarondb/fact`
- `aarondb/q`
- basic temporal APIs
- pull/history/diff/speculation

Treat these as opt-in extensions requiring deeper code review and operational testing:

- sharding
- MCP tooling
- cognitive features
- CMS modules
- HA and distributed coordination claims
