#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CHECKER="$ROOT/scripts/check_module_boundaries.clj"
FIXTURE=$(mktemp -d "${TMPDIR:-/tmp}/aarondb-boundaries.XXXXXX")
trap 'rm -rf "$FIXTURE"' EXIT

mkdir -p "$FIXTURE/docs/certification" "$FIXTURE/src/core" "$FIXTURE/src/runtime"
cp "$ROOT/docs/certification/module-boundaries.edn" "$FIXTURE/docs/certification/"
printf '%s\n' 'import gleam/list' > "$FIXTURE/src/core/approved.gleam"
printf '%s\n' 'import gleam/otp/actor' > "$FIXTURE/src/core/forbidden.gleam"
printf '%s\n' 'import fixture/unknown' > "$FIXTURE/src/core/unapproved.gleam"
printf '%s\n' 'import gleam/otp/actor' > "$FIXTURE/src/runtime/adapter.gleam"

rewrite_manifest() {
  root="$1" module="$2" bb -e '
(require (quote [babashka.fs :as fs]) (quote [clojure.edn :as edn]))
(let [p (fs/path (System/getenv "root") "docs/certification/module-boundaries.edn")
      m (edn/read-string (slurp (str p)))]
  (spit (str p) (pr-str (assoc-in m [:layers :pure] [(System/getenv "module")]))))
'
}

rewrite_manifest "$FIXTURE" "src/core/approved.gleam"
AARONDB_BOUNDARY_ROOT="$FIXTURE" bb "$CHECKER" | grep -q 'EMBEDDED_CORE_BOUNDARIES_OK pure_modules=1'

rewrite_manifest "$FIXTURE" "src/core/forbidden.gleam"
if AARONDB_BOUNDARY_ROOT="$FIXTURE" bb "$CHECKER" >"$FIXTURE/forbidden.log" 2>&1; then
  echo 'boundary checker accepted a forbidden pure-to-runtime import' >&2
  exit 1
fi
grep -q "src/core/forbidden.gleam imports forbidden runtime boundary 'gleam/otp/actor'" "$FIXTURE/forbidden.log"

rewrite_manifest "$FIXTURE" "src/core/unapproved.gleam"
if AARONDB_BOUNDARY_ROOT="$FIXTURE" bb "$CHECKER" >"$FIXTURE/unapproved.log" 2>&1; then
  echo 'boundary checker accepted an unapproved pure-module import' >&2
  exit 1
fi
grep -q "src/core/unapproved.gleam imports unapproved module 'fixture/unknown'" "$FIXTURE/unapproved.log"

echo 'EMBEDDED_CORE_BOUNDARY_REGRESSION_OK'
