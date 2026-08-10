# Production Maturity Promotion Audit

**Audit date:** 2026-08-10 UTC  
**Repository:** `moneyacademyKE/gleamdb`  
**Working tree baseline:** `a61f1066b3c429eea0758adff94b2a9172d06797` plus dirty local-stability edits and untracked distributed-reference work  
**Scope:** production promotion obligations for the durable/distributed wishlist only

## Verdict matrix

| Obligation | Status | Source / current evidence | Reproducible producer | Gap |
|---|---|---|---|---|
| Authenticated multi-node runtime | GO (scenario) | Three separate BEAM VMs; TLS runner reports election, redirect, follower convergence, unauthorized peer rejection | `sh scripts/verify_tls_cluster.sh` | Scenario proof is not sustained availability evidence |
| Durable recovery | GO (tested adapter) | Checksummed/fsync recovery-image tests, torn-write refusal, compaction and backup tests | `gleam test` (tests `raft_durability`) | No release-profile crash/power-loss campaign |
| Data-plane correctness | GO (tested contract) | 302-test suite covers commit visibility, CAS/idempotency, fences, cursors, projections, indexes, status | `gleam test` | No production workload envelope |
| Deterministic safety corpus | GO (library oracle) | Fixed-seed harness and known-bad mutants | `sh scripts/verify_distributed_harness.sh` | Not an independent black-box chaos campaign |
| Release-specific SLOs | BLOCKED | No versioned thresholds or supported hardware/runtime profile exists | None | Must define machine-readable thresholds and assumptions |
| Sustained latency/throughput evidence | NO-GO | Soak repeats correctness tests; no p50/p95/p99 or throughput samples | `AARONDB_SOAK_ITERATIONS=5 sh scripts/verify_cluster_soak.sh` | Workload and percentile artifacts absent |
| Resource budgets | NO-GO | Soak report asserts bounded growth but collects no RSS, CPU, disk, queue, or lag metrics | Same soak command | Assertion is undocumented optimism, not measurement |
| Destructive black-box chaos | NO-GO | Checked-in deterministic oracle exists; TLS runner exercises only one happy-path cluster scenario | `sh scripts/verify_distributed_harness.sh` | Missing independent partition/crash/disk/RPC/rotation/recovery artifacts |
| Operator packaging | BLOCKED | Runbook documents procedures but explicitly says packaging must expose equivalent commands | No executable operator CLI | Bootstrap/status/recovery/rotation/diagnostics need tested commands and exit codes |
| Fail-closed promotion gate | BLOCKED | CI runs format/docs/tests/actionlint and distributed scripts; no SLO, freshness, chaos, or runbook validator | `.github/workflows/ci.yml` | Compose one gate that rejects absent/stale/incomplete evidence |
| Release witness and review | NO-GO | `docs/releases/production-readiness-review-2026-08-09.md` records NO-GO | Review document | Witness must be generated from current commands and redacted artifacts |
| Local-stability isolation | GO | Tracked unrelated edits are identifiable and excluded from distributed manifest | `git diff --name-only`; manifest | Worktree is dirty; no commit/push/release may be inferred |

## Evidence inventory and claim corrections

The distributed modules and tests are present under `src/aarondb/` and
`test/aarondb/`, with the experimental manifest at
`docs/releases/durable_distributed_experimental.md`. The current checked-in
artifacts prove a local two-iteration run, not the configured five-iteration CI
profile. The artifact log records 302 passing tests and TLS integration, but it
contains no machine-readable latency, throughput, resource, lag, recovery-time,
or error-rate measurements.

`verify_cluster_soak.sh` currently calls the deterministic harness repeatedly
and then writes unconditional resource-growth and failover statements. Those
lines must not be treated as measurements. The script also defaults to five
iterations, while the current local report contains two. This is a concrete
fail-closed evidence defect for the next task.

The runbook is useful as a library/runtime procedure, but it explicitly states
that production packaging is still required. There is no operator command
surface in `scripts/` for bootstrap, status, backup/restore verification,
identity rotation/revocation, rebuild, or redacted incident collection.

The current maturity documents are honest: the distributed row remains
**Experimental reference library**, and the prior release review is **NO-GO**.
No unqualified production-ready claim was found in the audited maturity and
release documents.

## Excluded worktree changes

These pre-existing tracked local-stability edits are outside this promotion
stream and must remain isolated:

- `.github/workflows/ci.yml` (shared CI edits require careful merge review)
- `docs/features/ai_architect.md`
- `docs/manual/mcp_stdio.md`
- `docs/performance_guide.md`
- `docs/specs/agent_memory_context.md`
- `docs/specs/gleam_datalog.md`
- `docs/specs/gleam_vs_cozo.md`
- `src/aarondb.gleam`
- `src/aarondb/storage/mnesia.gleam`
- `src/aarondb/transactor.gleam`
- `src/aarondb_mnesia_ffi.erl`
- `test/aarondb/ergonomics_test.gleam`

The distributed-reference files, ADRs, manuals, scripts, and artifacts are
untracked additions and are not to be mixed with those baseline edits in a
release or commit.

## Commands actually run for this audit

- `pwd && git status --short && git diff --stat`
- `git diff -- .github/workflows/ci.yml docs/evidence.md docs/feature_maturity.md`
- `gleam format --check src test bench` (recorded in existing harness artifact)
- `gleam check` (recorded in existing harness artifact)
- `gleam test` — 302 passed (recorded in existing harness artifact)
- `sh scripts/verify_tls_cluster.sh` (recorded in existing harness artifact)
- `sh scripts/verify_distributed_harness.sh` (recorded in existing harness artifact)
- `AARONDB_SOAK_ITERATIONS=2 sh scripts/verify_cluster_soak.sh` (recorded in current soak report)

## Next promotion gate

Do not promote the maturity label. First define a named release profile with
thresholds and a validator, replace unconditional soak assertions with measured
artifacts, add destructive black-box scenarios and operator commands, then
compose a fail-closed gate and generated witness. Until those artifacts exist,
the defensible verdict remains **NO-GO**.
