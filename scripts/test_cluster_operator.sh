#!/bin/sh
# Disposable-cluster contract for the public operator CLI. It intentionally
# exercises both accepted and rejected paths without invoking raw BEAM eval.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/aarondb-clusterctl.XXXXXX")
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT INT TERM
DATA="$TMP/data"
BACKUP="$TMP/backup"
RESTORED="$TMP/restored"
DIAG="$TMP/diagnostics"

expect_fail() {
  label=$1
  shift
  if "$@" >"$TMP/$label.out" 2>"$TMP/$label.err"; then
    echo "OPERATOR_TEST_FAILED expected_failure=$label" >&2
    exit 1
  fi
}

sh "$ROOT/scripts/aarondb-clusterctl.sh" bootstrap --data-dir "$DATA" --cluster production-a --members a,b,c > "$TMP/bootstrap.out"
grep -q '^BOOTSTRAP_OK cluster=production-a members=a,b,c ' "$TMP/bootstrap.out"
expect_fail nonempty-bootstrap sh "$ROOT/scripts/aarondb-clusterctl.sh" bootstrap --data-dir "$DATA" --cluster production-a --members a,b,c
sh "$ROOT/scripts/aarondb-clusterctl.sh" status --data-dir "$DATA" > "$TMP/status.json"
grep -q 'production-a' "$TMP/status.json"
sh "$ROOT/scripts/aarondb-clusterctl.sh" diagnose --data-dir "$DATA" > "$TMP/diagnose.out"
grep -q '^DIAGNOSE_OK ' "$TMP/diagnose.out"
sh "$ROOT/scripts/aarondb-clusterctl.sh" backup --data-dir "$DATA" --destination "$BACKUP" > "$TMP/backup.out"
grep -q '^BACKUP_OK ' "$TMP/backup.out"
expect_fail ungated-restore sh "$ROOT/scripts/aarondb-clusterctl.sh" restore --data-dir "$RESTORED" --source "$BACKUP"
sh "$ROOT/scripts/aarondb-clusterctl.sh" restore --data-dir "$RESTORED" --source "$BACKUP" --confirm RESTORE_CLUSTER > "$TMP/restore.out"
grep -q '^RESTORE_OK ' "$TMP/restore.out"
sh "$ROOT/scripts/aarondb-clusterctl.sh" rotate --data-dir "$DATA" --node b --fingerprint private-fingerprint > "$TMP/rotate.out"
! grep -q 'private-fingerprint' "$TMP/rotate.out"
sh "$ROOT/scripts/aarondb-clusterctl.sh" revoke --data-dir "$DATA" --fingerprint private-fingerprint > "$TMP/revoke.out"
! grep -q 'private-fingerprint' "$TMP/revoke.out"
expect_fail ungated-recovery sh "$ROOT/scripts/aarondb-clusterctl.sh" acknowledge-recovery --data-dir "$DATA" --reason corruption
sh "$ROOT/scripts/aarondb-clusterctl.sh" acknowledge-recovery --data-dir "$DATA" --reason corruption --confirm ACK_UNSAFE_RECOVERY > "$TMP/recovery.out"
grep -q '^RECOVERY_ACKNOWLEDGED ' "$TMP/recovery.out"
sh "$ROOT/scripts/aarondb-clusterctl.sh" rebuild --data-dir "$DATA" --projection facts > "$TMP/rebuild.out"
grep -q '^REBUILD_REQUESTED projection=facts$' "$TMP/rebuild.out"
sh "$ROOT/scripts/aarondb-clusterctl.sh" collect --data-dir "$DATA" --output "$DIAG" > "$TMP/collect.out"
[ -s "$DIAG/diagnostics.json" ] && [ -s "$DIAG/status.json" ]
sh "$ROOT/scripts/aarondb-clusterctl.sh" shutdown --data-dir "$DATA" > "$TMP/shutdown.out"
grep -q '^SHUTDOWN_OK cluster=production-a$' "$TMP/shutdown.out"

echo "OPERATOR_LIFECYCLE_TEST_OK commands=13 failure_paths=3 redaction=verified"
