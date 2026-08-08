# Changelog

## 4.0.0 - 2026-08-08

A **breaking hardening release** that makes AaronDB's serialization, actor, vector, persistence, and deployment boundaries explicit.

### Added

- A local newline-delimited JSON-RPC stdio MCP adapter for `initialize`, `tools/list`, and the implemented `muninn_remember`, `muninn_recall`, and `muninn_read` tools.
- Apache-2.0 `LICENSE` and `SECURITY.md` with private vulnerability-reporting guidance and the supported local deployment boundary.
- CI checks for `gleam docs build` and GitHub Actions workflow linting via `actionlint`.
- Regression coverage for malformed term payloads and vector-dimension mismatch handling.

### Changed

- Rule and raw ETS term decoding now uses safe Erlang external-term decoding and returns `Result`, rejecting malformed or wrong-shaped payloads.
- Actor startup observes its caller-provided timeout; schema, composite, rule, transaction, and retraction calls return explicit timeout errors instead of asserting on missing replies.
- HNSW vector indexes establish a fixed dimension from the first vector. Mismatched insertions and searches are rejected; retrieval ignores incompatible vectors rather than silently truncating scores.
- Mnesia initialization preserves an incompatible `datoms` table and returns a descriptive error. Operators must back up and migrate—or deliberately reset—the table themselves.
- The former unwired MuninnDB-derived cognitive scoring/types were removed; `engine/cognitive` is the single authoritative cognitive model.
- Documentation now defines local-only MCP, recovery-oriented Mnesia, local-Beta sharding, and inactive Raft as the current supported boundary.

### Breaking changes

- `aarondb/index/ets.deserialize_term` now returns `Result(dynamic.Dynamic, Nil)` instead of `dynamic.Dynamic`.
- `storage/mnesia.init_mnesia` now returns `Result(Nil, String)` instead of `Nil`.
- `VecIndex` now carries an index dimensionality contract; callers needing diagnostics should use `try_insert` and `try_search`.

### Verification

- `gleam format --check src test bench`
- `gleam build`
- `gleam docs build`
- `actionlint`
- `gleam test`: 178 passed, no failures.

## 3.0.0 - 2026-08-04

A **breaking** cleanup release that removes the experimental CMS product surface and vestigial consensus scaffolding.

### Removed

- The experimental **GleamCMS layer** (`src/aarondb/gleamcms*`, `gleamcms_httpc_ffi.erl`) — a self-contained mist/wisp/lustre HTTP/CMS surface never imported by the core, tests, or MCP layer.
- The dead `aarondb_raft_ffi.erl` Erlang timer stub (never `@external`-linked).
- The inert public `aarondb.is_leader(db)` API and the `raft_state` field on `DbState` (raft demoted to a stub).
- 9 now-unused dependencies: mist, wisp, lustre, gleam_http, simplifile, gleam_regexp, gleam_crypto, logging. Direct deps 13→4; manifest packages 25→5.

### Changed

- Bumped `gleam_stdlib` 0.69.0 → 1.0.3 (major, zero breakage); `gleeunit` 1.9.0 → 1.11.0.
- `src/aarondb/raft.gleam` is now a documented, unwired clustering stub (election-only; no log replication).

### Verification

- `gleam format --check src test bench`
- `gleam test`: 169 passed, no failures.

## 2.4.5 - 2026-07-04

### Changed

- Added an explicit GitHub Actions workflow name and release permissions to finalize autonomous GitHub release creation.

### Verification

- `gleam format --check src test bench`
- `gleam test`: 169 passed, no failures, no warnings.
- Release workflow configured with current Gleam, OTP 27, rebar3, `HEX_API_KEY`, and `contents: write` permissions.

## 2.4.4 - 2026-07-04

### Changed

- GitHub Actions workflows now use OTP `27`, matching the runtime requirement of the current dependency graph.

### Verification

