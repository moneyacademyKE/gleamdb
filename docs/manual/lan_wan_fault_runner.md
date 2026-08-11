# LAN/WAN fault evidence runner

`verify_lan_wan_faults.sh` executes **real, provisioned three-host mTLS topology** scenarios. It intentionally does not pretend that a local `sleep`, a deterministic model, or three host-local clusters proves a WAN deployment.

## Required inputs

- A completed `independent-host-lan-v1` topology manifest with a non-placeholder `network_interface` for nodes `a`, `b`, and `c`.
- An executable operator-owned fault adapter. It receives:

  `adapter apply|clear SEED SCENARIO TOPOLOGY`

  The adapter is responsible for applying and removing the fault on the actual named hosts. A typical implementation uses privileged `tc netem` and `nftables` through the same locked-down SSH transport used by the independent-host runner.

- The adapter must write the following attestations to stdout:

  - `AARONDB_FAULT_APPLIED seed=<seed> ...`
  - `AARONDB_FAULT_CLEARED seed=<seed> ...`

No attestation, adapter failure, topology failure, failed mTLS proof, or failed known-bad mutant check is a **NO-GO**.

## Invocation

```text
sh scripts/verify_lan_wan_faults.sh \
  --topology /secure/operator/independent-host-lan.json \
  --adapter /secure/operator/aarondb-netem-adapter \
  --ops 10000
```

## Replay corpus

The runner executes and preserves three versioned schedules:

| Seed | Scenario |
|---:|---|
| 101 | Symmetric `a` ↔ `b` partition, then heal |
| 103 | Asymmetric `a` → `c`: 1% loss, 50 ms jitter, reorder, duplication, then heal |
| 107 | Slow follower `c`, restart `b`, denied member churn `d`, and clock skew on `a` |

Each seed persists its schedule, adapter apply/clear logs, redacted independent-host run, cluster evidence, and machine-readable evidence. The summary also fingerprints both the topology and adapter to make a replay source explicit.

The runner separately requires the deterministic known-bad mutants for split brain, duplicate apply, stale fencing, and unsafe unalarmed recovery to remain rejected. This is complementary to—not a replacement for—the real network path.

## Scope

A passing run earns only the documented bounded WAN-emulation profile. It does not claim arbitrary WAN conditions, arbitrary adapters, fault-free physical hardware, or a broader release maturity label by itself.
