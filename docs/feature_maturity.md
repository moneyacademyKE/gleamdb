# Feature Maturity

This document separates implemented capability from vision. The supported deployment boundary and explicit non-goals are defined in [ADR 0002](adr/0002-embedded-local-mcp-boundary.md). The concrete evidence gates for search, graph analytics, and federation are maintained in the [roadmap](roadmap_vnext.md).

## Levels

- Stable: the public contract has committed correctness, lifecycle, resource, reproducible local benchmark, and CI regression evidence.
- Beta: implemented and useful, but one or more Stable evidence gates remain incomplete.
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
| Graph analytics | Stable (local bounded API) | Directed contract, canonical/budget tests, benchmark fixtures, and CI evidence job | Legacy unbounded compatibility APIs remain available |
| Vector search | Stable (local approximate API) | Deterministic HNSW config, exact oracle, recall/churn tests, benchmark report, and CI evidence job | HNSW remains approximate; evidence is a stated local envelope, not a universal SLA |
| BM25 search | Stable (local caller-owned primitive) | Analyzer v1, golden/rebuild tests, benchmark report, and CI evidence job | No transactor integration, persistence, or concurrent mutation contract |
| Local federation | Stable (local fail-fast reads) | Named-source execution, provenance, typed failure tests, soak benchmark, and CI evidence job | No cross-source snapshot, partial results, or coordinated writes |
| Virtual predicates | Experimental | AST and tests exist | External adapter operational contract is separate from local federation |
| Reactive subscriptions and WAL-style hooks | Beta | Reactive module and tests | Behavior depends on actor interactions and timing |
| Sharding | Beta | `src/aarondb/sharded.gleam`, tests | Local scatter/gather only; cross-shard average/median are approximate and migration is explicitly unsupported |
| Raft / HA | Inactive stub | Pure election-only state machine in `src/aarondb/raft.gleam` | No log replication, transport, or runtime integration; explicitly outside the supported boundary |
| MCP server | Beta | Local stdio JSON-RPC adapter, three tools, JSON serialization, typed actor | Local child-process transport only; no network listener |
| Capability authorization | Local-only | `src/aarondb/auth.gleam`, gateway tests | JSON capabilities are not signed credentials; no network authentication claim |
| Mnesia persistence | Recovery-oriented | Adapter plus recovery test coverage | No production multi-node/failure contract |
| Cognitive memory layer | Beta | `engine/cognitive.gleam` implements the tested `Cognitive` clause solver | Relevance is currently explicit stored data (`engram/relevance`); no adaptive learning or decay model is claimed |

## Supported local contracts

- **Vector:** in-memory approximate cosine HNSW; deterministic test mode and a measured local benchmark envelope. See [Vector Search Contract](manual/vector_search.md).
- **BM25:** immutable, in-memory, sequential, caller-owned local primitive. See [BM25 Search Contract](manual/bm25_search.md).
- **Graph:** directed local analytics; new callers use bounded traversal/global APIs. Legacy APIs remain unbounded compatibility paths. See [Graph Query Contract](manual/graph_queries.md).
- **Federation:** named local actor reads, deterministic source ordering and provenance, and fail-fast typed failures. See [Local Federation](manual/local_federation.md).

These Stable labels do **not** imply remote federation, HA, replication, migration, quorum, coordinated writes, global snapshots, or universal performance guarantees.

## Adoption Guidance

Use the stable set when evaluating AaronDB as infrastructure:

- `aarondb`
- `aarondb/fact`
- `aarondb/q`
- basic temporal APIs
- pull/history/diff/speculation
- the four explicitly local contracts above

Treat these as opt-in extensions requiring deeper code review and operational testing:

- sharding
- MCP tooling
- cognitive features
- HA and distributed coordination claims

For deployment, auth, persistence, and extension constraints, follow [ADR 0002](adr/0002-embedded-local-mcp-boundary.md).
