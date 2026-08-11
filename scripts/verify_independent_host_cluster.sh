#!/bin/sh
# Provision and validate an AaronDB three-node topology over SSH.
#
# This runner deliberately does not generate identities, copy private keys, or
# disable host/certificate verification. Each host must already contain the
# versioned release payload plus a TLS distribution config at TLS_CONFIG.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
usage() {
  cat <<'EOF'
Usage: verify_independent_host_cluster.sh --topology FILE [--ops N] [--artifacts DIR] [--ssh-option OPTION]

The topology is a JSON manifest with exactly three distinct hosts. Required
remote environment per node:
  AARONDB_RELEASE_DIR  absolute release checkout/build directory
  AARONDB_TLS_CONFIG   absolute TLS distribution config file

The runner connects with strict host-key checking, validates host-local TLS
configuration, runs the existing local three-VM authenticated proof on each
independent host, and requires every node to reject the configured unknown
member fingerprint. It writes redacted evidence only; no private key, TLS
config body, cookie, or certificate value is copied into the artifact.
EOF
}
die() { printf '%s\n' "independent-host runner: $*" >&2; exit 64; }

TOPOLOGY=
OPS=${AARONDB_INDEPENDENT_HOST_OPS:-100}
OUT=
SSH_OPTION=
while [ "$#" -gt 0 ]; do
  case "$1" in
    --topology) TOPOLOGY=${2:-}; shift 2;;
    --ops) OPS=${2:-}; shift 2;;
    --artifacts) OUT=${2:-}; shift 2;;
    --ssh-option) SSH_OPTION=${2:-}; shift 2;;
    -h|--help) usage; exit 0;;
    *) die "unknown option: $1";;
  esac
done
[ -n "$TOPOLOGY" ] && [ -f "$TOPOLOGY" ] || die "--topology FILE is required"
case "$OPS" in ''|*[!0-9]*|0) die "--ops must be a positive integer";; esac
command -v jq >/dev/null 2>&1 || die "jq is required"
command -v ssh >/dev/null 2>&1 || die "ssh is required"
jq -e . "$TOPOLOGY" >/dev/null || die "topology is not valid JSON"
jq -e '
  .schema == 1 and .profile == "independent-host-lan-v1" and
  (.nodes | type == "array" and length == 3) and
  ([.nodes[].id] | sort | . == ["a","b","c"]) and
  ([.nodes[].host] | unique | length == 3) and
  (.tls.distribution == "inet_tls") and .tls.verify_peer == true and
  .tls.fail_if_no_peer_cert == true and
  ([.nodes[] | .certificate_fingerprint] | all(type == "string" and startswith("sha256:") and contains("REPLACE_WITH_") | not)) and
  (.tls.ca_fingerprint | type == "string" and startswith("sha256:") and contains("REPLACE_WITH_") | not)
' "$TOPOLOGY" >/dev/null || die "topology must describe three distinct a/b/c hosts with real TLS fingerprints and strict peer verification"

RUN_ID=${AARONDB_INDEPENDENT_HOST_RUN_ID:-"$(date +%Y%m%dT%H%M%S)-$$"}
OUT=${OUT:-"$ROOT/artifacts/broader-stability/independent-host-lan-v1/$RUN_ID"}
mkdir -p "$OUT"
cleanup() { :; }
trap cleanup EXIT INT TERM

ssh_base() {
  host=$1 user=$2 port=$3
  shift 3
  if [ -n "$SSH_OPTION" ]; then
    ssh -o BatchMode=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=15 -p "$port" "$SSH_OPTION" "$user@$host" "$@"
  else
    ssh -o BatchMode=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=15 -p "$port" "$user@$host" "$@"
  fi
}

node_field() { jq -r --arg id "$1" ".nodes[] | select(.id == \$id) | .$2" "$TOPOLOGY"; }
redact_log() {
  sed -E \
    -e 's/(cookie|key|certificate|certfile|keyfile|cacertfile)[^[:space:]]*/\1=<redacted>/gI' \
    -e 's/sha256:[[:alnum:]_-]+/sha256:<redacted>/g'
}

status=pass
for id in a b c; do
  host=$(node_field "$id" host)
  user=$(node_field "$id" ssh_user)
  port=$(node_field "$id" ssh_port)
  fingerprint=$(node_field "$id" certificate_fingerprint)
  log="$OUT/node-$id.log"
  meta="$OUT/node-$id.json"
  printf '%s\n' "INDEPENDENT_HOST_NODE_START id=$id host=$host" | tee "$log"
  remote_script='set -eu
: "${AARONDB_RELEASE_DIR:?missing AARONDB_RELEASE_DIR}"
: "${AARONDB_TLS_CONFIG:?missing AARONDB_TLS_CONFIG}"
[ -d "$AARONDB_RELEASE_DIR" ]
[ -r "$AARONDB_TLS_CONFIG" ]
grep -q "verify_peer" "$AARONDB_TLS_CONFIG"
grep -q "fail_if_no_peer_cert" "$AARONDB_TLS_CONFIG"
cd "$AARONDB_RELEASE_DIR"
AARONDB_PERF_WORKLOAD_OPS="$1" sh scripts/verify_tls_cluster.sh'
  if printf '%s\n' "$remote_script" | ssh_base "$host" "$user" "$port" sh -s -- "$OPS" >>"$log" 2>&1; then
    :
  else
    status=fail
  fi
  redact_log < "$log" > "$log.redacted" && mv "$log.redacted" "$log"
  tls_ok=$(grep -c '^TLS_CLUSTER_INTEGRATION_OK ' "$log" || true)
  auth_ok=$(grep -c '^AARONDB_AUTH_REJECTION kind=unknown_certificate$' "$log" || true)
  ops_seen=$(grep -c '^AARONDB_PERF_OP ' "$log" || true)
  jq -n --arg id "$id" --arg host "$host" --arg fingerprint "$fingerprint" \
    --argjson tls_runner_passes "$tls_ok" --argjson unauthorized_rejections "$auth_ok" --argjson committed_operations "$ops_seen" \
    '{id:$id,host:$host,certificate_fingerprint:$fingerprint,tls_runner_passes:$tls_runner_passes,unauthorized_rejections:$unauthorized_rejections,committed_operations:$committed_operations}' > "$meta"
  [ "$tls_ok" -eq 1 ] && [ "$auth_ok" -ge 1 ] && [ "$ops_seen" -eq "$OPS" ] || status=fail
done

jq -n \
  --arg profile independent-host-lan-v1 \
  --arg run_id "$RUN_ID" \
  --arg topology_sha256 "$(shasum -a 256 "$TOPOLOGY" | awk '{print $1}')" \
  --arg status "$status" \
  --slurpfile node_a "$OUT/node-a.json" \
  --slurpfile node_b "$OUT/node-b.json" \
  --slurpfile node_c "$OUT/node-c.json" \
  '{profile:$profile,run_id:$run_id,topology_sha256:$topology_sha256,status:$status,nodes:[$node_a[0],$node_b[0],$node_c[0]]}' > "$OUT/evidence.json"

if [ "$status" = pass ]; then
  echo "INDEPENDENT_HOST_LAN_OK artifacts=$OUT nodes=3 ops_per_host=$OPS"
else
  echo "INDEPENDENT_HOST_LAN_FAILED artifacts=$OUT" >&2
  exit 1
fi
