# AaronDB

[![Hex](https://img.shields.io/hexpm/v/aarondb.svg)](https://hex.pm/packages/aarondb)

AaronDB is a local, embedded Datalog database for the BEAM. Its documented Stable labels are narrow local contracts backed by committed tests, bounded failure behavior where relevant, reproducible harnesses, and CI; see the [evidence index](docs/evidence.md).

> "Simplicity is not about making things easy. It is about untangling complexity." — Rich Hickey

> **Current release line:** v4.2.0 certifies the `embedded-core-v1` structural closure: local Datalog domain models and deterministic algorithms with mechanically enforced pure-to-adapter boundaries. Sharding, distributed/HA, storage/transport, and MCP surfaces remain experimental; see [Feature Maturity](docs/feature_maturity.md), [Project Boundaries](docs/project_boundaries.md), and [the certification profile](docs/certification/embedded-core-v1.json).

AaronDB is a BEAM-native temporal Datalog engine written in Gleam. Its strongest shape is a fact-oriented database core built around a transactor actor, immutable-style state transitions, in-memory indexes, and a custom query engine.

This repository also contains local search, graph analytics, federation, cognitive, sharding, and MCP extensions. Their supported contracts are deliberately narrow; read `docs/feature_maturity.md` and `docs/project_boundaries.md` before adopting non-core features.

## Core Model

1. Facts, not objects: data is represented as datoms.
2. Actor-owned writes: a transactor process serializes state transitions.
3. Query over values: reads execute against database state snapshots.
4. Storage is pluggable: the engine is decoupled from persistence adapters.

## What Is Solid Today

- In-memory transactional core
- Datom model with transaction and valid-time fields
- Query DSL and interpreted query execution
- Pull, history, diff, and speculative state evaluation
- Constraints for uniqueness, cardinality, predicates, and composites
- Local Stable retrieval/analytics contracts with committed regression and benchmark evidence

## Maturity Snapshot

| Area | Status | Notes |
| --- | --- | --- |
| Core DB API (`aarondb`) | Stable | Primary strength of the repository |
| Query DSL and pull APIs | Stable | Backed by passing tests |
| Vector / HNSW | Stable (local approximate) | Deterministic evidence and exact-oracle comparison; no universal SLA |
| BM25 | Stable (local primitive) | Immutable, sequential, caller-owned Analyzer v1 index |
| Graph analytics | Stable (local bounded API) | Directed graph model; bounded APIs are the supported path for arbitrary data |
| Local federation | Stable (local fail-fast reads) | Named in-runtime sources, provenance, typed failure; no partial results |
| Temporal querying and diff | Stable (local bounded API) | Transaction-time, valid-time, and bitemporal snapshots plus deterministic bounded diffs; legacy unbounded APIs are compatibility-only |
| Reactive subscriptions | Stable (local mailbox delivery) | Serialized initial/delta/unsubscribe ordering; consumers own mailbox draining |
| Cognitive memory | Stable (local explicit-fact solver) | Explicit relevance facts with deterministic lifecycle semantics; no learned ranking or external retrieval |
| Virtual predicates | Stable (bounded local adapters) | Typed local adapter results and row bounds; no remote transport or forced interruption |
| Sharding and distributed queries | Local Beta | One-runtime scatter/gather only: no remote membership, failover, transactional migration, or exact global Avg/Median |
| Raft and HA claims | Inactive stub | Pure leader-election state machine exists but is **not wired into the engine** (election-only; no log replication) |
| Mnesia persistence | Recovery-oriented | Initialization preserves incompatible schemas and returns an error; explicit backup/migration/reset is required |
| MCP server and agent tooling | Local Beta | Local stdio JSON-RPC adapter exposes three implemented tools; no network listener or remote authentication |

## Explicitly local means exactly that

The Stable labels above are contracts for one BEAM runtime and stated, reproducible local evidence. They do **not** claim remote federation, replication, high availability, failover, migration, quorum, coordinated writes, global snapshots, distributed graph processing, or universal latency/memory/recall guarantees.

- **Vector:** [cosine HNSW contract](docs/manual/vector_search.md) plus exact oracle, recall/churn regression, and benchmark harness.
- **BM25:** [Analyzer v1 and lifecycle contract](docs/manual/bm25_search.md); no transaction integration, persistence, or concurrent mutation safety.
- **Graph:** [directed bounded analytics contract](docs/manual/graph_queries.md); legacy APIs remain unbounded compatibility paths.
- **Temporal/Diff:** [bounded local snapshot and diff contract](docs/manual/temporal_diff.md), with lifecycle/invariant tests and a reproducible [CI evidence harness](docs/benchmarks/temporal_diff.md); no remote/global snapshots or universal performance claims.
- **Federation:** [local fail-fast read contract](docs/manual/local_federation.md); no cross-source transaction/snapshot, retries, or partial result mode.

## Installation

Add the current release to your `gleam.toml`:

```toml
[dependencies]
aarondb = "4.2"
```

## What 4.2.0 Changes

AaronDB 4.2.0 certifies `embedded-core-v1`: a deliberately bounded structural profile for local Datalog domain data and deterministic algorithms. The profile is executable: it rejects forbidden effectful imports, unapproved pure-module dependencies, malformed certification metadata, and generated/runtime artifacts.

- **Explicit failure boundaries** — `register_composite_with_timeout` and `store_rule_with_timeout` accept caller-owned deadlines. Existing convenience APIs remain compatibility wrappers with their historical five-second deadline.
- **Pure transaction domain** — transaction transformation is separated from persistence and subscriber delivery; ordering and lookup failures have characterization tests.
- **Deterministic vector evidence** — the exact local oracle, validation boundary, and tie ordering are independently testable from the approximate HNSW façade.
- **State and continuation ownership** — state ownership is documented by concern, and retry/fallback/idempotency policy is explicit data rather than invisible control flow.

It does **not** promote sharding, Raft, HA, remote federation, storage/transport, MCP, lifecycle/upgrade/rollback, or broader cluster claims. Those surfaces remain experimental until their own candidate-SHA evidence profiles pass. See [CHANGELOG.md](CHANGELOG.md) for the full release notes.

## Basic Usage

Create an in-memory database:

```gleam
import aarondb

let db = aarondb.new()
```

Transact facts:

```gleam
import aarondb
import aarondb/fact.{EntityId, Str, Uid}

let assert Ok(_state) = aarondb.transact(db, [
  #(Uid(EntityId(101)), "user/name", Str("Alice")),
  #(Uid(EntityId(101)), "user/role", Str("Admin")),
])
```

Query with the DSL:

```gleam
import aarondb
import aarondb/q

let query =
  q.select(["name"])
  |> q.where(q.v("e"), "user/role", q.s("Admin"))
  |> q.where(q.v("e"), "user/name", q.v("name"))
  |> q.to_clauses()

let results = aarondb.query(db, query)
```

Use temporal and pull APIs:

```gleam
import aarondb
import aarondb/fact

let history = aarondb.history(db, fact.Uid(fact.EntityId(101)))
let entity = aarondb.pull(db, fact.Uid(fact.EntityId(101)), aarondb.pull_all())
```

## Documentation

- [Architecture](docs/architecture.md)
- [Feature Maturity](docs/feature_maturity.md)
- [Project Boundaries](docs/project_boundaries.md)
- [Query DSL](docs/manual/query_dsl.md)
- [Local MCP stdio adapter](docs/manual/mcp_stdio.md)
- [Supervision](docs/manual/supervision.md)
- [Vector search contract](docs/manual/vector_search.md)
- [BM25 search contract](docs/manual/bm25_search.md)
- [Graph query contract](docs/manual/graph_queries.md)
- [Local federation contract](docs/manual/local_federation.md)
- [Distributed Guide](docs/distributed_guide.md)

## Current Recommendation

Treat AaronDB first as a temporal Datalog engine with a strong in-memory core. The v4.1 local contracts are ready for their stated use, but distributed features remain deliberately separate work—not marketing adjectives.
