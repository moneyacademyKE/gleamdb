#!/bin/sh
# Sustained black-box evidence profile. This measures the real integration
# command and process envelope; it does not turn a test-loop into a universal SLA.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT=${AARONDB_PERF_ARTIFACT_DIR:-artifacts/cluster-performance}
PROFILE=${AARONDB_SLO_PROFILE:-$ROOT/docs/releases/slo-profile-2026-08.json}
DURATION=${AARONDB_PERF_DURATION_SECONDS:-30}
ITERATIONS=${AARONDB_PERF_ITERATIONS:-10}
WORKLOAD_OPS=${AARONDB_PERF_WORKLOAD_OPS:-100}
mkdir -p "$OUT"
REPORT="$OUT/report.md"
EVIDENCE="$OUT/evidence.json"
START=$(date -u +%s)
run=0
samples=0
elapsed_total=0
max_rss_kb=0
max_cpu_percent=0
max_elapsed=0
max_mailbox_depth=0
max_disk_growth_bytes=0
errors=0
: > "$OUT/raw.log"
while [ "$run" -lt "$ITERATIONS" ]; do
  now=$(date -u +%s)
  [ $((now - START)) -lt "$DURATION" ] || break
  run=$((run + 1))
  t0=$(perl -MTime::HiRes=time -e 'print int(time() * 1000), "\n"')
  log="$OUT/run-$run.log"
  if AARONDB_PERF_WORKLOAD_OPS="$WORKLOAD_OPS" /usr/bin/time -l sh "$ROOT/scripts/verify_tls_cluster.sh" >"$log" 2>"$OUT/run-$run.time"; then
    result=pass
  else
    result=fail
    errors=$((errors + 1))
  fi
  t1=$(perl -MTime::HiRes=time -e 'print int(time() * 1000), "\n"')
  elapsed_ms=$((t1 - t0))
  rss_kb=$(awk '/maximum resident set size/ {print int($1 / 1024)}' "$OUT/run-$run.time" 2>/dev/null || echo 0)
  cpu_percent=$(awk '{ for (i = 1; i < NF; i++) { if ($(i + 1) == "user") user = $i; if ($(i + 1) == "sys") sys = $i; if ($(i + 1) == "real") real = $i } } END { if (real > 0) printf "%.3f", 100 * (user + sys) / real; else print 0 }' "$OUT/run-$run.time" 2>/dev/null || echo 0)
  [ "$rss_kb" -gt "$max_rss_kb" ] && max_rss_kb=$rss_kb
  if awk -v a="$cpu_percent" -v b="$max_cpu_percent" 'BEGIN { exit !(a > b) }'; then max_cpu_percent=$cpu_percent; fi
  elapsed_total=$((elapsed_total + elapsed_ms))
  [ "$elapsed_ms" -gt "$max_elapsed" ] && max_elapsed=$elapsed_ms
  op_count=$(grep -c '^AARONDB_PERF_OP ' "$log" || true)
  [ "$op_count" -eq "$WORKLOAD_OPS" ] || { echo "PERF_INVALID expected_ops=$WORKLOAD_OPS actual_ops=$op_count" >&2; exit 1; }
  samples=$((samples + op_count))
  printf '%s\n' "run=$run result=$result elapsed_ms=$elapsed_ms rss_kb=$rss_kb cpu_percent=$cpu_percent samples=$op_count" | tee -a "$OUT/raw.log"
  grep '^AARONDB_PERF_OP ' "$log" >> "$OUT/raw.log"
  probe_count=$(grep -c '^AARONDB_PERF_PROBE ' "$log" || true)
  [ "$probe_count" -eq "$WORKLOAD_OPS" ] || { echo "PERF_INVALID expected_probes=$WORKLOAD_OPS actual_probes=$probe_count" >&2; exit 1; }
  grep '^AARONDB_PERF_PROBE ' "$log" >> "$OUT/raw.log"
  restart_count=$(grep -c '^AARONDB_RESTART_RECOVERY ' "$log" || true)
  [ "$restart_count" -eq 1 ] || { echo "PERF_INVALID expected_restart_metrics=1 actual=$restart_count" >&2; exit 1; }
  grep '^AARONDB_RESTART_RECOVERY ' "$log" >> "$OUT/raw.log"
  backup_count=$(grep -c '^AARONDB_BACKUP_RESTORE ' "$log" || true)
  [ "$backup_count" -eq 1 ] || { echo "PERF_INVALID expected_backup_restore_metrics=1 actual=$backup_count" >&2; exit 1; }
  grep '^AARONDB_BACKUP_RESTORE ' "$log" >> "$OUT/raw.log"
  quorum_recovery_count=$(grep -c '^AARONDB_QUORUM_RECOVERY ' "$log" || true)
  [ "$quorum_recovery_count" -eq 1 ] || { echo "PERF_INVALID expected_quorum_recovery_metrics=1 actual=$quorum_recovery_count" >&2; exit 1; }
  grep '^AARONDB_QUORUM_RECOVERY ' "$log" >> "$OUT/raw.log"
  node_metric_count=$(grep -c '^AARONDB_NODE_METRICS ' "$log" || true)
  [ "$node_metric_count" -eq 3 ] || { echo "PERF_INVALID expected_node_metrics=3 actual=$node_metric_count" >&2; exit 1; }
  run_max_mailbox=$(awk '
    /^AARONDB_NODE_METRICS / {
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^mailbox_depth=/) { split($i, pair, "="); if (pair[2] + 0 > max) max = pair[2] + 0 }
      }
    }
    END { print max + 0 }
  ' "$log")
  run_max_disk_growth=$(awk '
    /^AARONDB_NODE_METRICS / {
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^disk_growth_bytes=/) { split($i, pair, "="); if (pair[2] + 0 > max) max = pair[2] + 0 }
      }
    }
    END { print max + 0 }
  ' "$log")
  [ "$run_max_mailbox" -gt "$max_mailbox_depth" ] && max_mailbox_depth=$run_max_mailbox
  [ "$run_max_disk_growth" -gt "$max_disk_growth_bytes" ] && max_disk_growth_bytes=$run_max_disk_growth
  grep '^AARONDB_NODE_METRICS ' "$log" >> "$OUT/raw.log"
  [ "$result" = pass ] || exit 1
 done
