#!/bin/sh
# Fail-closed long-soak evidence runner. It accumulates independently validated
# workload batches and refuses to turn a short local smoke into soak proof.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PROFILE=${AARONDB_SOAK_PROFILE:-$ROOT/docs/releases/long-soak-v1.slo.json}
OUT=${AARONDB_SOAK_ARTIFACT_DIR:-$ROOT/artifacts/broader-stability/long-soak-v1/$(date -u +%Y%m%dT%H%M%SZ)}
DURATION=${AARONDB_SOAK_DURATION_SECONDS:-86400}
MIN_SAMPLES=${AARONDB_SOAK_MIN_SAMPLES:-1000000}
BATCH_OPS=${AARONDB_SOAK_BATCH_OPS:-1000}
PERF_DURATION=${AARONDB_SOAK_BATCH_DURATION_SECONDS:-3600}
MAX_BATCHES=${AARONDB_SOAK_MAX_BATCHES:-0}
# Must be an operator-provided command that executes the named independent-host
# topology. The local TLS runner is deliberately forbidden for this profile.
WORKLOAD_COMMAND=${AARONDB_SOAK_WORKLOAD_COMMAND:-}

fail() { printf '%s\n' "SOAK_INVALID $*" >&2; exit 1; }
[ -f "$PROFILE" ] || fail "missing profile=$PROFILE"
command -v jq >/dev/null 2>&1 || fail 'jq is required'
[ -n "$WORKLOAD_COMMAND" ] || fail 'AARONDB_SOAK_WORKLOAD_COMMAND must name an external independent-host workload command'
[ "$DURATION" -gt 0 ] 2>/dev/null || fail 'duration must be positive integer'
[ "$MIN_SAMPLES" -gt 0 ] 2>/dev/null || fail 'minimum samples must be positive integer'
[ "$BATCH_OPS" -gt 0 ] 2>/dev/null || fail 'batch operations must be positive integer'
profile_duration=$(jq -er '.assumptions.minimum_duration_seconds' "$PROFILE") || fail 'profile minimum duration missing'
profile_samples=$(jq -er '.assumptions.minimum_samples' "$PROFILE") || fail 'profile minimum samples missing'
[ "$DURATION" -ge "$profile_duration" ] || fail "requested duration=$DURATION below profile minimum=$profile_duration"
[ "$MIN_SAMPLES" -ge "$profile_samples" ] || fail "requested samples=$MIN_SAMPLES below profile minimum=$profile_samples"

mkdir -p "$OUT/batches"
MANIFEST="$OUT/manifest.json"
RAW="$OUT/raw.jsonl"
REPORT="$OUT/report.md"
: > "$RAW"
started_epoch=$(date -u +%s)
started_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
batch=0
samples=0

while :; do
  now=$(date -u +%s)
  elapsed=$((now - started_epoch))
  [ "$elapsed" -lt "$DURATION" ] || break
  [ "$samples" -lt "$MIN_SAMPLES" ] || break
  [ "$MAX_BATCHES" -eq 0 ] || [ "$batch" -lt "$MAX_BATCHES" ] || break

  batch=$((batch + 1))
  batch_dir="$OUT/batches/$batch"
  mkdir -p "$batch_dir"
  printf '%s\n' "[long-soak batch=$batch elapsed_seconds=$elapsed samples=$samples]" | tee "$batch_dir/runner.log"
  if AARONDB_PERF_ARTIFACT_DIR="$batch_dir/performance" \
    AARONDB_SOAK_EVIDENCE_PROFILE="$PROFILE" \
    AARONDB_PERF_DURATION_SECONDS="$PERF_DURATION" \
    AARONDB_PERF_ITERATIONS=1000000 \
    AARONDB_PERF_WORKLOAD_OPS="$BATCH_OPS" \
    sh -c "$WORKLOAD_COMMAND" >>"$batch_dir/runner.log" 2>&1; then
    evidence="$batch_dir/performance/evidence.json"
    [ -f "$evidence" ] || fail "batch=$batch missing performance evidence"
    jq -e --arg profile "$(jq -r .profile "$PROFILE")" '
      .profile == $profile
      and (.samples | type == "number" and . > 0)
      and (.observed | type == "object")
      and (.environment.topology_scope == "independent-host")
      and (.environment.topology_manifest_sha256 | type == "string" and length > 0)
    ' "$evidence" >/dev/null || fail "batch=$batch malformed, wrong-profile, or non-independent-host performance evidence"
    jq -c --argjson batch "$batch" '. + {batch: $batch}' "$evidence" >> "$RAW"
    batch_samples=$(jq -er '.samples' "$evidence")
    samples=$((samples + batch_samples))
  else
    fail "batch=$batch workload failed; see $batch_dir/runner.log"
  fi
done

finished_epoch=$(date -u +%s)
finished_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
elapsed_seconds=$((finished_epoch - started_epoch))
[ "$elapsed_seconds" -ge "$DURATION" ] || fail "under-duration seconds=$elapsed_seconds minimum=$DURATION"
[ "$samples" -ge "$MIN_SAMPLES" ] || fail "under-sampled samples=$samples minimum=$MIN_SAMPLES"

