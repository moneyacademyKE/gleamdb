# Long-Soak Evidence Runner

`scripts/verify_long_soak.sh` is a **fail-closed accumulator**, not a local benchmark wrapper. It requires the named `long-soak-v1` minimums: 24 hours and 1,000,000 operations, both measured against an independently addressable three-host topology.

## Starting an evidence run

An operator must provide `AARONDB_SOAK_WORKLOAD_COMMAND`. The command is responsible for running one external batch and writing its artifact to `$AARONDB_PERF_ARTIFACT_DIR/performance/evidence.json`. That evidence must:

- use the `long-soak-v1` profile;
- identify `environment.topology_scope` as `independent-host`;
- include a non-empty topology-manifest SHA-256;
- include complete finite telemetry required by `long-soak-v1`.

The runner supplies the batch output directory, batch operation count, and batch duration through environment variables. It aggregates only complete batches, preserves raw batch JSON in `raw.jsonl`, records a hash of the workload command in `manifest.json`, and validates the aggregate with `validate_slo_evidence.sh`.

It rejects missing workload commands, a requested duration/sample count below the profile minimum, local/same-host artifacts, malformed telemetry, failed batches, or any SLO violation. The old same-host TLS runner is deliberately not an acceptable command for this profile.

## Example shape

Use an operator-owned wrapper that invokes the SSH topology runner and gathers node telemetry. It must be passed as a quoted command, for example `AARONDB_SOAK_WORKLOAD_COMMAND='sh /secure/path/run-independent-host-batch.sh'`. Do not embed credentials, private keys, or certificate material in the command string: its SHA-256 is preserved in the resulting manifest.

A successful run is an artifact, not a chat claim. Until a real independent-host run reaches both targets, `long-soak-v1` remains **NO-GO**.
