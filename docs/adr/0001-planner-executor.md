# ADR 0001: Planner and Executor Phases

## Status

Accepted

## Context

`engine.gleam` previously mixed query optimization, clause iteration, result shaping, and clause solving in one function. That made further extraction difficult because every concern had to understand the full solver call shape.

## Decision

Split query execution into explicit phases:

- `engine/planner.gleam` builds a `QueryPlan`, collects aggregate metadata, and owns top-level ordering/pagination helpers.
- `engine/executor.gleam` executes planned clauses over binding contexts and delegates unknown clauses through a solver callback.
- `engine/solver_context.gleam` carries the database state, rules, derived facts, and temporal basis through solver boundaries.

The initial implementation preserves existing clause semantics. It changes boundaries, not behavior.

## Consequences

- `engine.run` is now orchestration code rather than a full interpreter loop.
- Specialized clause modules can remain independent of planner/executor mechanics.
- Aggregate and temporal solving can be extracted later using `SolverContext`, but should remain in `engine.gleam` until their callback contract is clearer.
