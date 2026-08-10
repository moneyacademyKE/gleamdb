# Identity and Operations Manual

`aarondb/identity` is the library-level transport admission and recovery-policy model. It is **not** a TLS socket implementation: adapters terminate mTLS, extract a verified certificate fingerprint, then call `admit_peer` before admitting any Raft traffic.

## Durable node identity and mTLS admission

A durable `TrustStore` binds cluster membership to node IDs, trusted issuing roots, certificate fingerprints, and certificate lifecycle state. Peer admission is conjunctive:

1. certificate fingerprint exists;
2. the certificate node matches the expected peer node;
3. its issuer is trusted;
4. its lifecycle is `Active` (not rotated or revoked);
5. the node is in committed membership; and
6. the RPC fits the explicit payload and retry limits.

A failure at any point rejects the RPC before it reaches Raft. Retries use a zero-based, finite attempt budget; exhaustion is an explicit error, never a hidden reconnect loop. Certificate rotation retains the old certificate only as inactive audit evidence, while revocation is immediately fail-closed.

Initial bootstrap is permitted only for an empty trust store and an empty membership set. Once either exists, membership changes must come through committed consensus configuration—not a transport handshake.

## Leases and recovery

Leases are committed commands. Every resource grant yields an increasing fencing token; a downstream protected resource must reject a token lower than the greatest it persisted. After quorum/leader/clock-bound uncertainty, grants fail closed.

Operator recovery supports inspect, export, and explicitly acknowledged force recovery only. `force_recovery` deliberately appends a durable `UnsafeRecoveryAcknowledged` alarm; inspection additionally records missing trust material and membership mismatch. These alarms are never silently cleared by a later clean process start.

## Fault gate

Release evidence includes deterministic partitions, crashes/restarts, duplicate/reordered RPC, slow followers, storage stalls, snapshot interruption, churn, and bounded clock anomalies. Seeded mutants for split brain, duplicate apply, stale fence, unsafe recovery, malicious oversized RPC, wrong identity binding, and revoked certificates must be caught.

