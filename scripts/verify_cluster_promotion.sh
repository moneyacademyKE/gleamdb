#!/bin/sh
# Fail-closed release promotion gate for the experimental AaronDB cluster.
# It creates a witness for every invocation, including a NO-GO verdict.
set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PROFILE=${AARONDB_SLO_PROFILE:-"$ROOT/docs/releases/slo-profile-2026-08.json"}
PERFORMANCE=${AARONDB_PERFORMANCE_EVIDENCE:-"$ROOT/artifacts/cluster-performance-10000-bounded-probes/evidence.json"}
CHAOS_DIR=${AARONDB_CHAOS_ARTIFACT_DIR:-"$ROOT/artifacts/cluster-chaos"}
OUT=${AARONDB_PROMOTION_ARTIFACT_DIR:-"$ROOT/artifacts/cluster-promotion"}
RELEASE_ID=${AARONDB_RELEASE_ID:-$(git -C "$ROOT" describe --always --dirty 2>/dev/null || echo unknown)}
NOW=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
mkdir -p "$OUT"
WITNESS="$OUT/release-witness.json"
REPORT="$OUT/release-witness.md"
CHECKS="$OUT/checks.jsonl"
: > "$CHECKS"

record() {
  name=$1 status=$2 detail=$3
  jq -cn --arg name "$name" --arg status "$status" --arg detail "$detail" \
    '{name:$name,status:$status,detail:$detail}' >> "$CHECKS"
}
pass() { record "$1" pass "$2"; }
fail() { record "$1" fail "$2"; }
sha256() { shasum -a 256 "$1" | awk '{print $1}'; }

# All conditions run independently so a witness tells an operator what failed.
if [ -f "$PROFILE" ] && jq -e . "$PROFILE" >/dev/null 2>&1; then
  pass profile "profile=$(jq -r .profile "$PROFILE") sha256=$(sha256 "$PROFILE")"
else
  fail profile "missing-or-invalid path=$PROFILE"
fi

if [ -f "$PERFORMANCE" ] && [ -f "$PROFILE" ] && sh "$ROOT/scripts/validate_slo_evidence.sh" "$PROFILE" "$PERFORMANCE" >"$OUT/performance-validation.log" 2>&1; then
  pass performance "path=$PERFORMANCE sha256=$(sha256 "$PERFORMANCE") $(cat "$OUT/performance-validation.log")"
else
  detail="missing-or-invalid path=$PERFORMANCE"
  [ -s "$OUT/performance-validation.log" ] && detail=$(tr '\n' ' ' < "$OUT/performance-validation.log")
  fail performance "$detail"
fi

chaos_ok=1
for seed in 11 23 37 41; do
  evidence="$CHAOS_DIR/seed-$seed/evidence.json"
  if [ -f "$evidence" ] && jq -e --argjson seed "$seed" '
      .seed == $seed and .status == "pass" and
      (.committed_operations | type == "number" and . > 0) and
      (.quorum_recovery_us | type == "number" and . >= 0) and
      (.safety_assertions | type == "array" and length >= 4)
    ' "$evidence" >/dev/null 2>&1; then
    pass "chaos-seed-$seed" "path=$evidence sha256=$(sha256 "$evidence")"
  else
    chaos_ok=0
    fail "chaos-seed-$seed" "missing-or-incomplete path=$evidence"
  fi
done
if [ -f "$CHAOS_DIR/mutant-gate.log" ] && grep -q '^CHAOS_MUTANT_GATE_OK cases=4$' "$CHAOS_DIR/mutant-gate.log"; then
  pass chaos-mutants "path=$CHAOS_DIR/mutant-gate.log sha256=$(sha256 "$CHAOS_DIR/mutant-gate.log")"
else
  chaos_ok=0
  fail chaos-mutants "missing-or-failed path=$CHAOS_DIR/mutant-gate.log"
fi

if sh "$ROOT/scripts/test_cluster_operator.sh" >"$OUT/operator-lifecycle.log" 2>&1 && grep -q '^OPERATOR_LIFECYCLE_TEST_OK commands=13 failure_paths=3 redaction=verified$' "$OUT/operator-lifecycle.log"; then
  pass operator-lifecycle "$(tail -1 "$OUT/operator-lifecycle.log")"
else
  fail operator-lifecycle "$(tr '\n' ' ' < "$OUT/operator-lifecycle.log" 2>/dev/null || echo failed)"
fi

if PATH="/opt/homebrew/bin:$PATH" gleam format --check src test bench >"$OUT/format.log" 2>&1; then pass format "gleam format --check src test bench"; else fail format "$(tail -3 "$OUT/format.log" | tr '\n' ' ')"; fi
if PATH="/opt/homebrew/bin:$PATH" gleam check >"$OUT/check.log" 2>&1; then pass check "gleam check"; else fail check "$(tail -3 "$OUT/check.log" | tr '\n' ' ')"; fi
if PATH="/opt/homebrew/bin:$PATH" gleam test >"$OUT/test.log" 2>&1; then pass tests "gleam test"; else fail tests "$(tail -3 "$OUT/test.log" | tr '\n' ' ')"; fi
if git -C "$ROOT" diff --check >"$OUT/diff-check.log" 2>&1; then pass diff-hygiene "git diff --check"; else fail diff-hygiene "$(cat "$OUT/diff-check.log" | tr '\n' ' ')"; fi

if git -C "$ROOT" status --porcelain | grep -q .; then
  fail source-state "dirty-worktree; promotion requires an immutable reviewed release commit"
else
  pass source-state "clean-worktree"
fi

jq -s --arg generated_at "$NOW" --arg release_id "$RELEASE_ID" \
  --arg profile "$PROFILE" --arg performance "$PERFORMANCE" --arg chaos_dir "$CHAOS_DIR" '
  {generated_at:$generated_at,release_id:$release_id,inputs:{profile:$profile,performance_evidence:$performance,chaos_artifacts:$chaos_dir},checks:.,verdict:(if all(.[]; .status == "pass") then "GO" else "NO-GO" end)}
' "$CHECKS" > "$WITNESS"

{
  echo '# AaronDB Cluster Release Witness'
  echo
  echo "- Generated: $NOW"
  echo "- Release identity: \`$RELEASE_ID\`"
  echo "- Verdict: **$(jq -r .verdict "$WITNESS")**"
  echo
  echo '| Check | Status | Detail |'
  echo '|---|---|---|'
  jq -r '.checks[] | "| \(.name) | \(.status) | \(.detail | gsub("\\|"; "\\\\|")) |"' "$WITNESS"
  echo
  echo "Machine-readable witness: \`$WITNESS\`. A NO-GO result is intentional: this command never converts absent, stale, dirty, or failed evidence into a release claim."
} > "$REPORT"

if [ "$(jq -r .verdict "$WITNESS")" = "GO" ]; then
  echo "PROMOTION_GO witness=$WITNESS"
  exit 0
fi
echo "PROMOTION_NO_GO witness=$WITNESS" >&2
exit 1
