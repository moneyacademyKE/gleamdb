# Broader Cluster Stability Profile Matrix

**Status:** planned evidence program; no profile below is promoted by this document.

The existing `aarondb-cluster-reference-2026-08` witness proves only a three-node, mTLS-authenticated, same-host BEAM profile. This matrix defines the additional evidence required before a stability claim can be widened. A profile earns a scoped claim only when its complete evidence matrix validates against its versioned SLO contract.

## Universal evidence rules

Every profile must provide:

- an immutable source identity and a clean-worktree witness;
- a versioned SLO profile with the topology, workload, fault budget, and correctness, availability, latency, replication, recovery, and resource thresholds below;
- raw telemetry and replayable schedules under `artifacts/broader-stability/<profile>/<run-id>/`;
- a machine-readable summary and a redacted operator-readable report;
- an explicit `NO-GO` result when any required measurement is absent, malformed, stale, outside its threshold, or detached from the source identity.

Successful operations use nearest-rank percentiles; errors are counted independently. A missing value is never equivalent to zero.

## Profile matrix

| Profile | Topology and workload | Fault budget | Required thresholds and telemetry | Required artifacts | Scoped maturity if passed |
|---|---|---|---|---|---|
| `independent-host-lan-v1` | Three separately addressable hosts, one node/host, mTLS, clock discipline, 4 vCPU/8 GiB/SSD minimum; 70% CAS write, 20% ReadIndex, 5% feed, 5% projection/index; 10,000 operations and 30-minute steady run | Single-node restart, leader loss, unauthorized join, bounded reconnect exhaustion | Zero split brain, duplicate apply, stale-fence acceptance, and uncommitted visibility; acknowledged writes >=99.9%; p99 write <=150 ms, ReadIndex <=120 ms, follower lag <=500 ms; CPU, RSS, mailbox depth, disk growth, reconnect/error counts | topology manifest, identity fingerprint manifest, raw operation telemetry, node resource telemetry, recovery schedule and report | Stable for the documented independent-host LAN envelope |
| `wan-emulation-v1` | Same three-host topology; deterministic impairment shim with 20--100 ms RTT and bounded loss/reorder; 10,000 operations and 30-minute impaired run | Symmetric/asymmetric partitions, 1% loss, 50 ms jitter, reorder, duplication, slow follower, leader restart | LAN correctness invariants remain zero; availability and latency thresholds are profile-specific; replication/projection/index lag, reconnects, quorum recovery, and schedule replay must be present | LAN artifacts plus seed schedules, impairment configuration, replay result, per-node connection telemetry | Stable only for the recorded WAN-emulation budget, not arbitrary WAN conditions |
| `destructive-storage-v1` | Three-node topology with a disposable storage volume per node; recovery workload validates committed state before and after faults | Torn/corrupt log image, interrupted snapshot, ENOSPC/write failure, kill at fsync boundary, backup corruption | Recovery equivalence after supported faults; every corruption/unsafe recovery has an alarm; no committed-state divergence; restore verification completes within the profile threshold | pre/post state hashes, injected-fault schedule, storage image checksums, alarms, recovery/restore output | Stable for the recorded process/storage fault classes |
| `long-soak-v1` | Three independently addressable nodes for at least 24 hours or 1,000,000 measured operations, whichever is greater; production-shaped mixed workload | Scheduled rolling restarts and bounded reconnect pressure only; faults are separately attributed | Full node CPU, RSS, mailbox, disk growth, latency, replication/feed/projection/index lag, reconnect/error, GC/process count, and recovery telemetry; all SLO thresholds hold throughout and no metric is missing | immutable raw telemetry chunks, aggregate percentile report, resource trend report, threshold validation result | Stable for the documented duration, workload, hardware floor, and resource envelope |
| `upgrade-rollback-v1` | Three nodes across N/N-1 compatible builds; rolling one-node-at-a-time upgrade then rollback via public operator tooling | Leader movement during upgrade, certificate rotate/revoke, interrupted rollout, restore from verified backup | Committed state survives every transition; mixed-version compatibility is explicitly tested; unsupported version pairs fail closed; rollback and identity incidents produce actionable alarms | version manifest, step transcript, state hashes, operator command results, alarms, rollback/restore reports | Stable for the exact tested upgrade and rollback compatibility window |

## Explicit non-claims

Passing these profiles does **not** claim:

- arbitrary hardware, throughput, cluster size, workload mix, or latency;
- unbounded or internet-wide WAN behavior;
- physical power-cut, controller-cache, firmware, or filesystem behavior unless tested on named hardware by a separate profile;
- Byzantine fault tolerance, a full Jepsen campaign, or safety properties beyond emitted schedules and checked invariants;
- release, deployment, or a rewrite of the existing `v4.1.0` tag.

## Profile-to-maturity mapping

| Evidence state | Permitted statement |
|---|---|
| Existing `aarondb-cluster-reference-2026-08` witness only | Production-ready for its named three-node same-host mTLS profile; experimental outside it |
| `independent-host-lan-v1` passes | Stable for the named independent-host LAN profile |
| `wan-emulation-v1` passes | Stable for the named bounded WAN-emulation profile |
| `destructive-storage-v1` passes | Stable for the named supported storage/process fault classes |
| `long-soak-v1` passes | Stable for the named long-soak hardware/workload envelope |
| `upgrade-rollback-v1` passes | Stable for the named version-compatibility and operator lifecycle window |
| Any missing, stale, malformed, dirty, or failed evidence | **NO-GO** for that profile; no broader claim |
