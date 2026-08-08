# AaronDB roadmap

AaronDB is a **local, embedded Datalog database**. The supported deployment boundary is defined by [ADR 0002](adr/0002-embedded-local-mcp-boundary.md): in-process use and local stdio MCP. It does not claim remote federation, replication, high availability, coordinated writes, sharding migration, or Raft-backed consensus.

## Current baseline

The retrieval/query-contract baseline is on `master` in `f0fe892` (PR #8). It defines explicit local contracts for approximate HNSW vector search, caller-owned BM25, directed graph operations, and local federation. These four areas remain **Beta** until their individual evidence gates are complete.

The authoritative maturity labels are maintained in [Feature Maturity](feature_maturity.md). Historical phase documents record prior implementation work; they are not current support or performance claims.

## Stable-maturity sequence

### 1. Vector / HNSW evidence

- Maintain a single cosine-search contract, deterministic test configuration, exact finite-corpus oracle, and committed recall corpus.
- Prove insert, replace, delete, and rebuild behavior with a churn suite.
- Commit reproducible benchmark inputs, environment, and results.

**Promotion gate:** deterministic recall and lifecycle evidence plus a measured local benchmark envelope. HNSW remains approximate; no universal latency, memory, or recall SLA is implied.

### 2. BM25 local retrieval evidence

- Maintain a versioned analyzer and parameter-validation contract.
- Keep golden ranking fixtures for Unicode, empty/repeated text, ties, replacement, and removal.
- Verify incremental state is equivalent to a clean rebuild.
- Commit reproducible local operation benchmarks and state the caller-owned concurrency/persistence boundary.

**Promotion gate:** deterministic local ranking and lifecycle evidence with a documented analyzer and benchmark envelope. Query-engine integration and hybrid retrieval are separate product work.

### 3. Graph analytics evidence

- Maintain one directed graph model for edges, self-loops, duplicate edges, missing vertices, and result ordering.
- Add canonical fixtures and invariants for every public graph algorithm.
- Bound traversal depth, result volume, visits, and iterative convergence; invalid or over-budget work must fail predictably.
- Commit representative sparse, dense, cyclic, disconnected, chain, and hub benchmark fixtures.

**Promotion gate:** every public graph operation has correctness, budget, and benchmark evidence.

### 4. Local federation evidence

- Execute reads against named local sources in deterministic source order.
- Preserve source provenance and namespace identity by source.
- Make source failures typed and fail-fast; the default API must not leak partial results.
- Test schema incompatibility, duplicate identities, stopped sources, timeouts, query failures, and multi-source soak behavior.

**Promotion gate:** tested local source execution and fail-fast behavior. This remains distinct from sharding, remote federation, replication, or coordinated writes.

## Explicitly deferred

- **Sharding:** local scatter/gather remains Beta until transactional migration and exact cross-shard aggregate semantics exist.
- **Raft:** inactive election-only stub; it has no transport, replicated log, persistence, or runtime integration.
- **Mnesia:** recovery-oriented adapter; no production multi-node or fault-tolerance claim.
- **Network MCP/auth:** local stdio is supported. Network exposure requires a separate signed-auth and service-operational design.

## Release discipline

A capability is labeled Stable only after its documented exit gate has committed evidence and all required checks pass: formatting, build, tests, docs build, workflow linting, and the applicable regression/benchmark checks.
