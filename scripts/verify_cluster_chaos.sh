#!/bin/sh
# Fail-closed destructive-chaos evidence gate.
#
# Every seed gets its own artifact directory. The TLS runner performs an actual
# three-VM actor outage/topology rebuild and records recovery timing; the pure
# deterministic oracle supplies the seed-specific partition/reorder/disk
# schedule and known-bad safety mutants. Neither half can silently skip.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT=${AARONDB_CHAOS_ARTIFACT_DIR:-"$ROOT/artifacts/cluster-chaos"}
PROFILE=${AARONDB_SLO_PROFILE:-"$ROOT/docs/releases/slo-profile-2026-08.json"}
MAX_RECOVERY_US=$(jq -er '.thresholds.recovery.max_quorum_recovery_seconds * 1000000' "$PROFILE")
MAX_FOLLOWER_LAG_US=$(jq -er '.thresholds.replication.max_p99_follower_lag_ms * 1000' "$PROFILE")
OPS=${AARONDB_CHAOS_WORKLOAD_OPS:-10}
mkdir -p "$OUT"

run_seed() {
  seed=$1
  schedule=$2
  dir="$OUT/seed-$seed"
  mkdir -p "$dir"
  log="$dir/run.log"
  : > "$log"

  printf '%s\n' "$schedule" > "$dir/schedule.txt"
  if AARONDB_TLS_RUN_ID="chaos-${seed}-$$" \
       AARONDB_CHAOS_SEED="$seed" \
       AARONDB_PERF_WORKLOAD_OPS="$OPS" \
       sh "$ROOT/scripts/verify_tls_cluster.sh" >"$log" 2>&1; then
    status=pass
  else
    status=fail
  fi

  # Every scenario must prove a committed workload and the destructive
  # three-node runtime outage/recovery measurement. Missing output is failure,
  # not a partial pass.
  ops=$(grep -c '^AARONDB_PERF_OP ' "$log" || true)
  recovery=$(grep -c '^AARONDB_QUORUM_RECOVERY ' "$log" || true)
  unauthorized=$(grep -c '^AARONDB_AUTH_REJECTION kind=unknown_certificate$' "$log" || true)
  [ "$status" = pass ] || { echo "CHAOS_FAILED seed=$seed runner=$status" >&2; exit 1; }
  [ "$ops" -eq "$OPS" ] || { echo "CHAOS_FAILED seed=$seed expected_ops=$OPS actual=$ops" >&2; exit 1; }
  [ "$recovery" -eq 1 ] || { echo "CHAOS_FAILED seed=$seed missing_quorum_recovery" >&2; exit 1; }
  [ "$unauthorized" -ge 1 ] || { echo "CHAOS_FAILED seed=$seed missing_auth_rejection" >&2; exit 1; }

  recovery_us=$(awk '/^AARONDB_QUORUM_RECOVERY / { for (i=1;i<=NF;i++) if ($i ~ /^recovery_us=/) { split($i,a,"="); print a[2] } }' "$log")
  case "$recovery_us" in ''|*[!0-9]*) echo "CHAOS_FAILED seed=$seed invalid_recovery" >&2; exit 1;; esac
  awk -v actual="$recovery_us" -v limit="$MAX_RECOVERY_US" 'BEGIN { exit !(actual <= limit) }' || { echo "CHAOS_FAILED seed=$seed quorum_recovery_us=$recovery_us limit=$MAX_RECOVERY_US" >&2; exit 1; }
  follower_lag_p99_us=$(awk '
    /^AARONDB_PERF_OP / {
      for (i=1; i<=NF; i++) if ($i ~ /^replication_lag_us=/) { split($i, pair, "="); values[++n] = pair[2] }
    }
    END {
      if (n == 0) exit 1
      for (i=1; i<=n; i++) for (j=i+1; j<=n; j++) if (values[i] > values[j]) { tmp=values[i]; values[i]=values[j]; values[j]=tmp }
      rank = int((n * 99 + 99) / 100); print values[rank]
    }
  ' "$log") || { echo "CHAOS_FAILED seed=$seed no_follower_lag" >&2; exit 1; }
  awk -v actual="$follower_lag_p99_us" -v limit="$MAX_FOLLOWER_LAG_US" 'BEGIN { exit !(actual <= limit) }' || { echo "CHAOS_FAILED seed=$seed follower_lag_p99_us=$follower_lag_p99_us limit=$MAX_FOLLOWER_LAG_US" >&2; exit 1; }
  safety=$(grep -c "^AARONDB_CHAOS_SAFETY seed=$seed split_brain_events=0 duplicate_application=0 stale_fence_acceptance=0 unsafe_recovery_alarms=0$" "$log" || true)
  [ "$safety" -eq 1 ] || { echo "CHAOS_FAILED seed=$seed missing_safety_assertions" >&2; exit 1; }
  jq -n --argjson seed "$seed" --arg schedule "$schedule" --arg status "$status" \
    --argjson committed_operations "$ops" --argjson quorum_recovery_us "$recovery_us" --argjson follower_lag_p99_us "$follower_lag_p99_us" \
    '{seed:$seed,schedule:$schedule,status:$status,committed_operations:$committed_operations,quorum_recovery_us:$quorum_recovery_us,follower_lag_p99_us:$follower_lag_p99_us,safety_assertions:["follower convergence","unauthorized certificate rejected","all-runtime-actors unavailable before topology recovery","recovered leader commits on two followers"]}' > "$dir/evidence.json"
  echo "CHAOS_SEED_OK seed=$seed artifact=$dir recovery_us=$recovery_us follower_lag_p99_us=$follower_lag_p99_us"
}

# These are the public replay seeds defined by aarondb/distributed_harness.
run_seed 11 'partition(a,b), duplicate append RPC, heal'
run_seed 23 'crash/restart(b), reordered append RPC'
run_seed 37 'slow follower(c), membership churn(d), negative clock skew(a)'
run_seed 41 'disk fault(b), crash/restart(b), reordered snapshot RPC'

# `gleam test` emits no test-file names, so make the mutant contract explicit
# and fail if any required known-bad case disappears from the source.
for mutant in known_bad_split_brain_mutant_is_detected_test known_bad_duplicate_apply_mutant_is_detected_test known_bad_stale_fence_mutant_is_detected_test known_bad_unsafe_recovery_mutant_is_detected_test; do
  grep -q "pub fn $mutant" "$ROOT/test/aarondb/distributed_harness_test.gleam" || {
    echo "CHAOS_FAILED missing_mutant=$mutant" >&2
    exit 1
  }
done
gleam test > "$OUT/mutant-gate.log" 2>&1 || { cat "$OUT/mutant-gate.log" >&2; exit 1; }
echo "CHAOS_MUTANT_GATE_OK cases=4" >> "$OUT/mutant-gate.log"
echo "CHAOS_EVIDENCE_OK artifacts=$OUT"
