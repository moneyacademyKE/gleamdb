# Rich Hickey Certification Audit — AaronDB

**Date:** 2026-08-09
**Repository:** `~/Desktop/gleamdb`
**Package:** `aarondb`
**Branch:** `stability/mcp-stdio-conformance`
**Verdict:** **Conditional pass for the local Datalog core; no certification for the repository as a whole.**

## Executive verdict

AaronDB has a genuinely Rich Hickey-shaped center: facts rather than objects, explicit data values, pure state-transition models for the protocol work, a small actor-owned mutation boundary, and deliberately narrow claims. The repository is strongest when treated as a temporal, embedded, local Datalog engine.

It does **not** earn an unconditional certification across the full codebase. The main deductions are not because the system is ambitious; they are because several concerns have accumulated into broad state and oversized modules, while the repository exposes many optional systems whose complexity is only partially separated from the core. The distributed work is commendably honest in its documentation, but the presence of Raft/consensus/sharding/search/cognitive/MCP surfaces makes the whole repository a product family, not one simple thing.

The right conclusion is not “rewrite it smaller.” It is: **protect the small core, make extension boundaries executable, and split the remaining aggregate modules by state ownership and protocol.**

## Scorecard

| Dimension | Score | Assessment |
|---|---:|---|
| Data orientation | 9/10 | Datoms, tagged unions, ASTs, explicit state records, and value-based APIs are pervasive. |
| Pure transformations and explicit state | 8/10 | `command` and `raft_runtime` are strong pure models; actor/FFI/storage edges necessarily remain effectful. |
| Composability and boundaries | 7/10 | Query, solver, transactor, and storage boundaries are clear; `DbState` and the top-level actor still aggregate too much. |
| Simplicity of the essential core | 8/10 | The documented core is coherent and local; optional capabilities enlarge the mental surface substantially. |
| Names and semantic precision | 8/10 | Maturity labels and non-claims are unusually explicit; some APIs still carry compatibility/legacy breadth. |
| Module cohesion | 5/10 | Several files exceed the project’s own 250 LOC review threshold by a lot. |
| Verification discipline | 9/10 | 304 tests passed; format, type-check, and diff hygiene passed. Evidence gates are fail-closed. |
| Overall | **7.7/10** | **Conditional certification:** strong local core, not whole-repository certification. |

## Evidence for the certification

### 1. Data is the primary abstraction

`src/aarondb/fact.gleam`, `src/aarondb/shared/ast.gleam`, and the query modules model facts, clauses, rules, bindings, and results as data. This is the right foundation for a database: behavior operates over explicit values instead of hiding domain state behind object graphs.

`src/aarondb/command.gleam` is particularly clean. `Command`, `CommandRequest`, `CommandResult`, `CommandError`, `Applied`, and `State` form a closed vocabulary. `apply/3` makes idempotency and committed-index sequencing explicit, while `fingerprint/1` gives replay identity without pretending to be a cryptographic signature. That distinction is precise and honest.

### 2. State transitions are explicit and testable

`src/aarondb/raft_runtime.gleam` represents `Role`, `HardState`, `Persisted`, `Rpc`, `Reply`, and `State` as tagged data. Functions such as `start_election/1`, `win_election/2`, `commit_quorum/3`, `recover/3`, and `handle/2` return new state rather than mutating hidden protocol objects.

`src/aarondb/consensus.gleam` composes this model with command application and explicit error values such as `Redirect`, `QuorumUnavailable`, `ReadIndexUnavailable`, `InvalidClock`, `LeaseHeld`, and `StaleFence`. This is good Hickey-style boundary design: the caller supplies evidence; the pure model does not hallucinate transport or durability.

### 3. The repository is unusually honest about scope

`README.md` and `docs/architecture.md` explicitly distinguish the strong local core from local-beta and inactive surfaces. The README says Raft/HA is an inactive election-only stub and that sharding is one-runtime scatter/gather, not a distributed database. It also states the non-claims: no failover, coordinated writes, global snapshots, transactional migration, or universal latency/recall guarantees.

That is not mere documentation polish. It is semantic hygiene. “Stable” is scoped to evidence-backed local contracts instead of being used as a magical global adjective.

### 4. Verification is treated as evidence, not vibes

The current native checks produced these results:

| Check | Result |
|---|---|
| `gleam format --check` | Pass; no output |
| `gleam check` | Pass; compiled successfully |
| `gleam test` | Pass; **304 passed, no failures** |
| `git diff --check` | Pass; no output |

The repository also contains explicit evidence harnesses and fail-closed promotion scripts. That aligns with the principle that claims should be reproducible and bounded.

## Deductions and risks

### 1. `DbState` is an aggregate-state pressure point

`src/aarondb/shared/state.gleam` defines `DbState` with storage, three primary indexes, subscribers, schema, functions, composites, reactive actors, followers, distribution flags, vector/BM25/ART indexes, extension registries, predicates, stored rules, virtual predicates, columnar storage, configuration, and query history.

This is understandable as an actor snapshot, but it is a coupling magnet. Adding a feature means adding fields to the central state and widening the dependency surface of functions that receive it. The type is data-oriented, but it is not yet minimal data. It is the repository’s clearest place where “one database state” risks becoming “the whole product in one record.”

