# Cluster Operations and Recovery Runbook

This runbook is the executable operator contract for the experimental cluster
runtime. The public control surface is `scripts/aarondb-clusterctl.sh`; it does
not require Erlang shell expressions, raw PIDs, `persistent_term`, or global
registry access. Its state-directory model is intentionally disposable for the
reference runtime—not a claim that a local JSON fixture replaces the durable
cluster control plane.

## Command contract

All commands return `0` only on success, `64` for invalid/missing inputs, and
non-zero for rejected safety conditions. Commands use bounded runner deadlines;
diagnostics redact fingerprints, certificate/key/token-shaped values. Execute
from the repository root:

| Operation | Public command | Safety boundary |
|---|---|---|
| Bootstrap | `scripts/aarondb-clusterctl.sh bootstrap --data-dir DIR --cluster ID --members a,b,c` | Requires an empty directory. |
| Status / diagnosis | `status --data-dir DIR`, `diagnose --data-dir DIR` | Read-only and redacted. |
| Backup | `backup --data-dir DIR --destination DIR` | Refuses an existing destination; records SHA-256. |
| Restore | `restore --data-dir DIR --source BACKUP --confirm RESTORE_CLUSTER` | Requires a verified backup and empty replacement directory. |
| Rotate / revoke | `rotate --data-dir DIR --node ID --fingerprint FP`, `revoke --data-dir DIR --fingerprint FP` | Output redacts the fingerprint; revocation raises an alarm. |
| Controlled shutdown | `shutdown --data-dir DIR` | Explicit lifecycle transition. |
| Unsafe recovery acknowledgement | `acknowledge-recovery --data-dir DIR --reason TEXT --confirm ACK_UNSAFE_RECOVERY` | Cannot occur without an exact confirmation token. |
| Projection rebuild | `rebuild --data-dir DIR --projection NAME` | Requests a rebuild; it does not make an index authoritative. |
| Incident collection | `collect --data-dir DIR --output DIR` | Refuses to overwrite a diagnostics directory. |
| TLS runtime verification | `verify --ops N` | Runs the public three-VM mTLS proof. |

The disposable success/failure contract is executable with:

`sh scripts/test_cluster_operator.sh`

## 1. Create and bootstrap

1. Create an empty data directory for each node with owner-only permissions.
2. Provision a cluster CA and one mTLS certificate per node. Record the
   certificate fingerprint and issuer in the trust store.
3. Start exactly one empty node with the committed cluster ID and the complete
   initial voter set. Bootstrap is allowed only when trust and membership are
   both empty.
4. Join the remaining nodes through the authenticated membership path. Never
   add a voter by editing a running node's local file.
5. Verify `status` on every node: one leader, quorum `Healthy`, commit index
   equal across voters, zero alarms, and queryable projections/indexes.

## 2. Diagnose

Collect, without mutating state:

- node identity, cluster ID, certificate fingerprint and membership;
- leader, term, commit/applied index, quorum health, follower lag;
- lease count and highest fencing token;
- projection checkpoint/lag/failure and index generation/health;
- active alarms, last failure reason, reconnect attempts, and durable-store
  path/checksum status.

A node with an alarm is not healthy because another node looks healthy. Quorum
loss stops acknowledged writes; projection/index degradation must be visible and
must not make a stale index authoritative.

## 3. Backup and restore

1. Stop or quiesce the target node using the public shutdown path.
2. Export a verified recovery image with the durability adapter's `backup`
   operation to a new destination. Check that the destination is distinct and
   retain the checksum and commit index in the incident record.
3. Restore only into an empty replacement data directory. Never overwrite a
   live store in place.
4. Start the replacement as a non-voter, authenticate it, replay/catch up, and
   compare hard state, committed log, snapshot, projections, indexes, leases,
   and idempotency results before promotion.

## 4. Rotation and recovery

Certificate rotation is staged: issue the replacement, add it to the trusted
root/membership policy, verify connectivity, then retire the old certificate.
Revocation is fail-closed and must be followed by a connectivity/status check.

Corrupt or torn durable bytes are refused and raise a persistent recovery alarm.
The safe action is restore-from-backup or replace-and-catch-up. Force recovery is
an exceptional, explicitly acknowledged operation; it must record
`UnsafeRecoveryAcknowledged` and remain visible until an operator acknowledges
and resolves the incident. Never delete the store or clear an alarm to make a
health check green.

## 5. Incident procedures

- **Quorum lost:** stop writes, preserve logs and status from every node, do
  not force a leader, and restore the missing voter or follow the approved
  replacement procedure.
- **Leader unavailable:** wait for election bounds; if no quorum exists,
  investigate transport/certificate/membership before recovery.
- **Follower lagging:** inspect RPC/reconnect and storage alarms; do not promote
  a lagging node until it catches up and its index is verified.
- **Projection/index failed:** keep the authoritative log available, replay
  from the last atomic checkpoint, rebuild into a new generation, and swap only
  after full catch-up.
- **Stale fencing token:** reject the operation, preserve the highest token,
  and investigate lease holder/recovery history.

Every incident record must include cluster ID, node IDs, commit index, alarm
state, seed/artifact path if a fault test was involved, operator, and UTC time.
