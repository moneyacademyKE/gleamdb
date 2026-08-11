# Historical Design Notes: GleamDB

> **Status: historical reference, not a product specification.** This document predates the v4.1.0 embedded/local boundary. Statements about SQLite, RocksDB, S3, distributed Erlang clustering, actor-per-entity execution, infinite traversal, hot upgrades, WAL recovery, and unbounded performance are exploratory ideas—not implemented or supported AaronDB behavior. For the current contract, use [Project Boundaries](../project_boundaries.md), [Feature Maturity](../feature_maturity.md), and [ADR 0002](../adr/0002-embedded-local-mcp-boundary.md).


**Status**: REFERENCE
**Priority**: P0
**Owner**: Rich Hickey (Simulated)

## 🧙‍♂️ Rich Hickey's Deep Assessment

> "Simplicity is not about making things easy. It is about untangling complexity."

GleamDB aims to bring the power of deductive database logic (Datalog) to the fault-tolerant, concurrent world of the BEAM. Similar to CozoDB, it provides graph capabilities. Similar to Datomic, it treats the database as an immutable value.

### Philosophy & Constraints
1.  **Immutability**: The database is a value. It does not change in place. A transaction produces a *new* database value.
2.  **Time**: We preserve history. Queries can be run against any point in time (Epochal Time Model).
3.  **Facts, not Objects**: Data is represented as atomic facts `(Entity, Attribute, Value, Transaction, Operation)`.
4.  **Datalog**: The query language is logic-based, enabling recursive queries (e.g., graph traversal) which are impossible in standard SQL.
5.  **Pluggable Storage**: The engine logic (query/transactor) is decoupled from the durability layer (Mnesia, SQLite, RocksDB).

### Simulation: The "Hostile SRE" Perspective
*   **Breaking Changes**: Schema evolution is non-breaking because attributes are first-class entities.
*   **Bottlenecks**: The single-writer model (Transactor) is a potential bottleneck for write throughput. *Mitigation*: Sharding or specialized accumulation buffers for high-volume logs.
*   **Cost**: Storing full history increases storage cost. *Mitigation*: Log-structured merge trees and structural sharing.

---

## 🧬 Unique BEAM-Native Propositions

GleamDB is not just another Datalog engine; it is an OTP-native actor system that treats queries as first-class processes.

### 1. The "Open Heart Surgery" Query
A query in GleamDB is a process (Actor). This enables:
*   **Introspection**: Inspect `QueryPid` to see exactly which tuple is being processed.
*   **Suspension**: Pause long-running analytical queries to prioritize transaction traffic, then resume.
*   **Debug Trace**: Attach tracers to running queries to visualize data flow in real-time.

### 2. Zero-Downtime Logic Upgrades
Harnessing the BEAM's hot code swapping:
*   Push new `engine` modules without stopping the database.
*   Existing queries finish on the old logic; new ones start on the new logic.
*   Ideal for evolving complex recursive rules without downtime.

### 3. "The Database is the API"
Zero serialization overhead. The memory structure of a "User" in your application is identical to the structure in GleamDB. No JSON/Protobuf marshaling. You can use arbitrary Gleam functions as custom predicates in your queries.

### 4. Actor-per-Entity Concurrency
Every Entity can theoretically be an independent Actor.
*   Updates to Entity 101 are sent as messages to its process.
*   Serialized access is guaranteed by the Actor mailbox, eliminating the need for traditional row-level locks.

### 5. Infinite Recursive Queries
Representation of graph traversals as tail-recursive functions. Tail-call optimization (TCO) allows traversing billions of nodes without stack overflow.

### 6. Distribution as a Library
Compute moves to the data. Send query closures to the nodes holding the relevant data shards using built-in Erlang distribution.

---


## User Stories

*   **US-1**: As a backend developer, I want to define recursive rules to query hierarchical data (e.g., org charts, ACLs) efficiently.
*   **US-2**: As an operator, I want to time-travel to a previous state of the database to debug an issue without restoring a backup.
*   **US-3**: As a system architect, I want to embed the engine directly in my Gleam/Erlang application to minimize network latency (Local-First).

## Acceptance Criteria (Gherkin)

```gherkin
Feature: Datalog Query Execution

  Scenario: Basic Fact Insertion and Query
    Given a fresh GleamDB instance
    When I transact the fact `[101, "name", "Alice"]`
    And I transact the fact `[101, "role", "admin"]`
    Then a query for `?id, "role", "admin"` should return `[101]`
    And a query for `101, "name", ?name` should return `["Alice"]`

  Scenario: Recursive Rule Evaluation
    Given the parent facts:
      | parent | child |
      | alice  | bob   |
      | bob    | charlie |
    AND the rule "ancestor(X, Y) :- parent(X, Y)."
    AND the rule "ancestor(X, Z) :- parent(X, Y), ancestor(Y, Z)."
    When I query `ancestor("alice", ?descendant)`
    Then the result should contain "bob" and "charlie"

  Scenario: Time Travel
    Given a fact `[1, "v", 10]` at transaction T1
    And a fact `[1, "v", 20]` at transaction T2
    When I query `?e, "v", ?v` as of transaction T1
    Then the result should be `10`
    When I query `?e, "v", ?v` as of transaction T2
    Then the result should be `20`
```