# Preserve raw per-batch immutable evidence, then derive an aggregate only from
# finite metrics. Max applies to safety/error/resource/recovery, min applies to
# success/throughput, and latency/lag fields take the worst batch percentile.
aggregate="$OUT/evidence.json"
jq -s --arg generated "$finished_at" --arg profile "$(jq -r .profile "$PROFILE")" \
  --argjson duration "$elapsed_seconds" '
  def nums($p): [ .[] | getpath($p) | select(type == "number" and isfinite) ];
  def maxnum($p): nums($p) as $values | if ($values | length) == length then ($values | max) else error("missing metric") end;
  def minnum($p): nums($p) as $values | if ($values | length) == length then ($values | min) else error("missing metric") end;
  if length == 0 then error("no batch evidence") else . end
  | . as $runs
  | {
      profile: $profile,
      generated_at: $generated,
      samples: ([.[] | .samples] | add),
      run_count: length,
      duration_seconds: $duration,
      source_identities: ([.[] | .environment] | unique),
      observed: {
        correctness: {
          max_uncommitted_visibility: maxnum(["observed","correctness","max_uncommitted_visibility"]),
          max_duplicate_application: maxnum(["observed","correctness","max_duplicate_application"]),
          max_stale_fence_acceptance: maxnum(["observed","correctness","max_stale_fence_acceptance"]),
          max_split_brain_events: maxnum(["observed","correctness","max_split_brain_events"])
        },
        availability: {
          min_acknowledged_write_success_rate: minnum(["observed","availability","min_acknowledged_write_success_rate"]),
          max_error_rate: maxnum(["observed","availability","max_error_rate"])
        },
        latency_ms: {
          max_p95_write: maxnum(["observed","latency_ms","max_p95_write"]),
          max_p99_write: maxnum(["observed","latency_ms","max_p99_write"]),
          max_p95_read_index: maxnum(["observed","latency_ms","max_p95_read_index"]),
          max_p99_read_index: maxnum(["observed","latency_ms","max_p99_read_index"]),
          max_p99_feed_pull: maxnum(["observed","latency_ms","max_p99_feed_pull"])
        },
        throughput: {min_committed_writes_per_second: minnum(["observed","throughput","min_committed_writes_per_second"])},
        replication: {
          max_p99_follower_lag_ms: maxnum(["observed","replication","max_p99_follower_lag_ms"]),
          max_p99_projection_lag_ms: maxnum(["observed","replication","max_p99_projection_lag_ms"]),
          max_p99_index_lag_ms: maxnum(["observed","replication","max_p99_index_lag_ms"])
        },
        recovery: {
          max_restart_recovery_seconds: maxnum(["observed","recovery","max_restart_recovery_seconds"]),
          max_quorum_recovery_seconds: maxnum(["observed","recovery","max_quorum_recovery_seconds"]),
          max_restore_verification_seconds: maxnum(["observed","recovery","max_restore_verification_seconds"])
        },
        resources: {
          max_rss_mb: maxnum(["observed","resources","max_rss_mb"]),
          max_cpu_percent: maxnum(["observed","resources","max_cpu_percent"]),
          max_disk_growth_mb: maxnum(["observed","resources","max_disk_growth_mb"]),
          max_mailbox_depth: maxnum(["observed","resources","max_mailbox_depth"])
        }
      },
      limitations: ["This is a bounded, named long-soak profile. It does not prove arbitrary hardware, WAN, or power-loss behavior."],
      raw_batch_evidence: "raw.jsonl"
    }
' "$RAW" > "$aggregate" || fail 'aggregate failed due to missing or nonnumeric telemetry'

# The generic validator understands threshold fields and freshness; verify the
# profile-specific duration separately, so evidence cannot pass on a fast run.
"$ROOT/scripts/validate_slo_evidence.sh" "$PROFILE" "$aggregate" > "$OUT/validation.log" 2>&1 || {
  cat "$OUT/validation.log" >&2
  fail 'threshold validation failed'
}
jq -e --argjson minimum_duration "$DURATION" '.duration_seconds >= $minimum_duration' "$aggregate" >/dev/null || fail 'duration absent or below requested minimum'

cat > "$MANIFEST" <<EOF
{
  "profile": "$(jq -r .profile "$PROFILE")",
  "started_at": "$started_at",
  "finished_at": "$finished_at",
  "duration_seconds": $elapsed_seconds,
  "samples": $samples,
  "batches": $batch,
  "source_commit": "$(git -C "$ROOT" rev-parse HEAD)",
  "source_dirty": $(test -n "$(git -C "$ROOT" status --porcelain)" && printf true || printf false),
  "workload_command_sha256": "$(printf '%s' "$WORKLOAD_COMMAND" | shasum -a 256 | awk '{print $1}')",
  "raw_telemetry": "raw.jsonl",
  "aggregate": "evidence.json",
  "validation": "validation.log"
}
EOF

cat > "$REPORT" <<EOF
# AaronDB Long Soak Evidence

- Profile: $(jq -r .profile "$PROFILE")
- Started: $started_at
- Finished: $finished_at
- Duration seconds: $elapsed_seconds
- Operations: $samples
- Batches: $batch
- Source commit: $(git -C "$ROOT" rev-parse HEAD)
- Raw telemetry: raw.jsonl
- Aggregate evidence: evidence.json
- Validator: validation.log

This is a bounded independent-host result. Any missing, malformed,
threshold-violating, under-duration, under-sampled, wrong-topology, or
dirty-source result is NO-GO for promotion.
EOF
printf '%s\n' "LONG_SOAK_OK artifact=$OUT samples=$samples duration_seconds=$elapsed_seconds"
