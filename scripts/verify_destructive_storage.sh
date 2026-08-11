#!/bin/sh
# Fail-closed evidence gate for the supported destructive-storage profile.
#
# This gate proves only injected process/filesystem fault classes against the
# atomic recovery-image adapter. It never claims physical power-cut, controller
# cache, firmware, or filesystem crash-consistency coverage.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT=${AARONDB_DESTRUCTIVE_STORAGE_ARTIFACT_DIR:-"$ROOT/artifacts/broader-stability/destructive-storage-v1/$(date -u +%Y%m%dT%H%M%SZ)"}
mkdir -p "$OUT"

case ${AARONDB_PHYSICAL_POWER_CUT_ATTESTATION:-} in
  "") ;;
  *)
    echo "DESTRUCTIVE_STORAGE_NO_GO physical_power_cut_attestation_is_not_supported_by_this_gate" >&2
    exit 64
    ;;
esac

for test_case in \
  fsynced_image_recovers_exact_acknowledged_state_after_restart_test \
  torn_or_corrupt_store_returns_alarm_instead_of_repairing_test \
  checksum_mismatch_returns_alarm_instead_of_decoding_payload_test \
  snapshot_compaction_round_trips_equivalent_recovery_state_test \
  verified_backup_exports_exact_recoverable_image_test \
  interrupted_pre_rename_write_preserves_last_acknowledged_image_test \
  corrupt_primary_requires_verified_backup_and_explicit_operator_recovery_test
do
  grep -q "pub fn $test_case" "$ROOT/test/aarondb/raft_durability_test.gleam" || {
    echo "DESTRUCTIVE_STORAGE_NO_GO missing_test=$test_case" >&2
    exit 1
  }
done

gleam test > "$OUT/gleam-test.log" 2>&1 || {
  cat "$OUT/gleam-test.log" >&2
  exit 1
}
sh "$ROOT/scripts/test_cluster_operator.sh" > "$OUT/operator-recovery.log" 2>&1 || {
  cat "$OUT/operator-recovery.log" >&2
  exit 1
}

source_id=$(git -C "$ROOT" rev-parse HEAD)
cat > "$OUT/evidence.json" <<EOF
{
  "profile": "destructive-storage-v1",
  "source_identity": "$source_id",
  "verdict": "SUPPORTED_FAULT_CLASSES_EVIDENCED",
  "fault_classes": [
    "corrupt and torn primary images",
    "checksum mismatch",
    "synced temporary write interrupted before rename",
    "snapshot compaction recovery equivalence",
    "verified backup recovery"
  ],
  "operator_recovery": "verified backup plus explicit restore/recovery acknowledgement contract",
  "physical_power_cut": {
    "tested": false,
    "claim": "not covered: no hardware power cut, storage-controller cache, firmware, or filesystem crash-consistency assertion"
  }
}
EOF
cat > "$OUT/report.md" <<EOF
# Destructive Storage Evidence

- Source: $source_id
- Result: supported injected storage/process faults passed.
- Operator recovery: backup/restore and unsafe-recovery acknowledgement contracts passed.
- Explicit limit: this run did **not** cut physical power or validate controller-cache, firmware, or filesystem crash behavior.
EOF

echo "DESTRUCTIVE_STORAGE_EVIDENCE_OK artifact=$OUT physical_power_cut=not_tested"
