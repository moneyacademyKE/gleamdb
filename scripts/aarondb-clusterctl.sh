#!/bin/sh
# AaronDB cluster operator surface. This script is deliberately a narrow wrapper:
# operators use named commands and JSON state, never ad-hoc BEAM eval expressions.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
usage() {
  cat <<'EOF'
Usage: aarondb-clusterctl.sh <command> [options]

Commands:
  bootstrap  --data-dir DIR --cluster ID --members a,b,c
  status     --data-dir DIR
  diagnose   --data-dir DIR
  backup     --data-dir DIR --destination DIR
  restore    --data-dir DIR --source DIR --confirm RESTORE_CLUSTER
  rotate     --data-dir DIR --node ID --fingerprint FP
  revoke     --data-dir DIR --fingerprint FP
  shutdown   --data-dir DIR
  acknowledge-recovery --data-dir DIR --reason TEXT --confirm ACK_UNSAFE_RECOVERY
  rebuild    --data-dir DIR --projection NAME
  collect    --data-dir DIR --output DIR
  verify     [--ops N]

All state paths are operator-owned. Destructive commands require their exact
confirmation token and never overwrite a non-empty replacement directory.
EOF
}
die() { echo "clusterctl: $*" >&2; exit 64; }
need_jq() { command -v jq >/dev/null 2>&1 || die "jq is required"; }
require_dir() { [ -n "${DATA_DIR:-}" ] || die "--data-dir is required"; }
state_path() { printf '%s/operator-state.json' "$DATA_DIR"; }
require_state() { require_dir; [ -f "$(state_path)" ] || die "cluster is not bootstrapped"; }
redact() { sed -E 's/(fingerprint|certificate|key|token)[^,[:space:]}]*/\1=<redacted>/gI'; }

command=${1:-}
[ -n "$command" ] || { usage >&2; exit 64; }
shift || true
DATA_DIR= CLUSTER= MEMBERS= DESTINATION= SOURCE= CONFIRM= NODE= FINGERPRINT= REASON= PROJECTION= OUTPUT= OPS=10
while [ "$#" -gt 0 ]; do
  case "$1" in
    --data-dir) DATA_DIR=${2:-}; shift 2;;
    --cluster) CLUSTER=${2:-}; shift 2;;
    --members) MEMBERS=${2:-}; shift 2;;
    --destination) DESTINATION=${2:-}; shift 2;;
    --source) SOURCE=${2:-}; shift 2;;
    --confirm) CONFIRM=${2:-}; shift 2;;
    --node) NODE=${2:-}; shift 2;;
    --fingerprint) FINGERPRINT=${2:-}; shift 2;;
    --reason) REASON=${2:-}; shift 2;;
    --projection) PROJECTION=${2:-}; shift 2;;
    --output) OUTPUT=${2:-}; shift 2;;
    --ops) OPS=${2:-}; shift 2;;
    -h|--help) usage; exit 0;;
    *) die "unknown option: $1";;
  esac
done
need_jq

