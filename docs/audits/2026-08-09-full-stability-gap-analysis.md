# Full Module Stability Gap Report

**Date:** 2026-08-09  
**Repository:** `moneyacademyKE/gleamdb`  
**Release baseline:** `v4.1.0` (`master` at `a61f106`)  
**Verification:** `gleam test --target erlang` — **220 passed, no failures**

## Scope and method

This report classifies the public product boundaries and all production-module families using implementation, tests, FFI behavior, CI evidence, and documentation—not filenames or test counts alone. The supported product shape remains **one embedded AaronDB instance in one BEAM runtime**. “Stable” therefore means stable for a documented local contract, not distributed-database availability or universal benchmark claims.

## Current classification

| Boundary / module family | Status | Evidence | Risk or remaining gate |
|---|---|---|---|
| `aarondb`, `transactor/*`, `engine/*`, `shared/*`, `fact`, `index`, `storage` | Stable-local core | Actor-owned writes, immutable state transition path, schema/query/constraint tests, safe term decoding, 220-test suite | Convenience APIs still contain timeout assertions; audit these as public totality work |
| Query DSL, planner, solver, pull, history, speculation | Stable-local | Direct DSL/engine/solver/pull/history tests; documented API contracts | Dense solver dispatch and legacy convenience APIs need normal regression maintenance |
| Temporal snapshots and diff | Stable-local bounded API | Canonical valid/transaction/bitemporal lifecycle tests, bounded scan/range errors, partition invariant, benchmark and CI harness | Legacy unbounded APIs are compatibility-only |
| Graph analytics | Stable-local bounded API | Directed semantic contract, canonical/invariant tests, traversal/global budgets, benchmark harness | Legacy unbounded APIs are compatibility-only; no remote/cancelled processing contract |
| Vector/HNSW | Stable-local approximate API | Dimension/zero-vector validation, exact oracle, deterministic test config, recall/churn evidence, benchmark harness | Approximate by design; no universal recall/latency SLA |
| BM25 | Stable-local caller-owned primitive | Analyzer v1, deterministic ranking, replace/remove/rebuild equivalence and benchmark | No persistence, transactor integration, or concurrent-mutation contract |
| Local federation | Stable-local fail-fast reads | Source admission, schema compatibility, provenance, deterministic ordering, typed unavailable/timeout errors, soak harness | No global snapshot, partial results, remote sources, retries, or coordinated writes |
| Virtual predicates | Stable-local bounded adapters | Typed adapter outcomes, positive row limits, fail-closed timeout/overflow tests | Synchronous adapter calls cannot be forcibly interrupted |
| Reactive subscriptions | Stable-local local mailbox delivery | Serialized initial/delta/unsubscribe lifecycle, stopped-subscriber cleanup, manual contract | Mailboxes are unbounded; no replay, acknowledgement, or durable stream |
| Cognitive solver | Stable-local explicit-fact solver | One active `engine/cognitive` path, relevance default/max/update/retract regression coverage | No adaptive learning, embeddings, ranking, external retrieval, or cross-node semantics |
| MCP `server`, `stdio`, `tools` | **Beta / local-only** | Real line-level JSON-RPC parsing and lifecycle tests cover initialize, notifications, parse errors, unsupported methods, EOF contract, protocol response separation | Add process-level stdin/stdout/stderr conformance, initialize-version negotiation, and child-process shutdown/supervision evidence before promotion |
| Mnesia adapter and FFI | **Recovery-oriented single-node** | Non-destructive schema mismatch behavior, transaction error propagation, recovery tests, explicit adapter contract | Add deterministic interruption/concurrency/schema-evolution evidence before a Stable-local recovery label; no HA/multi-node claim |
| Sharding | **Beta / contained** | Local scatter/gather, routing and HNSW tests; explicit unsupported migration/rebalance APIs; distributed guide states limits | Public lifecycle functions still need a full unsupported-surface review; migration, failover, exact global aggregates, and atomic writes are absent |
| Auth and gateway | **Local-only capability model** | Authorization/decode tests and explicit docs | Tokens have no signature, expiry, issuer trust, or key rotation. Never expose as network authentication without a separate design |
| `raft` | **Inactive stub** | Prominent source/docs status, isolated pure election tests, no runtime import path | Keep quarantined or remove. Do not wire election-only code into product paths |
| `rag` | **Stable-local MCP query macro** | Direct RAG tests and MCP consumer; compiles to existing cognitive/graph clauses | Must remain documented as a macro, not a retrieval service or second engine |
| `scoring`, `global`, `process_extra`, raw ETS/Mnesia/term/process FFI | Boundary/compatibility support | Focused consumers; term FFI uses `binary_to_term(..., [safe])`; malformed data regression coverage | Continue each-FI input/output and actor-lifecycle audit; do not market these as standalone product features |
| `cache`, `event`, `algo/{aggregate,bloom,cracking,vectorized}`, `math`, ART/ETS primitives | Stable-local support primitives | Unit/integration tests and core consumers | Define limits for resource-heavy or malformed-input calls where exposed publicly |
| Benchmark executables | Evidence tooling | CI executes vector, BM25, graph, federation, and temporal/diff harnesses | Benchmark assertions are acceptable tooling invariants, not library API behavior |

