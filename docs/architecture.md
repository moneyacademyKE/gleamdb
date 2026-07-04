# AaronDB Architecture

> "Simplicity is not about making things easy. It is about untangling complexity."

AaronDB is best understood as a temporal Datalog engine with extensions. The essential architecture is smaller and stronger than the full set of ideas present in this repository.

## Essential Core

### 1. Actor-Owned Transactions

A transactor actor owns the mutable process boundary. Transactions are serialized through that actor, while callers interact with values and results.

Core modules:

- `src/aarondb.gleam`
- `src/aarondb/transactor.gleam`
- `src/aarondb/shared/state.gleam`

### 2. Facts and Datoms

The basic data model is a datom carrying:

- entity
- attribute
- value
- transaction id
- transaction order
- valid time
- operation

This generic representation allows query execution and indexing to stay data-oriented.

### 3. Index-Oriented Reads

The primary in-memory indexes are:

- `EAVT`
- `AEVT`
- `AVET`

They support the main query path and are updated during transaction processing.

### 4. Interpreted Query Execution

Queries are represented as AST values and executed by a custom interpreter. The engine also includes rule derivation, pull handling, graph clauses, and aggregation.

This is powerful, but it also means much of the system's complexity is concentrated in a small number of large modules.

Current engine boundaries:

- `engine.gleam`: top-level query orchestration, rule derivation, core clause solving, aggregate and temporal coordination.
- `engine/planner.gleam`: query optimization, aggregate metadata collection, and top-level result ordering/pagination.
- `engine/executor.gleam`: planned clause execution over contexts with a clause-solver callback.
- `engine/solver/bindings.gleam`: part resolution helpers.
- `engine/solver/stores.gleam`: columnar store merging utilities.
- `engine/solver/triple.gleam`: positive/negative triple matching against base and derived facts.
- `engine/solver/positive.gleam`: positive clause solving with cracking, columnar, adapter, and morsel paths.
- `engine/solver/recursive.gleam`: recursive clause solving with parallel execution support.
- `engine/aggregate_clause.gleam`: aggregate clause solving with columnar and row-based paths.
- `engine/temporal_clause.gleam`: temporal clause solving with nested clause evaluation.
- `engine/solver_context.gleam`: explicit solver state passed through execution boundaries.
- `engine/entity.gleam`: entity history, active-datom filtering, pull, diff, and time filtering.
- `engine/traversal.gleam`: traversal expressions over entity references.
- `engine/predicate.gleam`: compiled filter predicates.
- `engine/graph_clauses.gleam`: Datalog graph clause adapters.
- `engine/retrieval.gleam`: vector similarity and custom-index clauses.
- `engine/string_clause.gleam`: string prefix clauses backed by ART.
- `engine/virtual.gleam`: virtual predicate argument and output binding.
- `transactor/validation.gleam`: transaction constraint validation (uniqueness, check, composite).

## Extension Layers

These exist in the repository, but should be treated as optional layers over the core rather than the definition of AaronDB itself.

| Layer | Current Role |
| --- | --- |
| Sharding | Parallel routing and scatter/gather query execution |
| Raft | Leader-election state machine |
| Search | ART, vector index, BM25 |
| Agent tooling | MCP, RAG, capability-gated gateway |
| CMS | GleamCMS application code |

## Current Architectural Reality

AaronDB has a strong center and a broad edge.

- The center is the transactor, datom model, indexes, and query engine.
- The edge contains several ambitious systems at different maturity levels.

That means the main architectural task is not inventing more features. It is preserving clarity around the core while preventing optional layers from becoming inseparable from it.

## Recommended Direction

1. Keep the core database contract small and explicit.
2. Treat distributed, agent, search, and CMS modules as extension surfaces.
3. Reduce documentation drift by tying claims to exported APIs and tests.
4. Keep future engine changes inside the smallest concern-specific module possible.
