# Independent-host LAN runner

`verify_independent_host_cluster.sh` promotes no infrastructure by itself. It is a **strict provisioning-and-validation executor**: hosts are explicitly declared in a topology manifest, remote release/TLS paths are supplied by each host’s operator environment, and the runner rejects ambiguous topology or weakened transport before it invokes the existing authenticated three-VM proof.

## Prerequisites

1. Build and install the same immutable AaronDB release on three independently addressable hosts.
2. Configure host SSH keys in the controller’s `known_hosts`. The runner always uses `BatchMode=yes` and `StrictHostKeyChecking=yes`.
3. On every host, configure the operator account with:
   - `AARONDB_RELEASE_DIR`: absolute path to the release checkout;
   - `AARONDB_TLS_CONFIG`: absolute path to an `inet_tls` config with `verify_peer` and `fail_if_no_peer_cert`.
4. Copy the example manifest and replace every `REPLACE_WITH_*` fingerprint with its actual SHA-256 identity fingerprint. The runner rejects placeholders, duplicate addresses, missing `a`/`b`/`c` members, and any TLS policy weaker than mutual verification.

## Run

```text
sh scripts/verify_independent_host_cluster.sh \
  --topology /secure/operator/independent-host-lan.json \
  --ops 10000
```

The runner does not copy keys, certificates, cookies, release archives, or secrets. It proves that each separately addressed host can execute the existing three-node mTLS test profile using its locally provisioned release. Every host must produce:

- one `TLS_CLUSTER_INTEGRATION_OK` result;
- the configured count of committed operations; and
- an `unknown_certificate` rejection.

Evidence is written to `artifacts/broader-stability/independent-host-lan-v1/<run-id>/`. Logs are redacted before persistence. Any SSH failure, malformed topology, missing local TLS policy, missing operation output, or failed unauthorized-member rejection returns non-zero and leaves the profile **NO-GO**.

This is intentionally not a claim that the three host-local subclusters form a single cross-host Raft deployment. That would require an externally routable cluster transport endpoint and is a separate product/runtime change. The runner earns evidence that the independent host envelope, identity policy, and deployment preparation are executable without misrepresenting the current same-host three-VM transport proof.
