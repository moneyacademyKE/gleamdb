#!/bin/sh
# Regression fixtures for the embedded-core profile contract.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PROFILE="$ROOT/docs/certification/embedded-core-v1.json"
VERIFIER="$ROOT/scripts/verify_embedded_core_v1.sh"
FIXTURE=$(mktemp "$ROOT/docs/certification/.embedded-core-profile.XXXXXX.json")
trap 'rm -f "$FIXTURE"' EXIT

jq '.excluded_surfaces = []' "$PROFILE" > "$FIXTURE"
if AARONDB_CERTIFICATION_PROFILE="$FIXTURE" sh "$VERIFIER" >"$FIXTURE.metadata.log" 2>&1; then
  echo 'embedded-core verifier accepted a profile with missing excluded-surface metadata' >&2
  exit 1
fi
grep -q 'profile is incomplete or malformed' "$FIXTURE.metadata.log"

jq '.pure_modules += ["artifacts/generated.gleam"]' "$PROFILE" > "$FIXTURE"
if AARONDB_CERTIFICATION_PROFILE="$FIXTURE" sh "$VERIFIER" >"$FIXTURE.artifact.log" 2>&1; then
  echo 'embedded-core verifier accepted a generated artifact in the pure closure' >&2
  exit 1
fi
grep -q 'profile references missing path\|profile may not certify generated or runtime artifact paths' "$FIXTURE.artifact.log"

echo 'EMBEDDED_CORE_PROFILE_REGRESSION_OK'
