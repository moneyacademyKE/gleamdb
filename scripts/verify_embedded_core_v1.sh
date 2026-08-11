#!/bin/sh
# Fail-closed structural verification for the embedded-core-v1 certification profile.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PROFILE=${AARONDB_CERTIFICATION_PROFILE:-"$ROOT/docs/certification/embedded-core-v1.json"}

fail() {
  echo "embedded-core-v1: FAIL: $*" >&2
  exit 1
}

exists() {
  case "$1" in
    */) [ -d "$ROOT/$1" ] ;;
    *) [ -f "$ROOT/$1" ] ;;
  esac
}

in_root() {
  case "$1" in
    "$ROOT"/*) return 0 ;;
    *) return 1 ;;
  esac
}

[ -f "$PROFILE" ] || fail "missing profile: $PROFILE"
in_root "$PROFILE" || fail "profile must be inside repository root: $PROFILE"
command -v jq >/dev/null 2>&1 || fail "jq is required to read the profile"
command -v bb >/dev/null 2>&1 || fail "Babashka (bb) is required for boundary verification"
command -v gleam >/dev/null 2>&1 || fail "gleam is required for certification"

jq -e '
  .profile == "embedded-core-v1" and
  (.status == "structural-certification-target") and
  (.scope | type == "string" and length > 0) and
  (.excluded_surfaces | type == "array" and length > 0) and
  (.excluded_surfaces | index("distributed and cluster runtime")) and
  (.excluded_surfaces | index("MCP")) and
  (.pure_modules | type == "array" and length > 0) and
  (.required_tests | type == "array" and length > 0) and
  (.approved_runtime_adapters | type == "array" and length > 0) and
  (.forbidden_import_prefixes | type == "array" and length > 0) and
  (.default_api_policy | type == "string" and length > 0) and
  (.certification_rule | type == "string" and length > 0)
' "$PROFILE" >/dev/null || fail "profile is incomplete or malformed"

jq -r '.pure_modules[], .required_tests[], .approved_runtime_adapters[]' "$PROFILE" |
while IFS= read -r path; do
  case "$path" in
    /*|*".."*|"" ) fail "profile contains unsafe repository-relative path: $path" ;;
    build/*|artifacts/*|Mnesia.*|*/Mnesia.*) fail "profile may not certify generated or runtime artifact paths: $path" ;;
  esac
  exists "$path" || fail "profile references missing path: $path"
done

if jq -e '.scope | test("distributed|cluster|raft|high availability|MCP"; "i")' "$PROFILE" >/dev/null; then
  fail "profile scope must not claim excluded distributed, HA, or MCP readiness"
fi

AARONDB_BOUNDARY_ROOT="$ROOT" bb "$ROOT/scripts/check_module_boundaries.clj"
sh "$ROOT/scripts/test_module_boundaries.sh"
sh "$ROOT/scripts/test_embedded_core_profile.sh"

if git -C "$ROOT" ls-files --error-unmatch -- build artifacts >/dev/null 2>&1; then
  fail "generated build or artifacts paths are tracked"
fi
if git -C "$ROOT" ls-files | grep -Eq '(^Mnesia\.|/Mnesia\.|\.beam$|erl_crash\.dump$)'; then
  fail "runtime artifact is tracked"
fi

gleam format --check src test bench
gleam check
gleam docs build
gleam test
git -C "$ROOT" diff --check

echo "EMBEDDED_CORE_V1_OK profile=$PROFILE"
