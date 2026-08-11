# Rich Hickey Certification — Path to 10/10

**Date:** 2026-08-09
**Repository:** `~/Desktop/gleamdb`
**Scope:** The embedded temporal Datalog core and the architecture surrounding it.

## Decision

A **10/10 does not mean fewer features** and does not mean pretending the distributed work has more evidence than it has. It means the repository makes a sharp distinction between:

1. **the small, dependable core** — facts, schema, transaction normalization/validation/application, query AST, and deterministic query evaluation;
2. **pure optional models** — HNSW, Raft transition logic, routing plans; and
3. **effectful adapters** — actors, storage, processes, FFI, remote transport, telemetry, and experimental product surfaces.

The previous certification score was **7.7/10**. The gap is primarily architectural coupling and module cohesion, not an absence of testing or data-oriented design.

## Certification target

| Dimension | Current | 10/10 condition |
|---|---:|---|
| Data orientation | 9 | Every important behavior accepts and returns explicit data; runtime capabilities do not leak into domain records. |
| Explicit transitions | 8 | Transaction, index, routing, and consensus decisions are pure transformations with effects applied by a thin interpreter. |
| Boundary clarity | 7 | Core, optional models, and runtime adapters have one-way dependencies verified mechanically. |
| Essential simplicity | 8 | The certified core can be explained, initialized, tested, and embedded without importing optional product subsystems. |
| Semantic precision | 8 | APIs distinguish stable core, compatibility paths, experimental features, and unsupported operations in names and types. |
| Module cohesion | 5 | Large modules have one state owner/protocol each; source layout reflects actual transformations rather than historical accumulation. |
| Verification | 9 | Characterization, property, and dependency-direction tests guard every extraction and public semantic contract. |

## Required work packages

### 1. Make the core a real package boundary — **highest leverage**

**Problem:** `shared/state.DbState` is a 23-field actor snapshot. It includes durable facts/indexes/schema alongside reactive subjects, vector/BM25/ART indexes, extension registries, virtual predicates, columnar storage, distribution flags, query history, and tuning configuration. Every function receiving it sees the entire product.

**Change:** replace the one-record-everything model with cohesive state values:

| New state | Owns | Must not own |
|---|---|---|
| `CoreState` | datom indexes, schema, transaction sequence, durable storage identity | actor subjects, extension registries, telemetry |
| `QueryState` | query-only indexes and query configuration | transaction lifecycle or process handles |
| `ExtensionState` | index adapters, extensions, predicates, stored rules, virtual adapters | core persistence or actor routing |
| `RuntimeState` | subscribers, reactive actor, followers, lifecycle/telemetry | domain rules and index implementation details |
| `DbState` / actor snapshot | composition of the above at the one mutation-owner boundary | new subsystem-specific fields |

The exact names can differ. The non-negotiable rule is **ownership**, not a cute record taxonomy.

**Acceptance criteria:**
- A core transaction/query test imports neither `gleam/erlang/process` nor optional vector/extension modules.
- Adding an extension does not add a field to the core state record.
- `compute_next_state` operates over `CoreState` plus an explicit extension policy/value, not an ambient all-product record.

### 2. Turn the transactor into an interpreter, not the product junk drawer

**Problem:** `transactor.gleam` has a 21-case `Message` union and mixes public API wrappers, startup/boot, global registration, lifecycle ticking, pure transition construction, storage orchestration, dispatch, and optional controls.

**Change:** retain exactly one actor that serializes core writes, but separate its protocol by responsibility:

- `transactor/api.gleam`: typed client wrappers and deadlines.
- `transactor/command.gleam`: data-only core write requests and replies.
- `transactor/transition.gleam`: pure transaction resolution → datom construction → state transition → validation result.
- `transactor/handler.gleam`: actor dispatch/interpreter, persistence, notification, and reply delivery.
- `transactor/bootstrap.gleam`: startup, recovery, naming, Mnesia/ETS setup, lifecycle wiring.
- `transactor/admin.gleam`: schema/rules/index configuration, explicitly outside the minimal write protocol.

The current `apply`, `validation`, `schema`, `messages`, `runtime`, and `lifecycle` modules are a useful start. Finish the cut: the root `transactor.gleam` should become a small façade, not retain `compute_next_state` and the full dispatch switch.

