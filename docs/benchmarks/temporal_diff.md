# Temporal querying and diff benchmark evidence

Run from the repository root:

    gleam run -m temporal_diff_benchmark

The harness creates one in-memory AaronDB actor in one local BEAM process,
commits 250 transactions across 25 entities, then measures 100 bounded
transaction-time snapshots and 100 bounded diff scans. It is reproducible
regression evidence, not a portable latency, retention, capacity, or
concurrency guarantee.

## Method

- **History:** 250 asserted datoms, one per transaction.
- **Entities:** IDs cycle across 25 entities.
- **Snapshot:** `as_of_bounded` at the latest transaction with a scan budget of
  260 datoms.
- **Diff:** `diff_bounded` from the first through the latest transaction with
  the same 260-datom budget.
- **Samples:** 100 sequential operations per API after setup, using the
  process-local monotonic system-time clock.

The output records setup time plus total, p50, and p95 integer-millisecond
samples. A rendered `0 ms` means the operation completed below the harness
clock resolution; it is **not** a sub-millisecond production SLA.

## Recorded local run

Environment: macOS, local Gleam/Erlang toolchain. Command:
`gleam run -m temporal_diff_benchmark`.

| Measure | Result |
| --- | ---: |
| Setup 250 transactions | 21 ms |
| Temporal snapshot total / p50 / p95 (100 samples) | 7 / 0 / 0 ms |
| Bounded diff total / p50 / p95 (100 samples) | 0 / 0 / 0 ms |

The integer-millisecond clock rounded the p50/p95 samples to zero. That is a
measurement-resolution limit—not a performance promise.

## Boundaries

- The harness proves only the stated local, in-memory envelope.
- It does not exercise Mnesia recovery, distributed history, concurrent
  mutation, retention pruning, remote snapshots, or global ordering.
- Every measured API is bounded: a history larger than the caller-provided
  budget returns a typed error rather than a partial result.
- Re-run this command on the deployment environment before making capacity or
  latency decisions.
