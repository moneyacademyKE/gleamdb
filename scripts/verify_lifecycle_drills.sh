#!/bin/sh
# Fail-closed lifecycle and incident-drill contract for the public operator API.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/aarondb-lifecycle.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM
ctl="$ROOT/scripts/aarondb-clusterctl.sh"
fail() { echo "LIFECYCLE_NO_GO $*" >&2; exit 1; }
expect_fail() { label=$1; shift; if "$@" >"$TMP/$label.out" 2>"$TMP/$label.err"; then fail "expected_failure=$label"; fi; }

node_a="$TMP/a"; node_b="$TMP/b"; backup="$TMP/backup"; restored="$TMP/restored"; incident="$TMP/incident"
sh "$ctl" bootstrap --data-dir "$node_a" --cluster lifecycle-a --members a,b,c >/dev/null
sh "$ctl" backup --data-dir "$node_a" --destination "$backup" >/dev/null
expect_fail restore_nonempty sh "$ctl" restore --data-dir "$node_a" --source "$backup" --confirm RESTORE_CLUSTER
expect_fail restore_ungated sh "$ctl" restore --data-dir "$restored" --source "$backup"
sh "$ctl" restore --data-dir "$restored" --source "$backup" --confirm RESTORE_CLUSTER >/dev/null
cmp "$node_a/operator-state.json" "$restored/operator-state.json" || fail restore_state_mismatch
sh "$ctl" rotate --data-dir "$node_a" --node b --fingerprint old-fingerprint >/dev/null
sh "$ctl" revoke --data-dir "$node_a" --fingerprint old-fingerprint >/dev/null
sh "$ctl" rebuild --data-dir "$node_a" --projection facts >/dev/null
sh "$ctl" collect --data-dir "$node_a" --output "$incident" >/dev/null
[ -s "$incident/status.json" ] || fail missing_status
[ -s "$incident/diagnostics.json" ] || fail missing_diagnostics
expect_fail bad_checksum sh -c "printf 'tampered' >> '$backup/operator-state.json'; '$ctl' restore --data-dir '$TMP/tampered' --source '$backup' --confirm RESTORE_CLUSTER"
sh "$ctl" shutdown --data-dir "$node_a" >/dev/null
jq -e '.state == "stopped" and (.alarms | length) > 0 and (.rotations | length) == 1 and (.revocations | length) == 1' "$node_a/operator-state.json" >/dev/null || fail lifecycle_state_mismatch
printf '%s\n' 'LIFECYCLE_DRILLS_OK backup_restore=verified rotation_revocation=verified rebuild=verified incident_collection=verified fail_closed=verified'
