# Changelog

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
