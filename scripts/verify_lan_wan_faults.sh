#!/bin/sh
# Run bounded LAN/WAN network-fault scenarios against a provisioned, independent
# three-host topology. This command fails closed: it never substitutes a
# same-host simulation for a requested cross-host profile.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
usage() {
  cat <<'EOF'
Usage: verify_lan_wan_faults.sh --topology FILE --adapter FILE [--ops N] [--artifacts DIR]

TOPOLOGY is an independent-host-lan-v1 manifest extended with each node's
`network_interface`. ADAPTER is an operator-owned executable which is invoked
as: ADAPTER apply|clear SEED SCENARIO TOPOLOGY. It must make the named fault
real on the named hosts, then emit AARONDB_FAULT_APPLIED / _CLEARED records.

The runner does not implement packet loss with sleeps or call a same-host test
an independent-host WAN proof. It requires a real adapter (for example,
privileged tc/netem + nftables on the hosts) and invokes the authenticated
three-host executor while each schedule is active.
EOF
}
die() { printf '%s\n' "LAN/WAN fault runner: $*" >&2; exit 64; }

TOPOLOGY=
ADAPTER=
OPS=${AARONDB_LAN_WAN_OPS:-100}
OUT=
while [ "$#" -gt 0 ]; do
  case "$1" in
    --topology) TOPOLOGY=${2:-}; shift 2;;
    --adapter) ADAPTER=${2:-}; shift 2;;
    --ops) OPS=${2:-}; shift 2;;
    --artifacts) OUT=${2:-}; shift 2;;
    -h|--help) usage; exit 0;;
    *) die "unknown option: $1";;
  esac
done
[ -n "$TOPOLOGY" ] && [ -f "$TOPOLOGY" ] || die "--topology FILE is required"
[ -n "$ADAPTER" ] && [ -x "$ADAPTER" ] || die "--adapter must be an executable operator-owned fault adapter"
case "$OPS" in ''|*[!0-9]*|0) die "--ops must be a positive integer";; esac
command -v jq >/dev/null 2>&1 || die "jq is required"
jq -e '
  .schema == 1 and .profile == "independent-host-lan-v1" and
  (.nodes | length == 3) and
  ([.nodes[].id] | sort | . == ["a","b","c"]) and
  ([.nodes[].host] | unique | length == 3) and
  ([.nodes[].network_interface] | all(type == "string" and length > 0 and startswith("REPLACE_WITH_") | not))
' "$TOPOLOGY" >/dev/null || die "topology must contain a real network_interface for every distinct a/b/c host"

RUN_ID=${AARONDB_LAN_WAN_RUN_ID:-"$(date +%Y%m%dT%H%M%S)-$$"}
OUT=${OUT:-"$ROOT/artifacts/broader-stability/wan-emulation-v1/$RUN_ID"}
mkdir -p "$OUT"
ACTIVE_SEED=
cleanup() {
  if [ -n "$ACTIVE_SEED" ]; then
    "$ADAPTER" clear "$ACTIVE_SEED" cleanup "$TOPOLOGY" >>"$OUT/adapter-cleanup.log" 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM

run_seed() {
  seed=$1
  scenario=$2
  dir="$OUT/seed-$seed"
  mkdir -p "$dir"
  printf '%s\n' "$scenario" >"$dir/schedule.txt"
  ACTIVE_SEED=$seed
  "$ADAPTER" apply "$seed" "$scenario" "$TOPOLOGY" >"$dir/adapter-apply.log" 2>&1 || {
    cat "$dir/adapter-apply.log" >&2; die "adapter failed to apply seed $seed";
  }
  grep -q "^AARONDB_FAULT_APPLIED seed=$seed " "$dir/adapter-apply.log" || die "adapter did not attest a real applied fault for seed $seed"
  if sh "$ROOT/scripts/verify_independent_host_cluster.sh" --topology "$TOPOLOGY" --ops "$OPS" --artifacts "$dir/cluster" >"$dir/run.log" 2>&1; then
    result=pass
  else
    result=fail
  fi
  "$ADAPTER" clear "$seed" "$scenario" "$TOPOLOGY" >"$dir/adapter-clear.log" 2>&1 || {
    cat "$dir/adapter-clear.log" >&2; die "adapter failed to clear seed $seed";
  }
  grep -q "^AARONDB_FAULT_CLEARED seed=$seed " "$dir/adapter-clear.log" || die "adapter did not attest cleanup for seed $seed"
  ACTIVE_SEED=
  [ "$result" = pass ] || { cat "$dir/run.log" >&2; die "authenticated topology failed under seed $seed"; }
  jq -n --argjson seed "$seed" --arg scenario "$scenario" \
    --arg topology_sha256 "$(shasum -a 256 "$TOPOLOGY" | awk '{print $1}')" \
    --arg adapter_sha256 "$(shasum -a 256 "$ADAPTER" | awk '{print $1}')" \
    '{seed:$seed,scenario:$scenario,status:"pass",topology_sha256:$topology_sha256,adapter_sha256:$adapter_sha256,required_invariants:["mTLS authenticated topology", "fault applied and cleared", "committed workload", "unknown certificate rejected"]}' >"$dir/evidence.json"
  echo "LAN_WAN_SEED_OK seed=$seed artifact=$dir"
}

run_seed 101 'symmetric a<->b partition then heal'
run_seed 103 'asymmetric a->c 1% loss 50ms jitter reorder duplicate then heal'
run_seed 107 'slow follower c; restart b; membership churn d denied; clock skew a'

# The reference oracle is independent evidence: ensure known-bad state models
# still fail rather than merely observing a green network run.
for mutant in known_bad_split_brain_mutant_is_detected_test known_bad_duplicate_apply_mutant_is_detected_test known_bad_stale_fence_mutant_is_detected_test known_bad_unsafe_recovery_mutant_is_detected_test; do
  grep -q "pub fn $mutant" "$ROOT/test/aarondb/distributed_harness_test.gleam" || die "missing known-bad mutant contract: $mutant"
done
gleam test >"$OUT/mutant-gate.log" 2>&1 || { cat "$OUT/mutant-gate.log" >&2; exit 1; }
printf '%s\n' 'LAN_WAN_MUTANT_GATE_OK cases=4' >>"$OUT/mutant-gate.log"
jq -n --arg profile wan-emulation-v1 --arg run_id "$RUN_ID" \
  --arg topology_sha256 "$(shasum -a 256 "$TOPOLOGY" | awk '{print $1}')" \
  '{profile:$profile,run_id:$run_id,status:"pass",topology_sha256:$topology_sha256,seeds:[101,103,107],mutants_rejected:4}' >"$OUT/evidence.json"
echo "LAN_WAN_EVIDENCE_OK artifacts=$OUT"
