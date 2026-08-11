# Upgrade and Rollback Evidence Runner

`verify_upgrade_rollback.sh` validates a retained, independently executed
three-host N/N-1 rolling upgrade and rollback record. It is a **validator**, not
a deployment mechanism: it never SSHes to nodes, transfers credentials, executes
an upgrade, or turns a same-host lifecycle drill into cross-host evidence.

## Required input

```text
scripts/verify_upgrade_rollback.sh \
  --topology /secure/path/independent-host-lan.topology.json \
  --evidence /secure/path/upgrade-rollback-evidence.json
```

The topology must identify exactly three distinct `a`, `b`, and `c` hosts and
require peer certificate verification. The evidence must be source-bound to the
validator checkout and include:

| Evidence | Required contract |
|---|---|
| Source | Clean immutable commit equals the current checkout |
| Topology | SHA-256 equals the supplied strict mTLS topology |
| Compatibility | Named distinct `from`/`to` versions; unsupported pair refused |
| Transcript | Passing upgrade and rollback steps across all three nodes |
| State | Equal committed-state hashes before, after upgrade, and after rollback |
| Operations | Redacted public operator command outcomes, verified restore |
| Alarms | Leader movement, identity rotation, and rollback alarms |

Missing input, a non-independent-host topology, stale/wrong source identity,
missing alarms, an unequal state hash, or a failed command produces
`UPGRADE_ROLLBACK_NO_GO` and a nonzero exit status.

## Evidence shape

The operator-owned runner should write a JSON document with this high-level
shape. Private keys, cookies, certificate material, and raw secret values must
never be placed in it.

```json
{
  "schema": 1,
  "profile": "upgrade-rollback-v1",
  "status": "pass",
  "source": {"commit": "<immutable checkout SHA>", "dirty": false},
  "topology_sha256": "<manifest SHA-256>",
  "hosts": [{"id": "a", "host": "host-a"}, {"id": "b", "host": "host-b"}, {"id": "c", "host": "host-c"}],
  "versions": {"from": "N-1", "to": "N"},
  "transcript": [{"action": "upgrade", "result": "pass"}, {"action": "rollback", "result": "pass"}],
  "state_hashes": {"before": "…", "after_upgrade": "…", "after_rollback": "…"},
  "operator_commands": [{"redacted": true, "result": "pass"}],
  "alarms": [{"kind": "leader_movement"}, {"kind": "identity_rotation"}, {"kind": "rollback"}],
  "unsupported_version_pair_refused": true,
  "restore_verified": true
}
```

This template is intentionally insufficient as evidence: the validator also
requires the full six-or-more-step passing transcript and hashes it against the
supplied topology and current clean source identity.
