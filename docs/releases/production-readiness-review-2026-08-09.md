# Production Readiness Release Review

**Review date:** 2026-08-09 UTC  
**Decision:** **NO-GO for production maturity; retain Experimental Reference Library**  
**Scope:** durable/distributed wishlist stream only; embedded AaronDB remains governed by ADR 0002.

## Evidence attached

| Gate | Evidence | Result |
| --- | --- | --- |
| Multi-node authenticated runtime | `scripts/verify_tls_cluster.sh`; three separately named BEAM VMs; mTLS, election, redirect, follower log convergence, unauthorized peer rejection | PASS for the exercised scenario |
| Deterministic safety corpus | `scripts/verify_distributed_harness.sh`; fixed seeds 11, 23, 37, 41; known-bad invariant tests; preserved logs | PASS for the library oracle and integration wrapper |
| Durability | `raft_durability` tests; checksum/torn-write refusal, fsync-backed image, compaction and backup coverage | PASS for the tested adapter scenarios |
| Data plane | `cluster_data_plane_test`; commit visibility, idempotency, CAS, fencing, cursors, projection/index status | PASS for the tested black-box contract |
| Soak profile | `scripts/verify_cluster_soak.sh`; 2 local iterations in this review, CI configured for 5; report records commit/host/OTP/topology | INCOMPLETE for production promotion: no sustained resource telemetry or release-specific SLO thresholds |
| Operations | `docs/manual/cluster_operations_runbook.md` | PASS as a documented library/runtime procedure; packaging equivalence remains to be supplied |
| Security/support boundary | `SECURITY.md`, ADR 0002, ADR 0011 | PASS: no contradiction; distributed runtime is not claimed as supported HA |

## Decision rationale

The evidence is strong enough to make the new modules a coherent **experimental
reference surface**. It is not enough to call them production-ready. The current
soak gate repeats correctness and integration checks but does not yet measure
p50/p95/p99 latency, acknowledged-write throughput, follower/feed/projection/index
lag, disk growth, RSS, queue growth, or recovery duration against versioned SLOs.
The runtime also lacks a packaged operator product and independent external
chaos/linearizability campaign beyond the checked-in harness.

Relabeling this as production now would contradict the evidence contract and
`SECURITY.md`. The correct release action is to publish the evidence profile,
keep the maturity row Experimental, and open a follow-up promotion review only
when the missing telemetry and external fault evidence are attached.

## Required follow-up before promotion

1. Define release-specific SLO thresholds and a supported hardware/OS matrix.
2. Add sustained workload telemetry for latency, throughput, lag, RSS, disk,
   queues, reconnects, snapshot/rebuild, and recovery.
3. Run destructive black-box chaos with preserved seeds, logs, and minimized
   histories on every supported environment.
4. Package the operator commands and verify bootstrap, rotation, backup/restore,
   and acknowledged recovery against that package.
5. Obtain independent review of the resulting evidence matrix.

**Promotion verdict:** NO-GO. No maturity label was changed.
