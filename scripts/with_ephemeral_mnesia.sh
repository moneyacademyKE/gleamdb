#!/bin/sh
# Run one command with a private, disposable Mnesia directory.
# Usage: sh scripts/with_ephemeral_mnesia.sh command [arg ...]
set -eu

[ "$#" -gt 0 ] || {
  echo "usage: $0 command [arg ...]" >&2
  exit 64
}

mnesia_dir=$(mktemp -d "${TMPDIR:-/tmp}/aarondb-mnesia.XXXXXX")
cleanup() {
  rm -rf "$mnesia_dir"
}
trap cleanup EXIT HUP INT TERM

ERL_FLAGS="-mnesia dir '\"$mnesia_dir\"'${ERL_FLAGS:+ $ERL_FLAGS}" "$@"