**Recommendation:** partition state by ownership: core transaction state, query/index state, reactive state, and optional extension registries. Compose them in the actor boundary rather than making every subsystem depend on the full `DbState`.

### 2. The transactor message vocabulary is broad

`src/aarondb/transactor.gleam` contains a large `Message` union spanning transactions, schema, functions, predicates, rules, reactive setup, joins, sync, compaction, boot, indexes, subscriptions, pruning, entity retraction, lifecycle ticks, and query history.

An actor message union is good data, but this one is approaching a product API and internal control plane at once. The risk is not the number of constructors alone; it is that unrelated capabilities share one serialization point and one state type.

**Recommendation:** keep the public transactor as a thin protocol adapter, but move optional control messages behind cohesive subprotocols or capability modules. Preserve one owner for core transaction ordering.

### 3. Oversized modules obscure the conceptual seams

The source tree contains 94 Gleam modules, but several important modules are much larger than the project’s preferred 250 LOC threshold. The largest observed files include:

| File | Lines | Concern |
|---|---:|---|
| `src/aarondb/vec_index.gleam` | 681 | index lifecycle, search, mutation, and algorithmic machinery |
| `src/aarondb/sharded.gleam` | 663 | routing, scatter/gather, aggregation, and shard behavior |
| `src/aarondb/transactor.gleam` | 591 | actor API, startup, message dispatch, and orchestration |
| `src/aarondb/raft_runtime.gleam` | 461 | protocol state plus multiple RPC transition families |
| `src/aarondb/raft.gleam` | 367 | broader Raft surface |
| `src/aarondb/consensus.gleam` | 332 | command submission, reads, leases, and helper machinery |

These are not automatically bad—protocol code can be cohesive—but they are review liabilities and make it harder to see the data model versus the orchestration around it.

**Recommendation:** split by semantic transformation, not arbitrary line count: types/state, command application, election, append/snapshot handling, lease transitions, and adapter orchestration.

### 4. “Pure model” and “runtime integration” need executable separation

The code and documentation make the distinction well in prose. `raft_runtime` says adapters persist `HardState` and deliver authenticated RPCs, while the module itself makes protocol decisions. That is excellent.

The certification gap is that the repository contains many runtime-facing modules and FFI surfaces alongside these reference models. A future contributor could accidentally promote a pure model into a deployment claim unless the boundary is enforced structurally.

**Recommendation:** make the boundary visible in module naming and dependency direction. Pure protocol modules should not import process, storage, network, or FFI modules. Add a lightweight architecture test or dependency check that fails if they do.

### 5. Local complexity is broad, even when claims are narrow

The codebase has 757 function declarations, 207 type declarations, and 593 imports across `src/aarondb`. Those numbers are not defects; they indicate a substantial system. But they confirm that whole-repository simplicity cannot be inferred from the elegant core.

The README’s “strong center and broad edge” diagnosis is correct. The certification should therefore attach to a named profile, not to AaronDB without qualification.

## What Rich Hickey would likely approve

- Datoms and query ASTs as data.
- Closed tagged unions for protocol commands, replies, and errors.
- Pure functions that transform explicit state.
- Caller-supplied quorum and monotonic-clock evidence rather than hidden environmental assumptions.
- Narrow, evidence-backed feature labels.
- Explicit rejection of distributed/HA claims that the current runtime cannot support.
- A local embedded boundary instead of premature network generalization.

## What would draw the sharp eyebrow

- A `DbState` that knows about nearly every subsystem.
- A transactor message union that mixes core mutation with many optional capabilities.
- 600+ line modules in the most important architectural areas.
- Compatibility and legacy APIs that remain broader or less bounded than the preferred contracts.
- A whole-repository certification label that ignores the difference between the Datalog core and experimental extensions.

## Prioritized action list

1. **Name the certification profile.** Certify “AaronDB embedded temporal Datalog core,” not the entire repository.
2. **Split aggregate state.** Introduce cohesive state records and compose them at the actor boundary.
3. **Split the largest modules.** Start with `transactor.gleam`, `raft_runtime.gleam`, `sharded.gleam`, and `vec_index.gleam`; preserve behavior with characterization tests.
4. **Enforce pure/runtime dependency direction.** Add a check preventing protocol reference modules from importing effectful adapters.
5. **Retire or isolate compatibility breadth.** Mark unbounded legacy paths as compatibility-only in both API naming and documentation.
6. **Keep evidence profiles separate.** Do not let local test evidence become a distributed maturity claim.


## 2026-08-11 certification result

The dated final report is
[Rich Hickey Certification Evidence — `embedded-core-v1`](reviews/rich-hickey-certification-evidence-2026-08-11.md).
It records a **10/10 structural verdict for the named embedded-core profile**,
not for the repository’s distributed or experimental surfaces. That profile
passed formatting, type checking, documentation, boundary fixture checks, its
fail-closed verifier, diff hygiene, and the full **319-test** suite.


**AaronDB earns a conditional Rich Hickey certification for its embedded local Datalog core.** Its best design choices are data-first modeling, explicit state transitions, composable query components, and unusually disciplined claim boundaries. The repository as a whole remains too broad and too centrally coupled for an unconditional simplicity certification. The next improvement is architectural pruning and boundary enforcement—not another feature.

> Rich Hickey check: **the core is data and the claims are honest; the remaining work is to make the boundaries as simple as the ideas.**
