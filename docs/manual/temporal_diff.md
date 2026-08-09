# Temporal Querying and Diff Contract

AaronDB supports **local, single-runtime** temporal reads over its in-memory
transaction history. This document describes the supported contract; it does
not promise remote history, globally consistent snapshots, replication, or
unbounded historical scans.

## Two independent axes

Every datom has both a transaction id (`tx`) and a valid-time integer
(`valid_time`).

- **Transaction time** answers: “what had been committed by transaction T?”
- **Valid time** answers: “which facts are valid at business time V?”

They are independent filters. `aarondb.as_of`, `aarondb.as_of_valid`, and
`aarondb.as_of_bitemporal` apply them to a complete query. A temporal AST
clause applies the corresponding basis to its nested clauses.

## Point-in-time query builder helpers

`q.temporal_at(variable, entity, tx)` and
`q.valid_temporal_at(variable, entity, valid_time)` create exact `At` clauses.
They do **not** accept an ignored end bound and do not claim interval support.

Point-in-time limits are inclusive: a datom is visible when its transaction id
or valid time is less than or equal to the requested basis. A basis before the
first matching fact produces no matching rows. Results use normal query
ordering; callers requiring a specific order must use `q.order_by`.

## Supported bounded snapshots

Use `aarondb.temporal_scan_limits(max_datoms)` to construct a positive local
history budget, then call `as_of_bounded`, `as_of_valid_bounded`, or
`as_of_bitemporal_bounded`. These return `InvalidTemporalScanLimit` for a
non-positive limit and `TemporalScanBudgetExceeded` when the current local
EAVT history is larger than the declared budget. They never return partial
rows.

`as_of`, `as_of_valid`, and `as_of_bitemporal` remain compatibility APIs with
no scan limit. They are not the supported Stable path for history-heavy reads.

## Diff

`aarondb.diff_bounded(db, from_tx, to_tx, limits)` is the supported local
history API. It reports a complete, deterministically transaction-ordered
change set for `(from_tx, to_tx]`, or one typed error: `InvalidDiffRange` when
`from_tx >= to_tx`, `InvalidDiffScanLimit` for non-positive scan budgets, or
`DiffScanBudgetExceeded` when the current local EAVT history exceeds the
caller-declared limit. It never returns a partial change set.

The legacy `aarondb.diff` remains compatibility-only: it has no scan budget
and makes no ordering promise beyond the included transaction range.

## Non-goals

This contract excludes remote queries, distributed/global snapshots, temporal
replication, retention guarantees, coordinated writes, Raft activation, and
universal performance claims.
