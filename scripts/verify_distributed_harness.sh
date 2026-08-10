#!/bin/sh
set -eu

# Named production gate: compile, run the full suite, then run the real
# authenticated three-VM proof when TLS tooling is available. Never hide a
# failing seed; preserve its seed and deterministic schedule in the log.
LOG_DIR=${AARONDB_HARNESS_ARTIFACT_DIR:-artifacts/distributed-harness}
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/run.log"
: > "$LOG_FILE"

run_step() {
  name=$1
  shift
  echo "[$name] $*" | tee -a "$LOG_FILE"
  "$@" 2>&1 | tee -a "$LOG_FILE"
}

run_step format gleam format --check src test bench
run_step check gleam check
run_step tests gleam test
run_step chaos sh scripts/verify_cluster_chaos.sh

if command -v openssl >/dev/null 2>&1 && command -v erl >/dev/null 2>&1; then
  run_step tls sh scripts/verify_tls_cluster.sh
else
  echo "[tls] skipped: openssl and erl are required" | tee -a "$LOG_FILE"
fi

echo "DISTRIBUTED_HARNESS_OK log=$LOG_FILE" | tee -a "$LOG_FILE"
