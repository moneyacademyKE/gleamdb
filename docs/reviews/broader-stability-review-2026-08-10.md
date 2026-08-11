# Broader Stability Review

**Review date:** 2026-08-10
**Repository:** AaronDB
**Final broader-stability verdict:** **NO-GO**

This review closes the locally implementable broader-stability program. The supporting runners and safety gates are operational; no broader maturity promotion is made because independent-host, WAN-emulation, long-soak, and mixed-version lifecycle evidence has not been supplied.

## Verification evidence

| Area | Command or artifact | Current result |
|---|---|---|
| Format, documentation, type-check, diff hygiene | `gleam format --check src test bench && gleam docs build && gleam check && git diff --check` | **PASS** |
| Regression suite | `gleam test` | **PASS — 304 tests, 0 failures** |
| Lifecycle / incident drills | `scripts/verify_lifecycle_drills.sh`; `artifacts/broader-stability/promotion/lifecycle.log` | **PASS** — gated backup/restore, rotation/revocation, rebuild, incident collection, and tamper refusal |
| Supported destructive storage faults | `scripts/verify_destructive_storage.sh`; `artifacts/broader-stability/destructive-storage-v1/20260810T214325Z/` | **PASS, scoped** — torn/corrupt image, checksum mismatch, interrupted pre-rename write, compaction recovery, and verified backup recovery |
| Independent-host runner rejection | `scripts/verify_independent_host_cluster.sh --topology docs/releases/independent-host-lan.topology.example.json` | **EXPECTED NO-GO** — template fingerprints are rejected; no real three-host manifest was provided |
| LAN/WAN runner rejection | `scripts/verify_lan_wan_faults.sh` | **EXPECTED NO-GO** — requires a real topology and executable privileged fault adapter |
| Long-soak runner rejection | `scripts/verify_long_soak.sh`; `artifacts/broader-stability/long-soak-v1/{no-workload-rejection.log,config-rejection.log}` | **EXPECTED NO-GO** — requires an external independent-host workload command plus 24-hour / 1M-operation evidence |
| Upgrade/rollback runner rejection | `scripts/verify_upgrade_rollback.sh` | **EXPECTED NO-GO** — requires source-bound independent-host N/N-1 evidence, state hashes, redacted operator outcomes, and alarms |
| Profile-aware promotion witness | `scripts/verify_broader_stability.sh` | **NO-GO, correct** — both `long-soak-v1` and `upgrade-rollback-v1` record missing external evidence; no default profile is silently omitted |

## Per-profile evidence decision

| Profile | Decision | Evidence and boundary |
|---|---|---|
| `independent-host-lan-v1` | **NO-GO / unrun** | Runner and strict three-host mTLS manifest contract exist, but no populated SSH-reachable topology or source-bound workload evidence exists. Same-host BEAM proof is not substituted. |
| `wan-emulation-v1` | **NO-GO / unrun** | Seeded fault schedules and cleanup attestation contract exist, but no operator-owned `tc`/firewall-style adapter or independent-host replay artifacts exist. |
| `destructive-storage-v1` | **Scoped supported-fault evidence** | Injected storage/process faults are evidenced by the destructive runner. This is not a physical power-cut, controller cache, firmware, or filesystem crash-consistency claim. |
| `long-soak-v1` | **NO-GO / unrun** | Gate correctly requires 24 hours, at least 1,000,000 measured operations, independent-host telemetry, and finite resource/lag/recovery metrics. None has been supplied. |
| `upgrade-rollback-v1` | **NO-GO / validator-ready** | A source- and topology-bound evidence validator now rejects incomplete/missing evidence. No N/N-1 rolling upgrade/rollback across independent hosts has been performed. |

## Operational risk register

| Risk | Status | Required closure evidence |
|---|---|---|
| Cross-host authentication, replication, and recovery are unproven | Open | Populate `independent-host-lan.topology` with three distinct hosts, trusted mTLS identities, strict SSH host keys, and retained runner artifacts. |
| Network-fault safety under real impairment is unproven | Open | Run `verify_lan_wan_faults.sh` with a reviewed privileged adapter; retain per-seed apply/clear logs and independent-host results. |
| Long-duration resource stability is unproven | Open | Run the external workload for at least 24 hours and 1M measured operations; retain raw telemetry and a passing `long-soak-v1` validation. |
| Physical power-loss semantics are unproven | Open by design | Create a named hardware/storage profile with actual power-cut methodology. The current destructive gate must not be relabeled. |
| Upgrade compatibility remains unproven | Open | Execute mixed N/N-1 rolling upgrade, rollback, identity-rotation, and restore drills across real hosts; validate the retained state-hash and alarm artifact with `verify_upgrade_rollback.sh`. |
| Current checkout is not a promotion candidate | Open by design | Commit/review this work, then rerun the scoped promotion gate from a clean immutable source identity. This alone cannot make missing profile evidence pass. |

## Promotion rule

Only profiles with fresh, source-bound, complete evidence may be named stable. The prior three-node same-host mTLS witness remains its own bounded claim. This review does **not** upgrade it, and it does not convert the completed tooling work into independent-host, WAN, soak, power-loss, or upgrade stability.
