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

## Lifecycle and flow control

The adapter is deliberately **single-request and synchronous**. It reads one complete newline-delimited request, handles it, writes at most one response, and only then reads the next request. There is no hidden request queue, concurrent tool execution, partial-result mode, or background transport worker.

This gives local hosts a simple backpressure contract: a slow tool call blocks further stdin reads until it completes. A host that needs a hard deadline or cancellation must terminate the child process; `notifications/cancelled` is accepted as a no-response notification, but cannot interrupt a tool call that is already running. EOF is the supported graceful shutdown mechanism.

JSON-RPC requests with an `id` receive one response. Notifications omit `id` and receive no stdout response, including `notifications/initialized` and `notifications/cancelled`. This preserves stdout as a protocol-only stream.

## Protocol support

- `initialize`
- `notifications/initialized`
- `notifications/cancelled` (acknowledged by suppression; no in-flight interruption)
- `tools/list`
- `tools/call` for `muninn_remember`, `muninn_recall`, and `muninn_read`

There are no network listeners, background transport tasks, remote authentication semantics, or unsigned-credential security claims.