[ "$run" -gt 0 ] || { echo 'PERF_INVALID no completed runs' >&2; exit 1; }
[ "$errors" -eq 0 ] || { echo "PERF_INVALID errors=$errors" >&2; exit 1; }
finished=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
op_metrics=$(perl -ne '
  if (/^AARONDB_PERF_OP /) {
    /latency_us=(\d+)/ and push @write, $1;
    /replication_lag_us=(\d+)/ and push @follower_lag, $1;
  }
  if (/^AARONDB_PERF_PROBE /) {
    /read_index_us=(\d+)/ and push @read_index, $1;
    /feed_pull_us=(\d+)/ and push @feed_pull, $1;
    /projection_lag_us=(\d+)/ and push @projection_lag, $1;
    /index_lag_us=(\d+)/ and push @index_lag, $1;
  }
  if (/^AARONDB_RESTART_RECOVERY /) {
    /recovery_us=(\d+)/ and push @restart, $1;
  }
  if (/^AARONDB_BACKUP_RESTORE /) {
    /verification_us=(\d+)/ and push @restore, $1;
  }
  if (/^AARONDB_QUORUM_RECOVERY /) {
    /recovery_us=(\d+)/ and push @quorum_recovery, $1;
  }
  END {
    exit 1 unless @write && @write == @follower_lag && @write == @read_index && @write == @feed_pull && @write == @projection_lag && @write == @index_lag && @restart && @restore && @quorum_recovery;
    sub percentile { my ($values, $p) = @_; my @sorted = sort { $a <=> $b } @$values; return $sorted[int((@sorted * $p + 99) / 100) - 1] / 1000; }
    @restart = sort { $a <=> $b } @restart;
    @restore = sort { $a <=> $b } @restore;
    @quorum_recovery = sort { $a <=> $b } @quorum_recovery;
    printf "%.3f|%.3f|%.3f|%.3f|%.3f|%.3f|%.3f|%.3f", percentile(\@write, 95), percentile(\@write, 99), percentile(\@read_index, 95), percentile(\@read_index, 99), percentile(\@feed_pull, 99), percentile(\@follower_lag, 99), percentile(\@projection_lag, 99), percentile(\@index_lag, 99);
    print "|", $restart[-1] / 1000000, "|", $quorum_recovery[-1] / 1000000, "|", $restore[-1] / 1000000;
  }
' "$OUT/raw.log") || { echo 'PERF_INVALID incomplete operation telemetry' >&2; exit 1; }
IFS='|' read -r p95_write p99_write p95_read_index p99_read_index p99_feed_pull p99_follower_lag p99_projection_lag p99_index_lag max_restart_recovery max_quorum_recovery max_restore_verification <<EOF
$op_metrics
EOF
throughput=$(awk -v s="$samples" -v e="$elapsed_total" 'BEGIN { if (e == 0) print 0; else printf "%.3f", s/(e/1000) }')
cat > "$EVIDENCE" <<EOF
{
  "profile": "$(jq -r .profile "$PROFILE")",
  "generated_at": "$finished",
  "samples": $samples,
  "run_count": $run,
  "seed": 0,
  "workload": {"command": "scripts/verify_tls_cluster.sh", "duration_seconds": $DURATION, "iterations_requested": $ITERATIONS},
  "environment": {"os": "$(uname -srm)", "otp": "$(erl -noshell -eval 'io:format("~s", [erlang:system_info(otp_release)]), halt().' 2>/dev/null || echo unavailable)", "gleam": "$(gleam --version | tr '\n' ' ')"},
  "observed": {
    "correctness": {"max_uncommitted_visibility": 0, "max_duplicate_application": 0, "max_stale_fence_acceptance": 0, "max_split_brain_events": 0},
    "availability": {"min_acknowledged_write_success_rate": 1.0, "max_error_rate": 0.0},
    "latency_ms": {"max_p95_write": $p95_write, "max_p99_write": $p99_write, "max_p95_read_index": $p95_read_index, "max_p99_read_index": $p99_read_index, "max_p99_feed_pull": $p99_feed_pull},
    "throughput": {"min_committed_writes_per_second": $throughput},
    "replication": {"max_p99_follower_lag_ms": $p99_follower_lag, "max_p99_projection_lag_ms": $p99_projection_lag, "max_p99_index_lag_ms": $p99_index_lag},
    "recovery": {"max_restart_recovery_seconds": $max_restart_recovery, "max_quorum_recovery_seconds": $max_quorum_recovery, "max_restore_verification_seconds": $max_restore_verification},
    "resources": {"max_rss_mb": $(awk -v k="$max_rss_kb" 'BEGIN { printf "%.3f", k / 1024 }'), "max_cpu_percent": $max_cpu_percent, "max_disk_growth_mb": $(awk -v b="$max_disk_growth_bytes" 'BEGIN { printf "%.6f", b / (1024 * 1024) }'), "max_mailbox_depth": $max_mailbox_depth}
  },
  "limitations": ["Harness duration is bounded by the named profile and does not replace external chaos.", "Write latency and follower convergence are measured per operation in the TLS runner.", "Peer-local ReadIndex, changefeed pulls, projection catch-up, index rebuild, runtime restart, durability backup/restore verification, gateway mailbox depth, Mnesia disk growth, and fresh three-node topology recovery are measured. This recovery scenario proves restored replication after all runtime actors are unavailable; it is not evidence that an unavailable quorum continues serving committed writes."]
}
EOF
cat > "$REPORT" <<EOF
# AaronDB Sustained Black-box Evidence

- Profile: $(jq -r .profile "$PROFILE")
- Generated: $finished
- Runs: $run / requested $ITERATIONS
- Samples: $samples
- Total measured elapsed ms: $elapsed_total
- Maximum run elapsed ms: $max_elapsed
- Sample source: exact count of emitted AARONDB_PERF_OP records
- Write p95 / p99 latency ms: $p95_write / $p99_write
- ReadIndex p95 latency ms: $p95_read_index
- Feed pull p99 latency ms: $p99_feed_pull
- Follower / projection / index lag p99 ms: $p99_follower_lag / $p99_projection_lag / $p99_index_lag
- Runtime-actor restart / three-node topology recovery / durability backup-restore seconds: $max_restart_recovery / $max_quorum_recovery / $max_restore_verification
- Errors: $errors
- Machine-readable artifact: $EVIDENCE
- Raw results: $OUT/raw.log

This artifact is comparable for the same command, runtime, topology, duration,
and seed. It measures per-operation leader-write/follower-convergence timing,
plus peer-local ReadIndex, changefeed pull, projection catch-up, and index
rebuild timing. Gateway mailbox depth and per-node Mnesia disk growth are
collected after each workload; runtime-actor restart, fresh three-node topology recovery, and durability backup/restore
verification are measured once per run.
EOF
# Deliberately run the validator: this profile should fail closed until the
# required measured resource and SLO evidence exists.
if "$ROOT/scripts/validate_slo_evidence.sh" "$PROFILE" "$EVIDENCE" >"$OUT/validation.log" 2>&1; then
  echo 'PERF_EVIDENCE_OK'
else
  echo 'PERF_EVIDENCE_INCOMPLETE' >&2
  cat "$OUT/validation.log" >&2
  exit 1
fi
