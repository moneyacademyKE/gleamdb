#!/bin/sh
# Fail-closed release metadata contract. gleam.toml is the version authority.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

fail() {
  echo "release-metadata: FAIL: $*" >&2
  exit 1
}

version=$(sed -nE 's/^version[[:space:]]*=[[:space:]]*"([^"]+)"[[:space:]]*$/\1/p' gleam.toml)
[ -n "$version" ] || fail "could not read package version from gleam.toml"
[ "$(printf '%s\n' "$version" | wc -l | tr -d ' ')" = 1 ] || fail "gleam.toml has more than one package version"

major_minor=$(printf '%s' "$version" | sed -nE 's/^([0-9]+\.[0-9]+)\.[0-9]+$/\1/p')
[ -n "$major_minor" ] || fail "package version is not semantic: $version"

first_changelog=$(sed -nE 's/^## ([0-9]+\.[0-9]+\.[0-9]+) - .*/\1/p' CHANGELOG.md | sed -n '1p')
[ "$first_changelog" = "$version" ] || fail "CHANGELOG top version $first_changelog does not match gleam.toml $version"

grep -Fq "Current release line:** v$version" README.md ||
  fail "README current release line does not name v$version"
grep -Fq "aarondb = \"$major_minor\"" README.md ||
  fail "README installation requirement does not use $major_minor"
grep -Fq "## What $version Changes" README.md ||
  fail "README release summary does not name $version"

grep -Fq 'sh scripts/verify_release_metadata.sh' .github/workflows/release.yml ||
  fail "release workflow does not run this metadata verifier"
grep -Fq 'tags:' .github/workflows/release.yml ||
  fail "release workflow has no tag trigger"

case "${GITHUB_REF:-}" in
  refs/tags/*)
    tag=${GITHUB_REF#refs/tags/v}
    [ "$tag" = "$version" ] || fail "tag v$tag does not match gleam.toml version $version"
    echo "RELEASE_METADATA_OK version=$version tag=v$tag"
    ;;
  *)
    echo "RELEASE_METADATA_OK version=$version tag=not-applicable"
    ;;
esac
