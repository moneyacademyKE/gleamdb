# AaronDB Gap Analysis

## Introduction

This document tracks the gap between the strongest implemented AaronDB core and
the broader platform vision described elsewhere in the repository.

The key distinction is simple:

- the core temporal Datalog engine is real and well tested
- several surrounding systems remain extension-grade or experimental

## 1. Datalog Expressiveness

**Current State:**

Supports core Datalog logic: pattern matching, `Bind`, graph algorithms
(`ShortestPath`, `PageRank`, etc.), aggregation, temporal filtering (`as_of`,
`since`), and unified `Cognitive` queries for semantic retrieval.

**Gaps:**

- Datalog rules are now durable across node restarts, persisted via binary serialization.
- Recursive queries using `pull_recursive` are functional but highly
  memory-intensive on deep graphs and could benefit from query-planner
  optimizations or lazy stream evaluation.

## 2. Distributed Operation and Raft

**Current State:**

Native sharding exists and distributed query helpers are implemented. Raft
currently provides a leader-election state machine.

**Gaps:**

- Re-balancing of shards is completely manual. Dynamic re-sharding when nodes
  crash or scale up is not yet implemented.
- The `Distributed Sovereign` telemetry uses raw Erlang distribution (Global)
  which does not scale beyond ~60-100 nodes. Transitioning to a Hash Ring
  (e.g., Riak Core) is needed for massive scale.
- Current distributed queries still rely on scatter/gather execution and do not
  yet amount to a tightly bounded distributed query planner.
- Raft claims should remain scoped to election and leadership behavior until a
  fuller replicated-log story exists.

## 3. Cognitive Engine (MuninnDB Integration)

**Current State:**

Ported successfully to pure Gleam. `Engram` decay functions (ACT-R) and Hebbian
learning are implemented and reachable dynamically via Datalog queries. MCP
server support exists with a small implemented subset of tools.

**Gaps:**

- Core MCP tools (`remember`, `recall`, `read`) are explicitly mapped; the
  broader MCP surface remains incomplete.
- Adaptive active decay (ACT-R) is now applied periodically to the engram pool 
  via background database ticks.

## 4. Security and Isolation

**Current State:**

No user authentication. Complete trust is assumed on the BEAM distribution
network.

**Gaps:**

- If exposed to external MCP agents directly over HTTP/SSE (currently stdio
  only), a Vault or capability-based security model must be implemented to
  prevent agents from corrupting the core transaction log.

## Immediate Action Items

1. Keep the README and architecture docs aligned with exported APIs and tests.
2. Continue separating core engine concerns from extension layers.
3. Implement dynamic shard rebalancing only after the distributed contract is clearer.
4. Expand MCP claims only when handlers and result formatting are complete.
