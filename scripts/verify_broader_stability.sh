#!/bin/sh
# Profile-aware broader-stability promotion gate. Missing external evidence is NO-GO.
set -u
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT=${AARONDB_BROAD_PROMOTION_DIR:-$ROOT/artifacts/broader-stability/promotion}
case "$OUT" in /*) ;; *) OUT="$ROOT/$OUT";; esac
PROFILE_DIR=${AARONDB_BROAD_PROFILE_DIR:-$ROOT/docs/releases}
EVIDENCE_ROOT=${AARONDB_BROAD_EVIDENCE_ROOT:-$ROOT/artifacts/broader-stability}
PROFILES=${AARONDB_BROAD_PROFILES:-"long-soak-v1 upgrade-rollback-v1"}
mkdir -p "$OUT"
WITNESS="$OUT/release-witness.json"; CHECKS="$OUT/checks.jsonl"; REPORT="$OUT/release-witness.md"
: > "$CHECKS"
record() { jq -cn --arg name "$1" --arg status "$2" --arg detail "$3" '{name:$name,status:$status,detail:$detail}' >> "$CHECKS"; }
pass() { record "$1" pass "$2"; }
fail() { record "$1" fail "$2"; }
sha() { shasum -a 256 "$1" | awk '{print $1}'; }
profile_path() { case "$1" in long-soak-v1) printf '%s/docs/releases/long-soak-v1.slo.json' "$ROOT";; upgrade-rollback-v1) printf '%s/docs/releases/upgrade-rollback-v1.slo.json' "$ROOT";; *) printf '%s/%s.slo.json' "$PROFILE_DIR" "$1";; esac; }
evidence_path() { printf '%s/%s/evidence.json' "$EVIDENCE_ROOT" "$1"; }
for profile in $PROFILES; do
  p=$(profile_path "$profile"); e=$(evidence_path "$profile"); log="$OUT/$profile.validation.log"
  mkdir -p "$(dirname "$log")"
  if [ -f "$p" ] && jq -e --arg n "$profile" '.profile == $n' "$p" >/dev/null 2>&1; then pass "profile-$profile" "sha256=$(sha "$p")"; else fail "profile-$profile" "missing-or-invalid=$p"; continue; fi
  if [ ! -f "$e" ]; then fail "evidence-$profile" "missing=$e"; continue; fi
  case "$profile" in
    long-soak-v1)
      if sh "$ROOT/scripts/validate_slo_evidence.sh" "$p" "$e" >"$log" 2>&1; then pass "evidence-$profile" "sha256=$(sha "$e")"; else fail "evidence-$profile" "$(tr '\n' ' ' < "$log" 2>/dev/null || echo validation-failed)"; fi;;
    upgrade-rollback-v1)
      topology=${AARONDB_BROAD_UPGRADE_TOPOLOGY:-}
      if [ -z "$topology" ]; then fail "evidence-$profile" "missing-topology=AARONDB_BROAD_UPGRADE_TOPOLOGY";
      elif sh "$ROOT/scripts/verify_upgrade_rollback.sh" --topology "$topology" --evidence "$e" --artifacts "$OUT/upgrade-rollback-v1" >"$log" 2>&1; then pass "evidence-$profile" "sha256=$(sha "$e")"; else fail "evidence-$profile" "$(tr '\n' ' ' < "$log" 2>/dev/null || echo validation-failed)"; fi;;
    *) fail "evidence-$profile" "unsupported-profile=$profile";;
  esac
done
if sh "$ROOT/scripts/verify_lifecycle_drills.sh" >"$OUT/lifecycle.log" 2>&1; then pass lifecycle "$(tail -1 "$OUT/lifecycle.log")"; else fail lifecycle "$(tr '\n' ' ' < "$OUT/lifecycle.log" 2>/dev/null || echo failed)"; fi
if git -C "$ROOT" diff --check >"$OUT/diff-check.log" 2>&1; then pass diff-hygiene "git diff --check"; else fail diff-hygiene "dirty diff check"; fi
if git -C "$ROOT" status --porcelain | grep -q .; then fail source-state "dirty-worktree"; else pass source-state "clean-worktree"; fi
release_id=$(git -C "$ROOT" describe --always --dirty 2>/dev/null || echo unknown); now=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
jq -s --arg generated_at "$now" --arg release_id "$release_id" --arg profiles "$PROFILES" '{generated_at:$generated_at,release_id:$release_id,profiles:($profiles|split(" ")),checks:.,verdict:(if all(.[];.status=="pass") then "GO" else "NO-GO" end)}' "$CHECKS" > "$WITNESS"
{ echo '# Broader Stability Promotion Witness'; echo; echo "- Generated: $now"; echo "- Release identity: \`$release_id\`"; echo "- Verdict: **$(jq -r .verdict "$WITNESS")**"; echo; echo '| Check | Status | Detail |'; echo '|---|---|---|'; jq -r '.checks[]|"| \(.name) | \(.status) | \(.detail|gsub("\\|";"\\\\|")) |"' "$WITNESS"; } > "$REPORT"
if [ "$(jq -r .verdict "$WITNESS")" = GO ]; then echo "BROAD_PROMOTION_GO witness=$WITNESS"; exit 0; fi
echo "BROAD_PROMOTION_NO_GO witness=$WITNESS" >&2; exit 1
