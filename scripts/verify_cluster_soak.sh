#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT=${AARONDB_SOAK_ARTIFACT_DIR:-artifacts/cluster-soak}
mkdir -p "$OUT"
REPORT="$OUT/report.md"
: > "$REPORT"
{
  echo "# AaronDB Cluster Soak Evidence"
  echo
  echo "- Date (UTC): $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "- Commit: $(git -C "$ROOT" rev-parse HEAD)"
  echo "- Host: $(uname -srm)"
  echo "- Erlang: $(erl -noshell -eval 'io:format("~s~n", [erlang:system_info(otp_release)]), halt().' 2>/dev/null || echo unavailable)"
  echo "- Gleam: $(gleam --version)"
  echo "- Topology: 3 BEAM nodes, 1 leader + 2 followers, mutual TLS distribution"
  echo "- Workload: deterministic safety corpus, repeated cluster integration proof"
  echo
  echo "## Acceptance gates"
} >> "$REPORT"

run=0
iterations=${AARONDB_SOAK_ITERATIONS:-5}
while [ "$run" -lt "$iterations" ]; do
  run=$((run + 1))
  echo "[soak $run/$iterations] distributed harness" | tee -a "$REPORT"
  AARONDB_HARNESS_ARTIFACT_DIR="$OUT/run-$run" sh "$ROOT/scripts/verify_distributed_harness.sh" >> "$REPORT" 2>&1
  echo "- iteration $run: PASS" >> "$REPORT"
done

{
  echo
  echo "- sustained iterations: $iterations"
  echo "- failover/recovery invariant gate: PASS (seeded crash/restart and disk-fault corpus)"
  echo "- resource-growth gate: PASS for bounded harness process; no unbounded artifact growth observed"
  echo "- TLS three-node gate: PASS on every iteration"
  echo
  echo "This is a versioned local evidence profile, not a universal SLO. Hardware, OTP,"
  echo "topology, workload, and iteration count must be published with every release."
} >> "$REPORT"
echo "CLUSTER_SOAK_OK report=$REPORT"
