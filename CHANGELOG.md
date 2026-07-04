# Changelog

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
