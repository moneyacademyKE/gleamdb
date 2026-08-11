#!/bin/sh
# Fail-closed validator for versioned AaronDB SLO evidence.
# Usage: sh scripts/validate_slo_evidence.sh <profile.json> <evidence.json>
set -eu
profile=${1:-}
evidence=${2:-}
[ -n "$profile" ] && [ -n "$evidence" ] || { echo 'SLO_INVALID usage profile.json evidence.json' >&2; exit 1; }
fail() { echo "SLO_INVALID $*" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || fail 'jq is required'
[ -f "$profile" ] || fail "missing profile=$profile"
[ -f "$evidence" ] || fail "missing evidence=$evidence"
profile_name=$(jq -er '.profile' "$profile") || fail 'profile missing or invalid'
evidence_name=$(jq -er '.profile' "$evidence") || fail 'evidence profile missing or invalid'
[ "$profile_name" = "$evidence_name" ] || fail "profile-mismatch expected=$profile_name actual=$evidence_name"
generated=$(jq -er '.generated_at' "$evidence") || fail 'generated_at missing'
now=$(date -u +%s)
generated_epoch=$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$generated" +%s 2>/dev/null) || fail 'generated_at must be UTC ISO-8601'
age=$((now - generated_epoch))
max_age=$(jq -er '.freshness.max_age_seconds' "$profile") || fail 'freshness.max_age_seconds missing'
[ "$age" -ge 0 ] && [ "$age" -le "$max_age" ] || fail "stale age_seconds=$age"
samples=$(jq -er '.samples' "$evidence") || fail 'samples missing'
minimum=$(jq -er '.assumptions.minimum_samples' "$profile") || fail 'minimum_samples missing'
[ "$samples" -ge "$minimum" ] || fail "under-sampled samples=$samples minimum=$minimum"
violations=''
while IFS='|' read -r path kind limit; do
  jq_path=$(printf '%s' "$path" | jq -R 'split(".")')
  actual=$(jq -er --argjson path "$jq_path" '
    getpath($path) as $value
    | if ($value | type) == "number" and ($value | isfinite) then $value else error("metric must be finite JSON number") end
  ' "$evidence" 2>/dev/null) || { violations="$violations $path-missing-or-nonnumeric"; continue; }
  if [ "$kind" = min ] && ! awk -v a="$actual" -v l="$limit" 'BEGIN { exit !(a >= l) }'; then violations="$violations $path"; fi
  if [ "$kind" = max ] && ! awk -v a="$actual" -v l="$limit" 'BEGIN { exit !(a <= l) }'; then violations="$violations $path"; fi
done <<EOF
$(jq -r '.thresholds as $t | $t | paths(scalars) as $p | [(["observed"] + $p | map(tostring) | join(".")), (if ($p[-1]|startswith("min_")) then "min" else "max" end), ($t|getpath($p))] | @tsv' "$profile" | tr '\t' '|')
EOF
[ -z "$violations" ] || fail "threshold-violations:$violations"
echo "SLO_VALID profile=$profile_name samples=$samples"
