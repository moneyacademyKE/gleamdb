# Durable/Distributed Cluster Promotion Manifest

## Scope and baseline

This manifest records the production-cluster promotion separately from the embedded local API. It is **not** a claim that `aarondb.new()` has changed its local support boundary, nor a retagging of the existing `v4.1.0` release.

The profile-bounded cluster runtime was promoted by the fail-closed gate at commit `92d9a73`. The promotion applies only to the stated three-node mTLS topology, versioned SLO profile, workload envelope, chaos corpus, and operator lifecycle contract. See the [current release review](production-readiness-review-2026-08-09.md) and [promotion gate](cluster-promotion-gate.md).

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

- [Promotion review (2026-08-10)](production-readiness-review-2026-08-09.md): **GO** for the profile-bounded cluster runtime at `92d9a73`.
- [Fail-closed promotion gate](cluster-promotion-gate.md): validates SLO profile, 10,000-operation evidence, chaos corpus, operator lifecycle, source checks, and immutable source identity.

- `sh scripts/verify_cluster_promotion.sh`
- `AARONDB_HARNESS_ARTIFACT_DIR=artifacts/distributed-harness sh scripts/verify_distributed_harness.sh`
- `AARONDB_SOAK_ITERATIONS=5 sh scripts/verify_cluster_soak.sh`
- `sh scripts/verify_tls_cluster.sh`
- `docs/reports/cluster-soak-evidence.md` and generated `artifacts/cluster-soak/`

The repository CI runs formatting, generated documentation, and the entire test
suite, including distributed-harness mutants. The promotion gate adds release-profile
performance, resource, recovery, chaos, operator, source-identity, and witness checks.

## Claim boundary

The durable/distributed APIs are profile-bounded and opt-in. The legacy
`aarondb/raft` election-only module remains inactive and must not be confused
with `aarondb/raft_runtime`. The promotion applies to the authenticated
three-node runtime and versioned evidence envelope, not to arbitrary hardware,
WAN deployment, unmeasured fault modes, or a silent compatibility change to the
embedded local API.