case "$command" in
  bootstrap)
    require_dir
    [ -n "$CLUSTER" ] && [ -n "$MEMBERS" ] || die "--cluster and --members are required"
    if [ -e "$DATA_DIR" ] && [ "$(find "$DATA_DIR" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]; then
      die "bootstrap requires an empty data directory"
    fi
    mkdir -p "$DATA_DIR"
    umask 077
    jq -n --arg cluster "$CLUSTER" --arg members "$MEMBERS" \
      '{schema:1,cluster:$cluster,members:($members|split(",")),state:"running",alarms:[],rotations:[],revocations:[],rebuilds:[]}' > "$(state_path)"
    echo "BOOTSTRAP_OK cluster=$CLUSTER members=$MEMBERS data_dir=$DATA_DIR"
    ;;
  status)
    require_state
    jq -e '{cluster,members,state,alarms,revocations,latest_rebuild:(.rebuilds[-1] // null)}' "$(state_path)" | redact
    ;;
  diagnose)
    require_state
    jq -e '{cluster,members,state,alarm_count:(.alarms|length),revocation_count:(.revocations|length),rotation_count:(.rotations|length),rebuild_count:(.rebuilds|length)}' "$(state_path)" | redact
    echo "DIAGNOSE_OK data_dir=$DATA_DIR"
    ;;
  backup)
    require_state
    [ -n "$DESTINATION" ] || die "--destination is required"
    [ ! -e "$DESTINATION" ] || die "backup destination must not already exist"
    mkdir -p "$DESTINATION"
    cp "$(state_path)" "$DESTINATION/operator-state.json"
    jq -S . "$DESTINATION/operator-state.json" | shasum -a 256 | awk '{print $1}' > "$DESTINATION/operator-state.sha256"
    echo "BACKUP_OK destination=$DESTINATION"
    ;;
  restore)
    require_dir
    [ "$CONFIRM" = RESTORE_CLUSTER ] || die "restore requires --confirm RESTORE_CLUSTER"
    [ -n "$SOURCE" ] && [ -f "$SOURCE/operator-state.json" ] && [ -f "$SOURCE/operator-state.sha256" ] || die "source is not a verified backup"
    [ ! -e "$DATA_DIR" ] || [ -z "$(find "$DATA_DIR" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ] || die "restore requires an empty replacement directory"
    expected=$(cat "$SOURCE/operator-state.sha256")
    actual=$(jq -S . "$SOURCE/operator-state.json" | shasum -a 256 | awk '{print $1}')
    [ "$expected" = "$actual" ] || die "backup checksum mismatch"
    mkdir -p "$DATA_DIR"
    cp "$SOURCE/operator-state.json" "$(state_path)"
    echo "RESTORE_OK data_dir=$DATA_DIR source=$SOURCE"
    ;;
  rotate)
    require_state; [ -n "$NODE" ] && [ -n "$FINGERPRINT" ] || die "--node and --fingerprint are required"
    tmp="$(state_path).tmp"
    jq --arg node "$NODE" --arg fingerprint "$FINGERPRINT" '.rotations += [{node:$node,fingerprint:$fingerprint,state:"staged"}]' "$(state_path)" > "$tmp" && mv "$tmp" "$(state_path)"
    echo "ROTATE_OK node=$NODE fingerprint=<redacted>"
    ;;
  revoke)
    require_state; [ -n "$FINGERPRINT" ] || die "--fingerprint is required"
    tmp="$(state_path).tmp"
    jq --arg fingerprint "$FINGERPRINT" '.revocations += [$fingerprint] | .alarms += ["certificate_revoked"]' "$(state_path)" > "$tmp" && mv "$tmp" "$(state_path)"
    echo "REVOKE_OK fingerprint=<redacted>"
    ;;
  shutdown)
    require_state
    tmp="$(state_path).tmp"; jq '.state="stopped"' "$(state_path)" > "$tmp" && mv "$tmp" "$(state_path)"
    echo "SHUTDOWN_OK cluster=$(jq -r .cluster "$(state_path)")"
    ;;
  acknowledge-recovery)
    require_state; [ "$CONFIRM" = ACK_UNSAFE_RECOVERY ] || die "acknowledgement requires --confirm ACK_UNSAFE_RECOVERY"; [ -n "$REASON" ] || die "--reason is required"
    tmp="$(state_path).tmp"; jq --arg reason "$REASON" '.alarms += ["UnsafeRecoveryAcknowledged: " + $reason]' "$(state_path)" > "$tmp" && mv "$tmp" "$(state_path)"
    echo "RECOVERY_ACKNOWLEDGED reason=$REASON"
    ;;
  rebuild)
    require_state; [ -n "$PROJECTION" ] || die "--projection is required"
    tmp="$(state_path).tmp"; jq --arg projection "$PROJECTION" '.rebuilds += [{projection:$projection,state:"requested"}]' "$(state_path)" > "$tmp" && mv "$tmp" "$(state_path)"
    echo "REBUILD_REQUESTED projection=$PROJECTION"
    ;;
  collect)
    require_state; [ -n "$OUTPUT" ] || die "--output is required"; [ ! -e "$OUTPUT" ] || die "diagnostic output must not already exist"
    mkdir -p "$OUTPUT"
    sh "$0" diagnose --data-dir "$DATA_DIR" > "$OUTPUT/diagnostics.json"
    sh "$0" status --data-dir "$DATA_DIR" > "$OUTPUT/status.json"
    echo "COLLECT_OK output=$OUTPUT"
    ;;
  verify)
    case "$OPS" in ''|*[!0-9]*|0) die "--ops must be a positive integer";; esac
    AARONDB_PERF_WORKLOAD_OPS="$OPS" sh "$ROOT/scripts/verify_tls_cluster.sh"
    echo "VERIFY_OK ops=$OPS"
    ;;
  *) usage >&2; die "unknown command: $command";;
esac
