# Full Module Stability Gap Report

**Date:** 2026-08-08  
**Repository:** `moneyacademyKE/gleamdb`  
**Checkout:** `/Users/moe/Desktop/gleamdb`  
**Branch:** `release/v4.1-local-maturity`  
**HEAD:** `a8859b7`  

## Scope and baseline

This audit classifies the public source modules, FFI boundaries, tests, and maturity claims against the supported product boundary: an embedded AaronDB instance in one BEAM runtime. It does not treat a module name or the existence of a test as proof of maturity.

The checkout is clean except for this report. The source tree contains 79 production Gleam modules plus Erlang FFI files. Generated `build/` artifacts are excluded from classification. Existing docs define Stable as requiring correctness, lifecycle, resource, reproducible local benchmark, and CI evidence.

## Classification

| Area / modules | Status | Evidence | Remaining risk / gate |
|---|---|---|---|
| `aarondb.gleam`, `transactor/*`, `engine/*`, `shared/*`, `fact.gleam`, `storage.gleam` | Stable-local core | Broad test suite, typed storage adapters, query/planner/solver decomposition, temporal/diff bounded APIs | Large orchestration modules and some convenience APIs still contain assertions; continue totality audit |
| `index/*`, `vec_index.gleam`, `vector.gleam` | Stable-local approximate | Dimension validation, exact oracle, deterministic test config, churn/recall tests, benchmark and evidence docs | HNSW remains approximate; no universal SLA; production topology uses randomness |
| `index/bm25.gleam` | Stable-local caller-owned primitive | Analyzer v1, deterministic ranking, lifecycle/rebuild/golden tests, benchmark | No transactor integration, persistence, or concurrent mutation contract by design |
| `algo/graph.gleam`, `engine/graph_clauses.gleam`, traversal/graph query APIs | Stable-local bounded | Directed semantics, bounded traversal/global APIs, canonical tests, benchmark fixtures | Legacy unbounded compatibility APIs remain; no remote/cancellation/global snapshot guarantees |
| `engine/temporal_clause.gleam`, temporal APIs, `engine.diff` | Stable-local bounded | Transaction/valid/bitemporal lifecycle tests, typed scan limits, bounded diff range/budget, invariant and benchmark evidence | Legacy unbounded APIs remain compatibility-only; no retention or remote snapshot guarantee |
| `federation.gleam` | Stable-local fail-fast reads | Named source admission, schema compatibility, deterministic ordering, provenance, typed source failures, soak benchmark | No cross-source snapshot, coordinated writes, remote transport, retries, or partial-result API |
| `engine/virtual.gleam`, virtual adapter state | Stable-local bounded adapter | Typed adapter errors, positive row limits, overflow/failure/timeout tests and docs | Synchronous adapter cannot be forcibly interrupted; no remote/distributed contract |
| `reactive.gleam` | Stable-local mailbox delivery | Serialized actor ordering, explicit unsubscribe, stopped-subscriber pruning, tests and manual | Unbounded BEAM mailbox and no durable replay/ack contract |
| `engine/cognitive.gleam` | Stable-local explicit-fact solver | One authoritative solver, relevance update/retract/default tests and docs | No learned ranking, embeddings, decay, external retrieval, or cross-node consistency |
| `mcp/server.gleam`, `mcp/stdio.gleam`, `mcp/tools.gleam` | Beta / local | JSON-RPC parsing/serialization, three-tool registry, real stdio tests, notification and EOF behavior | Broader host-conformance, supervision, cancellation, schema compatibility evidence still needed; no network listener |
| `storage/mnesia.gleam`, `aarondb_mnesia_ffi.erl` | Recovery-oriented | Non-destructive schema mismatch, propagated transaction errors, recovery tests and docs | Single-node only; concurrency/interruption/schema evolution operational evidence incomplete; no HA/multi-node claim |
| `sharded.gleam` | Beta | Local scatter/gather and HNSW/rebalance tests; migration returns explicit unsupported error | `pull` still uses `unsafe_coerce`; rebalance atomicity/source retraction unclear; migration/failover absent; Avg/Median approximate |
| `auth.gleam`, `gateway.gleam` | Local-only | Capability model and authorization tests; no network transport | Tokens are decoded, not signed/verified; no issuer/expiry/key rotation/trust store; keep local-only |
| `raft.gleam` | Inactive stub | Prominent inactive status; pure election state machine and isolated tests | No replicated log, transport, persistence, quorum, or runtime integration; do not promote piecemeal |
| `rag.gleam`, `scoring.gleam` | Legacy/compatibility-only | Isolated tests/docs exist, but not authoritative for `engine/cognitive` | Duplicate conceptual surface; remove/quarantine or define an integration milestone |
| `global.gleam`, `process_extra.gleam`, raw FFI modules | Compatibility / boundary support | Thin wrappers with focused consumers | Need per-boundary malformed-input and process-lifecycle audit; not independently product features |
| `cache.gleam`, `event.gleam`, `algo/bloom.gleam`, `algo/cracking.gleam`, `algo/vectorized.gleam`, `math.gleam` | Stable-local supporting primitives | Unit/integration coverage and pure implementations | Define limits and failure behavior where inputs can be malformed or resource-heavy |
| `rule_serde.gleam`, `index/ets.gleam`, `aarondb_term_ffi.erl`, other storage/index FFI | Stable-local with trust-boundary risk | Safe term decoding and malformed payload tests exist | Continue auditing shape validation, FFI error propagation, and corrupt persisted data behavior |

