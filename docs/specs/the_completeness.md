# PRD: Phase 9 - The Completeness

**Status**: IMPLEMENTED (v2.1.0)
**Priority**: P0
**Owner**: Rich Hickey 🧙🏾‍♂️

## Overview
GleamDB has achieved Entity Purity, but it lacks the primitives for **Atomic Logic** (Transaction Functions) and **Rich Integrity** (Composite Constraints). This phase completes the engine's journey from a "Triple Store" to a "Durable System of Record."

## User Stories
- **As a Developer**, I want to run logic within the transactor (e.g., `increment`) so that I avoid race conditions during read-modify-update cycles.
- **As a System Architect**, I want to define composite unique constraints (e.g., `user/first-name` and `user/last-name`) so that I can enforce business-level entity integrity.
- **As an SRE**, I want the database to reject transactions that violate schema invariants (Schema Guards), ensuring the data is correct by construction.

## Acceptance Criteria
### Transaction Functions
- [x] GIVEN a registered function `inc`
- [x] WHEN I transact `[:db/fn "inc" [entity "age" 1]]`
- [x] THEN the transactor resolves the current value, computes the increment, and persists the new fact atomically.
- [x] FAILURE: If the function crashes, the entire transaction is rolled back (Mnesia transaction).

### Composite Uniqueness
- [x] GIVEN a schema defining a unique composite `[attr-a, attr-b]`
- [x] WHEN I transact facts that would create a duplicate pair
- [x] THEN the transaction is rejected with a descriptive error.

### Schema Guards
- [x] GIVEN an existing dataset
- [x] WHEN I attempt to apply a schema change that contradicts existing data (e.g., making a non-unique attribute unique)
- [x] THEN the schema update is rejected.

## Technical Implementation

### Database Schema Changes
- `DbState` will now store a `functions: Dict(String, fn(DbState, List(Value)) -> List(Fact))`.
- `CompositeConstraints: List(List(String))`.

### API
- `gleamdb.register_fn(db, name, func)`
- `gleamdb.transact_with_fn(db, name, args)`

### Visual Architecture (Mermaid)
```mermaid
sequence_diagram
    participant Client
    participant Transactor
    participant Registry
    participant Mnesia
    
    Client->>Transactor: Transact([:db/fn "inc" [1 "age"]])
    Transactor->>Registry: Lookup "inc"
    Registry-->>Transactor: FunctionPtr
    Transactor->>Transactor: Run(FunctionPtr, State, [1 "age"])
    Transactor->>Mnesia: Persist [[:db/add 1 "age" 31]]
    Mnesia-->>Transactor: Ok
    Transactor-->>Client: NewState
```

## Pre-Mortem Analysis
**Why will this fail?**
1. **Blocking the Writer**: If a transaction function performs heavy computation, it blocks all other writers (single-process transactor). 
   - *Mitigation*: Strictly enforce that transaction functions must be pure and "fast." No I/O allowed inside the function.
2. **Non-Determinism**: If a function uses `Now()` or `Random()`, replicas might drift.
   - *Mitigation*: Functions only receive the `DbState` and `Args`. Replicas receive the *resulting* datoms, not the function call itself.

## Phase 26: The Intelligent Engine
- [x] GIVEN a graph of entities linked by an attribute
- [x] WHEN I query `ShortestPath` or `PageRank`
- [x] THEN the engine computes the algorithmic result and binds it to variables.
- [x] GIVEN an external data source
- [x] WHEN I query a `Virtual` predicate
- [x] THEN the engine delegates to the registered adapter.

## Phase 27: The Speculative Soul
- [x] GIVEN an immutable `DbState`
- [x] WHEN I call `with_facts(state, facts)`
- [x] THEN I receive a new `DbState` containing the facts without persistent side-effects.
- [x] GIVEN a recursive relationship (e.g., manager/employee)
- [x] WHEN I use `pull_recursive`
- [x] THEN the engine automatically traverses the graph to the specified depth.
- [x] GIVEN an entity ID and attribute
- [x] WHEN I use the `Entity API` (`get`/`get_one`)
- [x] THEN I retrieve the values directly without Datalog overhead.

## Phase 31: Sovereign Intelligence (v1.9.0)
- [x] GIVEN a large dataset (>500 contexts)
- [x] WHEN I allow `solve_parallel`
- [x] THEN the engine automatically shards execution across spawned processes.
- [x] GIVEN a query with `Aggregate` clauses (`Sum`, `Count`, etc.)
- [x] WHEN I execute it
- [x] THEN the engine computes reductions in-stream without returning raw data.

## Phase 3: Local Search Primitives

- [x] GIVEN a caller-owned BM25 index
- [x] WHEN documents are added, replaced, removed, or searched
- [x] THEN the index preserves document statistics and returns deterministic local rankings.
- [ ] GIVEN a database transaction and a query with BM25 terms
- [ ] WHEN the engine executes it
- [ ] THEN the transactor maintains BM25 state and the query engine performs text retrieval or hybrid ranking.

The second scenario is intentionally not implemented: see `docs/manual/bm25_search.md`.

## Phase 4: Adaptive Stabilization (v2.2.0)
- [x] GIVEN a persistent memory requirement in GClaw
- [x] WHEN I initialize with `init_persistent`
- [x] THEN the system restores the silicon-substrate from disk using the 5-arity Datom adapter.
- [x] GIVEN a historical sharded dataset
- [x] WHEN I query with `sharded.since`
- [x] THEN the engine leverages sharded temporal read-paths to achieve a **59x speedup**.

## Phase 8: The Sovereign Console (v2.2.0)
- [x] GIVEN a running Sovereign Fabric
- [x] WHEN I access the Console via HTTP
- [x] THEN I see a real-time D3.js visualization of the cluster topology and alpha generation.

## Phase 15: The Federated Pulse (v2.6.0)
- [x] GIVEN a sharded cluster
- [x] WHEN I execute a query with aggregates (`Sum`, `Count`)
- [x] THEN the coordinator performs a secondary reduction pass to resolve global truth.
- [x] GIVEN a transaction
- [x] WHEN it is committed to the log
- [x] THEN the transactor broadcasts the datoms to all WAL subscribers in real-time.

## Phase 32: Sovereign Content (v2.1.0)
- [x] GIVEN a requirement for decentralized editing
- [x] WHEN I use the **Fact-Sync Bridge**
- [x] THEN atomic Datalog facts are transacted directly into the CMS store via the Wisp/Lustre interface.
- [x] GIVEN a need for type-safe projections
- [x] WHEN I use **Exhaustive Projections** with Sum Types
- [x] THEN the compiler guarantees that every post state (Draft, Published, Archived) is handled in the SSG.

## Phase 5: Bounded Extension Roadmap

Graph, local federation, and search extensions remain Beta. The current supported contract is embedded/in-process execution. HNSW vector search and standalone BM25 behavior are documented under `docs/manual/`; neither implies hybrid retrieval, distributed coordination, or production service guarantees.
