#!/bin/sh
# Exercise the local MCP adapter through real stdin/stdout/stderr file handles.
# Requires: Gleam, Erlang, and jq. Intended for local use and GitHub Actions.
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo_root"

input=$(mktemp)
stdout=$(mktemp)
stderr=$(mktemp)
cleanup() {
  rm -f "$input" "$stdout" "$stderr"
}
trap cleanup EXIT HUP INT TERM

cat >"$input" <<'EOF'
{"jsonrpc":"2.0","id":"init","method":"initialize","params":{}}
{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}
{"jsonrpc":"2.0","id":"tools","method":"tools/list","params":{}}
{
{"jsonrpc":"2.0","id":"unknown","method":"unsupported","params":{}}
EOF

gleam run -m aarondb/mcp/stdio <"$input" >"$stdout" 2>"$stderr"

# The initialized notification produces no response; EOF ends the child cleanly.
test "$(wc -l <"$stdout" | tr -d ' ')" = "4"
grep -q 'AaronDB local MCP stdio server started' "$stderr"

# Every stdout line must be a JSON-RPC response; compiler/runtime diagnostics stay
# on stderr and cannot contaminate a host's protocol stream.
jq -e '
  .jsonrpc == "2.0" and
  ((.result != null and .error == null) or (.result == null and .error != null))
' <"$stdout" >/dev/null

sed -n '1p' "$stdout" | jq -e '
  .id == "init" and
  .result.protocolVersion == "2024-11-05" and
  .result.capabilities.tools == {} and
  .error == null
' >/dev/null

sed -n '2p' "$stdout" | jq -e '
  .id == "tools" and
  (.result.tools | type == "array") and
  ([.result.tools[].name] | sort == ["muninn_read", "muninn_recall", "muninn_remember"]) and
  .error == null
' >/dev/null

sed -n '3p' "$stdout" | jq -e '
  .id == null and .result == null and .error.code == -32700
' >/dev/null

sed -n '4p' "$stdout" | jq -e '
  .id == "unknown" and .result == null and .error.code == -32601
' >/dev/null

printf '%s\n' 'MCP stdio child-process conformance passed.'
