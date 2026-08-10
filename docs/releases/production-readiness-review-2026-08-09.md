# Production Readiness Release Review

**Review date:** 2026-08-10 UTC
**Source identity:** `92d9a7327ebcbe6a95d97be5fb3151cf0eecfb29` (`v4.1.0-1-g92d9a73`)
**Decision:** **GO for the versioned production-cluster promotion gate**
**Scope:** durable/distributed cluster stream only. Embedded `aarondb.new()` remains local and governed by ADR 0002.

> **Historical correction:** the 2026-08-09 NO-GO review was accurate for the evidence available then. It is superseded for commit `92d9a73` by the current gate witness below; it is not a claim about the older `v4.1.0` tag at `a61f106`.

## Current evidence and verification

| Gate | Evidence | Result |
|---|---|---|
| Immutable source | Clean worktree at `92d9a73` | PASS |
| SLO profile and workload | Versioned `slo-profile-2026-08.json`; 10,000 committed operations | PASS |
| Performance envelope | 261.739 and 262.405 ops/s independent runs; write p99 2.292/2.196 ms; follower-lag p99 3.566/3.416 ms; zero workload errors | PASS |
| Multi-node authenticated runtime | Three separately named BEAM VMs under mTLS; election, redirect, follower convergence, rejected unknown peer, and shutdown | PASS |
| Recovery/durability | Checksummed fsync image, corruption refusal, restart/topology recovery, and verified backup/restore | PASS for the tested scenarios |
| Destructive chaos | Seeds 11, 23, 37, 41; convergence, full-runtime outage/recovery, and known-bad mutant rejection | PASS |
| Operator lifecycle | Public `aarondb-clusterctl.sh`; 13 commands, three rejected paths, redaction verification | PASS |
| Source verification | Format, type-check, tests, and diff hygiene | PASS — 302 tests |
| Promotion gate | `scripts/verify_cluster_promotion.sh` generated redacted JSON and Markdown witnesses | PASS — GO |

## Proven behavior

The promotion evidence proves the defined three-node TLS workload envelope and the versioned SLO/profile contract. It includes committed-write latency and throughput, follower convergence, resource sampling, restart/topology recovery, backup/restore validation, operator command behavior, and deterministic destructive scenarios.

## Boundaries that remain true

This decision does **not** silently widen the product boundary:

- It does not retag or alter the existing `v4.1.0` release, which points to `a61f106` rather than this reviewed commit.
- It does not claim universal performance, arbitrary hardware support, WAN behavior, power-loss equivalence, or a Jepsen campaign beyond the recorded profile and artifact set.
- It does not authorize a push, PR, merge, deployment, tag, or public release. Those are separate external actions.
- The local embedded API retains its ADR 0002 support boundary.

## Reproduction

Run the fail-closed gate from the reviewed commit:

`sh scripts/verify_cluster_promotion.sh`

Expected result: `PROMOTION_GO` and regenerated witnesses at:

- `artifacts/cluster-promotion/release-witness.json`
- `artifacts/cluster-promotion/release-witness.md`

The gate validates every input and writes a **NO-GO** witness if the worktree is dirty or required profile, performance, chaos, operator, format, check, test, or diff-hygiene evidence is incomplete.

**Promotion verdict:** **GO for commit `92d9a73` under the stated profile.**
