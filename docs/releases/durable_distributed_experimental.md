# Durable/Distributed Experimental Release Manifest

## Scope and baseline

This manifest records the library-only durable/distributed evolution separately
from the pre-existing local-stability worktree changes. It is deliberately not a
release announcement, a production-readiness claim, or a compatibility change
to `aarondb.new()`.

The baseline local-stability changes remain the tracked modifications present
before this evolution (MCP stdio, Mnesia recovery, local evidence, and related
core files). The experimental layer consists exclusively of the new modules,
tests, ADRs, and manuals listed below. Neither group is to be staged, committed,
or reviewed as a mixed change.

## Release slices

| Slice | Library modules | Tests | Contract/docs | Evidence gate |
| --- | --- | --- | --- | --- |
| Durable log | `durable_log` | `durable_log_test` | ADR 0004; `manual/durable_log.md` | ordered offsets, retention expiry, snapshot validation, atomic checkpoint failure |
| Changefeed and projection | `changefeed`, `projection` | `changefeed_test`, `projection_test` | ADR 0005; `manual/durable_projections.md` | resumable snapshot-then-tail, duplicate delivery, credits, replay, rebuild/swap |
| Signed envelopes | `envelope`, `aarondb_envelope_ffi` | `envelope_test` | ADR 0006; `manual/signed_envelopes.md` | canonical-frame mutation, domain separation, key rotation and revocation |
| Deterministic commands | `command` | `command_test` | ADR 0008; `manual/commands.md` | idempotency, replay determinism, committed CAS, fencing issuance |
| Durable authenticated Raft | `raft_runtime` | `raft_runtime_test` | ADR 0007; `manual/consensus.md` | recovery, quorum election/commit, catch-up, snapshots, ReadIndex, membership |
| Consensus leases | `consensus` | `consensus_test` | ADR 0009; `manual/consensus.md` | quorum loss, leader redirects, monotonic lease expiry, renewal/revocation, stale fences |
| Node identity and recovery | `identity` | `identity_test` | ADR 0010; `manual/identity_operations.md` | certificate binding/trust lifecycle, authorization, bounded RPC, persistent alarms |
| Projection indexes and operations | `projection_index`, `operations` | `projection_index_operations_test` | `manual/durable_projections.md`, `manual/identity_operations.md` | ordered application, safe full-catch-up swap, non-queryable degradation, truthful health |
| Adversarial gate | `distributed_harness` | `distributed_harness_test` | `manual/distributed_harness.md` | deterministic partition, crash, reorder, slow follower, churn, skew and known-bad mutants |

## Global evidence

- [Production readiness review (2026-08-09)](production-readiness-review-2026-08-09.md): NO-GO for production maturity; evidence keeps the distributed modules Experimental.

- `AARONDB_HARNESS_ARTIFACT_DIR=artifacts/distributed-harness sh scripts/verify_distributed_harness.sh`
- `AARONDB_SOAK_ITERATIONS=5 sh scripts/verify_cluster_soak.sh`
- `sh scripts/verify_tls_cluster.sh`
- `docs/reports/cluster-soak-evidence.md` and generated `artifacts/cluster-soak/`
- [Production readiness review](production-readiness-review-2026-08-09.md): the current decision is **NO-GO** for production maturity.

The repository CI runs formatting, generated documentation, and the entire test
suite, including distributed-harness mutants. A green result is evidence for
the reference-library contracts only; it is not evidence of a deployed
multi-node system.

## Claim boundary

The durable/distributed APIs are experimental and opt-in. The legacy
`aarondb/raft` election-only module remains inactive and must not be confused
with `aarondb/raft_runtime`. Existing Stable labels remain local labels until a
separate release verifies an integrated transport, durable storage adapter, and
production fault evidence.
