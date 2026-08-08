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

## 2. Local Sharding and Raft

**Current State:**

Local sharding provides parallel scatter/gather work inside a BEAM runtime. Raft is an inactive election-only state-machine stub and is not part of the query or transaction path.

**Gaps and deliberate limits:**

- `migrate_shard_data` is an explicit not-implemented error; there is no dynamic re-sharding, retry, recovery, or failover contract.
- Query coordination scans all local shards; there is no remote membership or bounded distributed query planner.
- `Sum`, `Count`, `Min`, and `Max` are exact secondary reductions. `Avg` and `Median` are approximate from per-shard scalar results.
- No Raft, quorum, replication, or high-availability claim is supported.

See `docs/distributed_guide.md` and ADR 0002 for the supported boundary.

## 3. Cognitive Engine (MuninnDB Integration)

**Current State:**

The active cognitive feature is the `Cognitive` Datalog clause implemented in `engine/cognitive.gleam`. It intersects stored `engram/concept` and `engram/context` facts and filters by explicit `engram/relevance`; it does not include the former unwired ACT-R/Hebbian scoring model.

**Gaps:**

- The local MCP stdio adapter implements only `remember`, `recall`, and `read`.
- Adaptive decay, association learning, and probabilistic confidence are deliberate non-goals until a new engine-backed design defines their persistence and ranking semantics.

## 4. Security and Isolation

**Current State:**

The supported boundary is an embedded library and local child-process MCP adapter. Capability payloads are local authorization data, not user authentication or signed credentials.

**Gaps and deliberate limits:**

- Network exposure is not supported. Adding HTTP/SSE/TCP requires a new security ADR and a signed, expiring capability-token design before any listener is introduced.

## Immediate Action Items

1. Keep README, architecture, and maturity docs aligned with exported APIs and tests.
2. Keep extension boundaries explicit before expanding claims.
3. Revisit migration, exact global aggregates, and HA only with a concrete distributed product commitment.
4. Expand MCP tools only when handlers, schemas, and local protocol tests exist.
