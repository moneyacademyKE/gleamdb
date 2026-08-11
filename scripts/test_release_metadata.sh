#!/bin/sh
# Regression checks for the package/changelog/README/tag metadata contract.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VERIFY="$ROOT/scripts/verify_release_metadata.sh"
FIXTURE=$(mktemp -d "${TMPDIR:-/tmp}/aarondb-release-metadata.XXXXXX")
trap 'rm -rf "$FIXTURE"' EXIT

version=$(sed -nE 's/^version[[:space:]]*=[[:space:]]*"([^"]+)"[[:space:]]*$/\1/p' "$ROOT/gleam.toml")
[ -n "$version" ]

GITHUB_REF="refs/tags/v$version" sh "$VERIFY" | grep -q "RELEASE_METADATA_OK version=$version tag=v$version"

mkdir -p "$FIXTURE/scripts" "$FIXTURE/.github/workflows"
cp "$ROOT/gleam.toml" "$ROOT/CHANGELOG.md" "$ROOT/README.md" "$FIXTURE/"
cp "$ROOT/.github/workflows/release.yml" "$FIXTURE/.github/workflows/"
cp "$VERIFY" "$FIXTURE/scripts/"

if GITHUB_REF="refs/tags/v0.0.0" sh "$FIXTURE/scripts/verify_release_metadata.sh" >"$FIXTURE/tag.log" 2>&1; then
  echo 'release metadata verifier accepted a mismatched tag' >&2
  exit 1
fi
grep -q 'does not match gleam.toml version' "$FIXTURE/tag.log"

awk 'NR == 3 { print "## 0.0.0 - 1970-01-01"; next } { print }' "$FIXTURE/CHANGELOG.md" > "$FIXTURE/CHANGELOG.next"
mv "$FIXTURE/CHANGELOG.next" "$FIXTURE/CHANGELOG.md"
if sh "$FIXTURE/scripts/verify_release_metadata.sh" >"$FIXTURE/changelog.log" 2>&1; then
  echo 'release metadata verifier accepted a mismatched changelog' >&2
  exit 1
fi
grep -q 'CHANGELOG top version' "$FIXTURE/changelog.log"

echo 'RELEASE_METADATA_REGRESSION_OK'