**Acceptance criteria:**
- The public core command union contains only core data changes and reads needed to coordinate them.
- Admin/extension operations use a distinct capability/protocol, so they cannot silently become part of transaction ordering semantics.
- Pure transition tests need no actor, storage backend, process subject, or wall-clock timeout.

### 3. Split algorithm modules by transformation, preserving deterministic oracles

**Problem:** `vec_index.gleam` (681 LOC) combines configuration, random/deterministic level sources, input validation, node insertion, layer-link repair, approximate traversal, exhaustive oracle search, delete/repair, and public compatibility APIs. The exact oracle is excellent but is buried in the implementation aggregate.

**Change:** split by actual algorithmic role:

| Module | Responsibility |
|---|---|
| `vector/hnsw_types` | `VecIndex`, layer/config/result data, deterministic level-source data |
| `vector/hnsw_validate` | dimension, magnitude, threshold, and `k` validation |
| `vector/hnsw_build` | insertion, level choice, neighbor selection, edge repair |
| `vector/hnsw_search` | greedy traversal and bounded approximate search |
| `vector/hnsw_oracle` | deterministic exhaustive search and equivalence/comparison helpers |
| `vector/hnsw_delete` | deletion and layer/entry-point repair |

Do **not** extract generic abstractions merely to chase line count. Keep direct data flow; share only stable representations and obvious helpers.

**Acceptance criteria:**
- Deterministic search oracle is independently testable and remains the benchmark/test authority for bounded corpora.
- Randomness/level selection is injected as data (`LevelSource`), never hidden ambient behavior.
- Approximate search quality tests state corpus, configuration, seed, and comparison rule explicitly.

### 4. Separate sharding semantics from same-runtime process orchestration

**Problem:** `sharded.gleam` (663 LOC) mixes vnode routing, shard startup, process spawning, scatter/gather transaction/query work, aggregate reduction, vector result merge, lifecycle termination, migration planning, and deliberately unsupported migration/rebalance APIs.

**Change:** introduce a pure routing/model layer and a runtime coordinator:

- `sharding/routing.gleam`: vnode map creation and entity → shard routing, fully pure.
- `sharding/plan.gleam`: `MigrationPlan` calculation and invariants, fully pure.
- `sharding/reduce.gleam`: result merge, aggregate reduction, deterministic top-k tie breaking.
- `sharding/runtime.gleam`: local actor/process fan-out, deadlines, startup, stop.
- `sharding/unsupported.gleam` or remove APIs entirely: explicit unsupported operations only if compatibility requires them.

**Critical semantic fix:** `add_shard` changes routing for future writes while historical data remains unmigrated. Either make that condition prominent in the type/API name or keep it out of the certified profile. It must never masquerade as ordinary elastic sharding.

**Acceptance criteria:**
- Routing, migration planning, and reduction execute without processes, storage, or transactor subjects.
- Global vector merge has deterministic secondary ordering for equal scores.
- “Unsupported” functions are not presented alongside completed operational APIs as if they are half a feature.

### 5. Enforce model → adapter dependency direction mechanically

**Problem:** The repo documents the pure/runtime distinction well—`raft_runtime` is mostly a pure state machine, while `cluster_runtime` handles actor/FFI/transport integration—but prose is not a guardrail.

**Change:** define and test these layers:

```text
core data/query/transaction model
       ↓
optional pure models (HNSW, Raft, sharding routing)
       ↓
adapters (storage, actor, telemetry, FFI, transport, MCP)
       ↓
applications / integration entrypoints
```

Pure layers must not import `gleam/erlang/process`, `gleam/otp`, storage adapters, FFI declarations, or network/cluster integration modules. Effects point inward only through explicit inputs/outputs.

**Acceptance criteria:**
- Add a repository dependency test/script that rejects forbidden imports in declared pure modules.
- `raft_runtime` is either split by RPC family (`election`, `append`, `snapshot`, `membership`) or has a documented reason to remain cohesive as the one Raft transition algebra.
- `cluster_runtime` remains the effectful interpreter; it does not grow domain decisions already represented in `raft_runtime`.