## Concrete findings

### P0 — incomplete public sharding surface

`sharded.migrate_shard_data` is public but explicitly returns an unsupported error. `sharded.pull` crosses a typed process boundary through `unsafe_coerce`. `rebalance` does not yet establish transactional copy/verify/cut-over/retract semantics. Keep sharding Beta; either hide unsupported operations or introduce explicit unsupported types and checked result boundaries.

### P1 — MCP remains local Beta

The stdio adapter is synchronous and local, which is a coherent boundary. Remaining evidence is host-conformance breadth: initialize negotiation, tools/list schemas, malformed requests, notifications, unsupported methods/tools, EOF, diagnostics, child-process supervision, and the fact that cancellation cannot interrupt a running synchronous tool call.

### P1 — Mnesia contract is narrower than its name suggests

The adapter now preserves data on schema mismatch and propagates transaction failures. The supported contract should remain single-node recovery. Add deterministic tests for interruption/concurrent access/schema evolution where feasible; do not claim multi-node durability or HA.

### P1 — public assertion/failure audit incomplete

Production assertions remain in transactor convenience paths, recursive solver waits, sharded process lookups, raw ETS reads, vector random-level math, and low-level bit parsing. Some are invariant checks or benchmark-only assertions; each must be classified, converted to typed errors, or documented as an accepted internal invariant.

### P2 — legacy surfaces

Raft is correctly inactive and election-only. RAG/scoring modules are not the authoritative cognitive implementation and should be removed, quarantined, or given an explicit compatibility/roadmap status. The repository should have one authoritative implementation per supported concept.

### P2 — documentation drift

Some legacy feature pages and reports still describe earlier Beta states or old scale claims. Search and reconcile README, feature maturity, architecture, distributed guide, changelog, and feature pages whenever a promotion or quarantine decision changes.

## Promotion/removal gates

1. **MCP Stable-local:** real stdin/stdout integration tests, protocol-only stdout, stderr diagnostics, lifecycle/notification/EOF coverage, and explicit no-network docs.
2. **Mnesia Stable-local recovery:** isolated restart/recovery, aborted write, schema mismatch, interruption/concurrency evidence; typed FFI failures; no destructive startup path.
3. **Sharding:** remains Beta until migration atomicity, exact aggregate semantics, failover, and unsafe-cast removal are implemented and tested. Otherwise quarantine incomplete APIs.
4. **Failure boundaries:** zero unexplained production assertions or unsafe casts at public/FFI boundaries; accepted invariants documented and regression-tested.
5. **Legacy:** remove/quarantine RAG/scoring and retain Raft only as an unmistakable inactive stub unless a bounded integration milestone is approved.
6. **Release evidence:** CI runs format, build, tests, docs, actionlint, and applicable evidence harnesses; maturity labels link to artifacts.

## Non-goals

This report does not recommend implementing Raft consensus, replicated logs, quorum commit, remote federation, coordinated distributed writes, shard migration, or network authentication. Those require separate product and architecture decisions.