## Concrete current findings

### 1. MCP needs process-boundary evidence

The line handler is well specified: one synchronous line at a time; JSON-RPC notifications produce no response; malformed input produces `-32700`; diagnostics use stderr; EOF ends the process. Current tests call `serve_line`, however, rather than exercising `serve` through an actual child process with separate stdin/stdout/stderr. Promotion requires that black-box test plus initialize protocol-version handling and a documented process-supervision/shutdown result.

### 2. Mnesia is honest but not yet operationally mature

The adapter now preserves incompatible schemas and returns FFI errors rather than deleting data or reporting failed writes as successful. The claim should remain recovery-oriented until isolated tests demonstrate restart/interruption behavior, deterministic concurrent initialization/writer semantics, and a defined schema-evolution response. This is deliberately not a request for HA or multi-node storage.

### 3. Sharding remains an intentional Beta boundary

`migrate_shard_data` and `rebalance` return explicit unsupported errors, which is correct. The remaining gate is containment: verify every public sharding function either provides its stated local scatter/gather behavior or returns a typed unsupported/failure result. A Stable distributed claim requires an entirely separate plan for migration atomicity, idempotency, exact aggregates, and failover.

### 4. Public timeout totality remains incomplete

Some public convenience calls still use `let assert Ok(...) = process.receive(...)`, notably state/config/function/predicate helpers in `transactor` and `new_with_adapter_and_timeout`. These are ordinary timeout paths, not invariant failures. Convert them to `Result` APIs or explicitly mark panic-style convenience functions as compatibility-only with safe alternatives. Internal bit-pattern/logarithm assertions and benchmark assertions are separately classifiable invariants.

### 5. Legacy names are now mostly honest, but need guardrails

Raft is correctly inactive. RAG is a supported local macro, not legacy dead code. `scoring` must stay explicitly caller-owned and separate from the sole cognitive solver. The docs should preserve this distinction so no second cognitive/retrieval architecture reappears by implication.

## Promotion and removal gates

| Boundary | Gate |
|---|---|
| MCP → Stable-local | Child-process conformance suite: protocol-only stdout, stderr diagnostics, negotiation/notification/malformed/unsupported/EOF cases, and documented supervision/cancellation behavior |
| Mnesia → Stable-local recovery | Isolated restart, failed-write, schema mismatch, interruption, and concurrent initialization evidence; typed errors at every FFI edge; documented single-node topology |
| Sharding | Remains Beta. Either fully quarantine incomplete migration/rebalance APIs or implement transactional migration, exact aggregation, recovery, and failover under a separate approved design |
| Public actor APIs | No unexplained timeout assertions at public/FFI boundaries; each has a typed safe path and a regression test |
| Raft | Keep inactive or remove. Promotion requires replicated log, transport, persistence, commit semantics, and fault testing—out of scope |
| Auth | Keep local-only. Network use requires signed expiring credentials, trusted issuers, key rotation, and replay/clock policy |

## CI and release evidence

CI currently runs formatting, docs build, tests, Actionlint, and the five committed evidence harnesses. `v4.1.0` is the released baseline. Future maturity promotions must update this report, `docs/feature_maturity.md`, the contract manual, tests, and evidence index in the same change.

## Non-goals

This audit does not recommend adding remote federation, HA, Raft consensus, replicated logs, coordinated distributed writes, shard migration, or network authentication. Those are distinct products, not missing polish on the embedded/local database.