### 6. Give compatibility APIs an honest perimeter

**Problem:** Some convenience wrappers intentionally assert or hide timeout/error channels (for example, compatibility reads). They are reasonable migration aids but make it easier to use the less explicit contract by default.

**Change:**

- Make result-returning, deadline-explicit functions the obvious/default APIs.
- Place assertion-based wrappers in a `compat` module or rename them with a compatibility/deprecated signal.
- Prevent certified-core modules from depending on compatibility APIs.

**Acceptance criteria:**
- New examples and internal callers use explicit `Result` + deadline contracts.
- Compatibility use is grep-auditable and constrained to documented adapters/examples.

### 7. Define the certification profile as executable selection, not prose

**Problem:** “Local Datalog core” is currently a strong description, but certification should be reproducible as a selection of modules and tests.

**Change:** create a named profile, e.g. `embedded-core-v1`, containing:

- module allowlist;
- supported storage configurations;
- core public API surface;
- excluded optional modules/features;
- required characterization/property tests;
- dependency-direction check;
- performance/non-claim boundary.

The profile should explicitly exclude distributed runtime, operational sharding, MCP integration, RAG/cognitive surfaces, and any experimental indexing feature unless it independently meets the same conditions.

**Acceptance criteria:**
- One command validates the profile: format, check, profile tests, architecture dependencies, and API-surface snapshot.
- Release documentation uses “certified under `embedded-core-v1`,” never “the repository is 10/10.”

## Work ordering

1. **Characterize before moving code:** capture current transaction/state, vector oracle, routing, and public API behavior in tests.
2. **Extract `CoreState` and pure transaction transition:** this reduces coupling across everything else.
3. **Finish transactor interpreter split:** remove all-product protocol pressure from the core mutation path.
4. **Extract HNSW oracle/search/build seams:** preserve deterministic evidence while reducing algorithmic opacity.
5. **Extract pure sharding routing/reduction:** do not implement migration/rebalance as part of this certification work.
6. **Add mechanical architecture checks and profile runner.**
7. **Re-run the audit against the profile and only award 10/10 if the whole profile passes.**

## Explicit non-goals

These are **not** prerequisites for 10/10 certification of `embedded-core-v1`:

- Completing multi-host Raft/HA proof.
- Making sharding operationally elastic or implementing migration/rebalance.
- Achieving a universal vector recall/latency number.
- Deleting all large files just to satisfy a numeric LOC rule.
- Rewriting working Gleam code into a more fashionable architecture.
- Collapsing useful data types into generic maps or callback soup.

Those would be classic accidental-complexity traps: solving a different problem while claiming simplicity.

## Verification gates

Every extraction must preserve behavior and add a test at the newly visible boundary:

| Gate | Evidence |
|---|---|
| Behavior preservation | Existing test suite plus characterization tests pass before/after each logical extraction. |
| Transition purity | Core transition tests run with no actor, storage adapter, subject, process, or FFI setup. |
| Dependency direction | Automated forbidden-import check passes for every declared pure module. |
| Determinism | Vector/routing/reduction tests assert tie-breaking, seed/config, and output ordering. |
| API precision | Certified profile exposes timeout/error-aware APIs; compatibility paths are excluded. |
| Claim discipline | Docs and release profile enumerate exclusions and no unsupported distributed claim leaks into certification. |


## Implemented status — 2026-08-11

The certification work packages are complete for `embedded-core-v1`. The public
`DbState` was not destructively replaced; it now has a total ownership
projection, with a later breaking-release migration intentionally deferred.
The final [certification evidence](rich-hickey-certification-evidence-2026-08-11.md)
records all green gates and the narrow 10/10 verdict. Broader distributed,
independent-host, WAN, soak, and upgrade evidence remains outside this profile.


Award **10/10 only when** the named embedded-core profile has a small dependency closure, explicit data/state transformations, a thin effect interpreter, mechanical boundary enforcement, deterministic tests for its algorithmic contracts, and a clearly fenced compatibility/experimental perimeter.

> Rich Hickey check: the move is not “make it more abstract.” It is **make the data ownership and effect boundaries obvious enough that the system cannot lie about what it is.**
