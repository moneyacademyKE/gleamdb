# Local MCP Stdio Adapter

AaronDB can run as a **local**, newline-delimited JSON-RPC MCP process. This is an adapter around the in-memory database and the three implemented tools: `muninn_remember`, `muninn_recall`, and `muninn_read`.

## Boundary

The adapter is for an MCP host that launches AaronDB as a child process on the same machine. It is not an HTTP/SSE/TCP server. Capability payloads are local authorization data, not signed credentials; do not expose this process to untrusted callers. The complete boundary is defined in [ADR 0002](../adr/0002-embedded-local-mcp-boundary.md).

## Run

```sh
gleam run -m aarondb/mcp/stdio
```

Send one JSON-RPC request per line on stdin. Responses are written one-per-line to stdout. Startup diagnostics are written to stderr, keeping stdout safe for an MCP host to parse.

Example initialization request:

```json
{"jsonrpc":"2.0","id":"init-1","method":"initialize","params":{}}
```

Then call `tools/list` to discover the supported tool schemas. The process exits cleanly at stdin EOF. Malformed JSON receives a JSON-RPC `-32700` parse error; unsupported methods receive `-32601`.

## Protocol support

- `initialize`
- `notifications/initialized`
- `tools/list`
- `tools/call` for `muninn_remember`, `muninn_recall`, and `muninn_read`

There are no network listeners, background transport tasks, or remote authentication semantics.