## Technical Implementation

### 1. Data Model (The 5-Tuple)
Every piece of data is stored as a Datomic-style tuple:
`{Entity ID (Int), Attribute (String/Int), Value (Any), Transaction ID (Int), Added (Bool)}`

*   **E**: Entity ID (64-bit integer)
*   **A**: Attribute (typically an ident keyword, mapped to an integer ID)
*   **V**: Value (Gleam dynamic, strictly typed at boundaries)
*   **T**: Transaction ID (Time)
*   **Op**: Boolean (True = Assert, False = Retract)

### 2. Indexes (Silicon Saturation)
To support efficient Datalog execution, we maintain lock-free ETS indices:
- **EAVT**: Bucketed `Dict` or ETS `duplicate_bag` for entity-first lookups.
- **AEVT**: Attribute-first lookups for index scans.
- **AVET**: Value-based lookups for uniqueness.
- **HNSW**: Hierarchical Navigable Small-World graph for vector similarity ($O(\log N)$).
- **ART**: Adaptive Radix Tree for string prefix search ($O(k)$).
- **Silicon Saturation**: ETS `read_concurrency` enables O(1) concurrent reads across all nodes.

### 3. Architecture components
*   **`gleamdb/engine`**: The core semi-naive evaluation engine.
*   **`gleamdb/storage`**: Protocols for KV storage (Adapters for Ets, Mnesia, SQLite, Disk).
*   **`gleamdb/transactor`**: Serializes writes, assigns Tx IDs, notifies listeners.
*   **`gleamdb/sharded`**: Horizontal partitioning and sharded temporal optimization (**59x speedup**).

### 4. Data Flow
1.  **Write**: `API -> Transactor -> (Validation) -> (Log Write) -> (Index Update) -> Storage`.
2.  **Read**: `API -> Query Engine -> (Index Seek/Scan) -> Storage`
3.  **Subscription**: `Transactor -> (Broadcast) -> Connected Peers`

### 5. API Design
```gleam
// Definition
pub type Fact = #(Int, String, Dynamic)
pub type QueryResult = List(List(Dynamic))

// Core API
pub fn new(storage: StorageAdapter) -> Db
pub fn transact(db: Db, facts: List(Fact)) -> Result(Db, Error)
pub fn query(db: Db, logic: String) -> Result(QueryResult, Error)
pub fn as_of(db: Db, tx_id: Int) -> Db
```

### 7. Advanced Predicates (Graph & Federation)
Native algorithmic and external data primitives:
*   **ShortestPath(from, to, edge, path_var, cost_var)**: BFS traversal over `edge` attribute.
*   **PageRank(entity_var, edge, rank_var, damping, iterations)**: Iterative power method for node ranking.
*   **Virtual(predicate, args, outputs)**: Delegation to registered external adapters (Federation).
*   **StartsWith(variable, prefix)**: String prefix filtering and generation using ART.
*   **Similarity(variable, vector, threshold)**: Vector similarity search using HNSW.

### 8. Time Travel API
*   **`gleamdb.as_of(db, tx)`**: Query the database state as it existed at a specific transaction.
*   - **`gleamdb.diff(db, start_tx, end_tx)`**: Retrieve all assertion/retraction datoms between two points in time.

## Security & Validation
*   **AuthZ**: Capability-based security at the API boundary. The engine itself is trusted; wrappers provide security.
*   **Input Validation**: All values must match the schema type of the Attribute (if enforced).
*   **DoS Prevention**: Query timeout limits and max recursion depth configuration.

## Pre-Mortem Analysis
*   **Failure Mode 1**: **Query Explosion**. A complex recursive query consumes all memory.
    *   *Mitigation*: Implement strict memory budgets per query and "Fuel" metric for execution steps.
*   **Failure Mode 2**: **Write Contention**. The single transactor cannot keep up.
    *   *Mitigation*: Optimistic concurrency for distinct entities? No, keep it simple first. Batching writes is the primary solution.
*   **Failure Mode 3**: **Storage Divergence**. Index corruption.
    *   *Mitigation*: Write-Ahead Log (WAL) is the source of truth. Indices can be rebuilt from the Log.

## Autonomous Pipeline Status
1.  **Drafted**: ✅
2.  **Implementation**: ✅ (Phase 26 complete)
3.  **Verification**: `test/gleamdb/graph_algo_test.gleam`, `test/gleamdb/federation_test.gleam`, `test/gleamdb/diff_test.gleam`
