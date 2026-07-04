# Contributing

AaronDB uses a small-step refactoring and verification workflow.

## Preferred Workflow

1. Start from the smallest correct change.
2. Keep behavior unchanged while extracting modules.
3. Run `gleam format src test bench` after edits.
4. Run `gleam test` after each substantive extraction batch.
5. Update docs when architecture boundaries change.
6. Prefer focused modules over expanding `engine.gleam` or `transactor.gleam`.

## Architectural Rules

- Planner and executor own query orchestration.
- Solver modules own clause-solving mechanics.
- Clause-specific features live in dedicated modules.
- Transactor domain logic should stay in focused helper modules.
- Benchmarks belong in `bench/`, not the normal test suite.

## Release Expectations

- `gleam format --check src test bench`
- `gleam test`
- version bump in `gleam.toml`
- changelog update
- tag must match the package version
