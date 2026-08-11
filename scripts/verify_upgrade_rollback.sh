#!/bin/sh
# Fail-closed validator for independent-host mixed-version upgrade/rollback evidence.
# It validates retained evidence; it never executes upgrades, copies credentials,
# or treats host-local lifecycle drills as an independent-host result.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PROFILE=${AARONDB_UPGRADE_PROFILE:-$ROOT/docs/releases/upgrade-rollback-v1.slo.json}
TOPOLOGY=${AARONDB_UPGRADE_TOPOLOGY:-}
EVIDENCE=${AARONDB_UPGRADE_EVIDENCE:-}
OUT=${AARONDB_UPGRADE_ARTIFACT_DIR:-$ROOT/artifacts/broader-stability/upgrade-rollback-v1/validation-$(date -u +%Y%m%dT%H%M%SZ)}

usage() {
  cat <<'EOF'
Usage: verify_upgrade_rollback.sh --topology FILE --evidence FILE [--artifacts DIR]

Validate evidence produced by an operator-owned, independent-host N/N-1 rolling
upgrade and rollback run. The evidence must retain the source identity, topology
hash, distinct a/b/c host identities, version transition transcript, state hashes,
operator outcomes, and alarm records. Missing or malformed evidence is NO-GO.

This command does not run an upgrade and does not make same-host lifecycle drills
into cross-host compatibility proof.
EOF
}
die() { printf '%s\n' "UPGRADE_ROLLBACK_NO_GO $*" >&2; exit 1; }
while [ "$#" -gt 0 ]; do
  case "$1" in
    --topology) TOPOLOGY=${2:-}; shift 2;;
    --evidence) EVIDENCE=${2:-}; shift 2;;
    --artifacts) OUT=${2:-}; shift 2;;
    -h|--help) usage; exit 0;;
    *) die "unknown option=$1";;
  esac
done
command -v jq >/dev/null 2>&1 || die 'jq is required'
[ -f "$PROFILE" ] || die "missing profile=$PROFILE"
[ -n "$TOPOLOGY" ] && [ -f "$TOPOLOGY" ] || die '--topology FILE is required'
[ -n "$EVIDENCE" ] && [ -f "$EVIDENCE" ] || die '--evidence FILE is required'
mkdir -p "$OUT"
LOG="$OUT/validation.log"

jq -e '.profile == "upgrade-rollback-v1" and .schema == 1' "$PROFILE" >/dev/null || die 'invalid profile'
jq -e '
  .schema == 1 and .profile == "independent-host-lan-v1" and
  ([.nodes[].id] | sort | . == ["a","b","c"]) and
  ([.nodes[].host] | unique | length == 3) and
  (.tls.verify_peer == true) and (.tls.fail_if_no_peer_cert == true)
' "$TOPOLOGY" >/dev/null || die 'topology must be a strict three-distinct-host mTLS manifest'
topology_sha=$(shasum -a 256 "$TOPOLOGY" | awk '{print $1}')
source_head=$(git -C "$ROOT" rev-parse HEAD)

jq -e --arg topology_sha "$topology_sha" --arg source_head "$source_head" '
  .schema == 1 and .profile == "upgrade-rollback-v1" and
  (.status == "pass") and
  (.topology_sha256 == $topology_sha) and
  (.source.commit | type == "string" and length >= 7) and
  (.source.commit == $source_head) and
  (.source.dirty == false) and
  (.hosts | type == "array" and length == 3 and ([.[].id] | sort | . == ["a","b","c"]) and ([.[].host] | unique | length == 3)) and
  (.versions | type == "object" and (.from | type == "string" and length > 0) and (.to | type == "string" and length > 0) and .from != .to) and
  (.transcript | type == "array" and length >= 6 and
    ([.[] | .action] | index("upgrade")) and ([.[] | .action] | index("rollback")) and
    ([.[] | .result] | all(. == "pass"))) and
  (.state_hashes | type == "object" and (.before | type == "string" and length > 0) and (.after_upgrade | type == "string" and length > 0) and (.after_rollback | type == "string" and length > 0) and .before == .after_upgrade and .before == .after_rollback) and
  (.operator_commands | type == "array" and length > 0 and all(.[]; .redacted == true and .result == "pass")) and
  (.alarms | type == "array" and ([.[] | .kind] | index("leader_movement")) and ([.[] | .kind] | index("identity_rotation")) and ([.[] | .kind] | index("rollback"))) and
  (.unsupported_version_pair_refused == true) and
  (.restore_verified == true)
' "$EVIDENCE" >"$LOG" 2>&1 || { cat "$LOG" >&2; die 'evidence is missing required independent-host upgrade/rollback proof'; }

jq -n --arg profile upgrade-rollback-v1 --arg topology_sha256 "$topology_sha" --arg source_commit "$source_head" --arg evidence_sha256 "$(shasum -a 256 "$EVIDENCE" | awk '{print $1}')" \
  '{profile:$profile,status:"pass",topology_sha256:$topology_sha256,source_commit:$source_commit,evidence_sha256:$evidence_sha256}' > "$OUT/validation.json"
printf '%s\n' "UPGRADE_ROLLBACK_OK artifact=$OUT evidence=$EVIDENCE"
