# AaronDB

> "Simplicity is not about making things easy. It is about untangling complexity." - Rich Hickey

AaronDB is a BEAM-native temporal Datalog engine written in Gleam. Its strongest current shape is a fact-oriented database core built around a transactor actor, immutable-style state transitions, in-memory indexes, and a custom query engine.

This repository also contains experimental distributed, search, MCP, cognitive, and CMS layers. Those subsystems are not all at the same maturity level. See `docs/feature_maturity.md` and `docs/project_boundaries.md` before adopting non-core features.

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
| Graph, vector, BM25, federation | Beta | Implemented, but less bounded than core |
| Sharding and distributed queries | Beta/Experimental | Works as scatter/gather; not a full distributed query fabric |
| Raft and HA claims | Experimental | Leader-election state machine exists; production consensus story is incomplete |
| MCP server and agent tooling | Experimental | Partial tool coverage and explicit TODOs remain |
| GleamCMS | Experimental | Product layer mixed into the DB repo |

## Installation

Add `aarondb` to your `gleam.toml`:

```toml
[dependencies]
aarondb = "2.4.1"
```

## Why 2.4.1 Is Better

AaronDB 2.4.1 completes the last safe reduction of `engine.gleam` after the 2.4.0 redesign.

- `engine.gleam` reduced from 2174 to 296 lines.
- `transactor.gleam` remains split into runtime, lifecycle, schema, validation, apply, and message helpers.
- The solver is now split into protocol modules: bindings, stores, triple, positive, and recursive orchestration.
- The solver dispatch hub is extracted into `engine/solver/core.gleam`.
- Derived-clause handling is extracted into `engine/solver/derived.gleam`.
- Vector input parsing is extracted into `engine/solver/vector_input.gleam`.
- The transactor is now split into domain modules: lifecycle, schema validation, runtime, apply, messages, and constraint validation.
- Rule derivation, aggregate clauses, and temporal clauses each have their own modules.
- Direct unit tests now cover extracted solver and transactor modules.
- CI runs format checks and tests automatically.
- Benchmarks are separated from the default test suite.
- All 169 tests pass with zero warnings.

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
- [Supervision](docs/manual/supervision.md)
- [Distributed Guide](docs/distributed_guide.md)

## Current Recommendation

Treat AaronDB first as a temporal Datalog engine with a strong in-memory core. Adopt peripheral layers only with explicit evaluation of their maturity and operational trade-offs.