- `gleam format --check src test bench`
- `gleam test`: 169 passed, no failures, no warnings.
- Release workflow configured with current Gleam, OTP 27, rebar3, and `HEX_API_KEY` for autonomous Hex publishing.

## 2.4.3 - 2026-07-04

### Changed

- GitHub Actions workflows now install `rebar3`, fixing autonomous CI and Hex publishing for dependencies that require Rebar3.

### Verification

- `gleam format --check src test bench`
- `gleam test`: 169 passed, no failures, no warnings.
- Release workflow configured with `HEX_API_KEY` and `rebar3` support for autonomous Hex publishing.

## 2.4.2 - 2026-07-04

### Changed

- Updated GitHub Actions workflows to use Gleam `1.17.0` so autonomous release automation matches the current codebase.

### Verification

- `gleam format --check src test bench`
- `gleam test`: 169 passed, no failures, no warnings.
- Release workflow configured with `HEX_API_KEY` for autonomous Hex publishing.

## 2.4.1 - 2026-07-04

### Added

- `engine/solver/derived.gleam` for derived-clause handling.
- `engine/solver/vector_input.gleam` for vector-target extraction.

### Changed

- `engine.gleam` reduced from 317 to 296 lines.
- Solver glue moved out of `engine.gleam` into dedicated modules.

### Verification

- `gleam format --check src test bench`
- `gleam test`: 169 passed, no failures, no warnings.

## 2.4.0 - 2026-07-04

### Added

- Solver dispatch extracted into `engine/solver/core.gleam`.
- Transactor message helper module `transactor/messages.gleam`.
- Direct unit tests for extracted solver and transactor modules.
- Contributor guide documenting the green-slice workflow.
- Release workflow now builds docs and optionally publishes to Hex.

### Changed

- `engine.gleam` reduced from 546 to 317 lines.
- `transactor.gleam` reduced from 534 to 504 lines.
- Benchmarks remain outside the default test suite in `bench/`.

### Verification

- `gleam format --check src test bench`
- `gleam test`: 169 passed, no failures, no warnings.

## 2.3.0 - 2026-07-04

### Added

- Solver protocol with explicit modules for bindings, stores, triple solving, positive solving, and recursive orchestration under `engine/solver/`.
- Transactor domain modules: `lifecycle.gleam` (tick/eviction), `schema.gleam` (schema validation), `runtime.gleam` (transaction handling), `apply.gleam` (datom application), `validation.gleam` (constraint validation).
- Rule derivation extracted to `engine/rules.gleam`.
- Aggregate and temporal clause solving extracted to dedicated modules.
- CI workflow for format checking and testing.
- Release workflow with version verification.
- Benchmark moved to `bench/` directory, separated from default test suite.
- ADR 0001 for planner/executor architecture.

### Changed

- `engine.gleam` reduced from 2174 to 546 lines.
- `transactor.gleam` reduced from 1130 to 534 lines.
- Feature docs updated with experimental maturity warnings.
- All test warnings cleaned.
- Planner and executor test coverage expanded.

### Verification

- `gleam test`: 161 passed, no failures, no warnings.

## 2.2.0 - 2026-07-04

### Added

- Planner and executor phases for query execution.
- Explicit `SolverContext` for carrying solver state through execution boundaries.
- Focused engine modules for entity/pull, traversal, predicates, graph clauses, retrieval, string prefix clauses, virtual predicates, and cognitive solving.
- Feature maturity and project boundary documentation.
- ADR 0001 documenting the planner/executor architecture.
- Unit tests for planner and executor behavior.

### Changed

- Re-centered README and architecture docs around the implemented temporal Datalog core.
- Reduced `engine.gleam` to orchestration, rule derivation, core solving, aggregate coordination, and temporal coordination.
- Updated documentation to distinguish stable core features from beta and experimental extension layers.

### Fixed

- Removed a source warning in `engine/prefetch.gleam`.
- Corrected README examples to match exported APIs.

### Verification

- `gleam test`: 147 passed, no failures.
