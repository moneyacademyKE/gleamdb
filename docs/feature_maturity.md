# Feature Maturity

This document separates implemented capability from vision. The goal is to keep adoption decisions tied to the strongest, most testable parts of the codebase.

## Levels

- Stable: core API is coherent, tested, and aligns with repository reality.
- Beta: implemented and useful, but still carries boundary or operational risk.
- Experimental: promising or partially implemented, but not yet a strong contract.

## Matrix

| Feature Area | Level | Evidence | Main Risk |
| --- | --- | --- | --- |
| Core transactor and DB state | Stable | `src/aarondb.gleam`, `src/aarondb/transactor.gleam`, broad tests | Large core modules raise change risk |
| Fact and datom model | Stable | `src/aarondb/fact.gleam` | None beyond normal API evolution |
| Query DSL and query execution | Stable | `src/aarondb/q.gleam`, `src/aarondb/engine.gleam` | Engine complexity is concentrated in one file |
| Pull, history, diff, with_facts | Stable | Public API plus dedicated tests | Pull and query behavior share a large execution surface |
| Schema constraints | Stable | Uniqueness, cardinality, check, composite validation in transactor | Validation cost may grow with data size |
| Temporal querying | Beta | `query_at`, valid-time fields, temporal tests | Temporal semantics are coupled to general engine execution |
| Graph algorithms | Beta | Query DSL support and tests | Execution complexity and planner boundaries |
| Vector and BM25 search | Beta | Separate modules and tests | Hybrid retrieval story is broader than current interfaces |
| Federation and virtual predicates | Beta | AST and tests exist | Operational contracts are still thin |
| Reactive subscriptions and WAL-style hooks | Beta | Reactive module and tests | Behavior depends on actor interactions and timing |
| Sharding | Beta/Experimental | `src/aarondb/sharded.gleam`, tests | Distributed query path is still scatter/gather full scan |
| Raft / HA | Experimental | Pure election state machine in `src/aarondb/raft.gleam` | Not a full replicated-log consensus implementation |
| MCP server | Experimental | Partial handlers in `src/aarondb/mcp/server.gleam` | Tool coverage and protocol output remain incomplete |
| Cognitive memory layer | Experimental | Query surface exists | Documentation and claims outrun the most bounded implementation |
| GleamCMS | Experimental | Separate app subtree exists | Product concerns are mixed into the DB repository |

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
