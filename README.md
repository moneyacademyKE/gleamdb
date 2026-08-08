# AaronDB

> "Simplicity is not about making things easy. It is about untangling complexity." - Rich Hickey

> **Current release line:** v4.0.0 hardens persistence, actor timeout, vector, and term-decoding boundaries while formalizing AaronDB as an embedded library with an optional local stdio MCP adapter. See [ADR 0002](docs/adr/0002-embedded-local-mcp-boundary.md).

AaronDB is a BEAM-native temporal Datalog engine written in Gleam. Its strongest current shape is a fact-oriented database core built around a transactor actor, immutable-style state transitions, in-memory indexes, and a custom query engine.

This repository also contains local search, cognitive, sharding, and MCP extensions with deliberately bounded operational contracts. See `docs/feature_maturity.md` and `docs/project_boundaries.md` before adopting non-core features.

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
- Broad automated test coverage

## Maturity Snapshot

| Area | Status | Notes |
| --- | --- | --- |
| Core DB API (`aarondb`) | Stable | Primary strength of the repository |
| Query DSL and pull APIs | Stable | Backed by passing tests |
| Temporal querying and diff | Stable/Beta | Usable, but still tied to large core modules |
| Graph, vector, BM25, federation | Beta | Vector has an explicit HNSW contract; BM25 is a standalone local index with deterministic lifecycle/ranking semantics; graph and federation remain bounded extensions |
| Sharding and distributed queries | Local Beta | One-runtime scatter/gather only: no remote membership, failover, transactional migration, or exact global Avg/Median |
| Raft and HA claims | Inactive stub | Pure leader-election state machine exists but is **not wired into the engine** (election-only; no log replication). Retained as a documented stub. See `src/aarondb/raft.gleam` |
| Mnesia persistence | Recovery-oriented | Initialization preserves incompatible schemas and returns an error; explicit backup/migration/reset is required |
| MCP server and agent tooling | Local Beta | Local stdio JSON-RPC adapter exposes three implemented tools; no network listener or remote authentication |

## Installation

Add the current release to your `gleam.toml`:

```toml
[dependencies]
aarondb = "4.0.0"
```

## What 4.0.0 Changes

AaronDB 4.0.0 is a **breaking hardening release**. It makes previously implicit or unsafe boundary behavior explicit.

- **Safe term decoding** — serialized rules and raw ETS terms now use safe Erlang external-term decoding and reject malformed or wrong-shaped payloads.
- **Truthful actor timeouts** — startup honors the timeout supplied by callers; public actor operations return timeout errors rather than crashing on an unanswered receive.
- **Vector dimension contracts** — HNSW indexes establish one dimension and reject mismatched insert/search vectors; retrieval skips incompatible stored vectors instead of truncating scores.
- **Non-destructive Mnesia startup** — an incompatible `datoms` schema produces an error and preserves persisted data; backup/migration/reset is an explicit operator action.
- **Local MCP is real, but local** — the stdio adapter supports `initialize`, `tools/list`, and the three implemented tools; it is not a network service.
- **Release assurance and package trust** — CI builds docs and lints workflows; the repository now includes Apache-2.0 licensing and a security policy.
- **Distributed limits are explicit** — sharding remains local Beta, Raft remains an inactive stub, and Mnesia remains recovery-oriented.

See [CHANGELOG.md](CHANGELOG.md), [Feature Maturity](docs/feature_maturity.md), and [ADR 0002](docs/adr/0002-embedded-local-mcp-boundary.md) for the supported contract.

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

Start a sharded cluster when you explicitly want the experimental distributed layer:

```gleam
import aarondb/sharded

let assert Ok(cluster) = sharded.start_sharded("cluster", 4, None)
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
- [Local federation contract](docs/manual/local_federation.md)
- [Distributed Guide](docs/distributed_guide.md)

## Current Recommendation

Treat AaronDB first as a temporal Datalog engine with a strong in-memory core. Adopt peripheral layers only with explicit evaluation of their maturity and operational trade-offs.
