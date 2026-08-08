# ADR 0002: Embedded Core and Local MCP Boundary

## Status

Accepted

## Context

AaronDB has a mature in-process temporal Datalog core, alongside extension layers with very different operational properties. The repository contains a capability model, a typed MCP request actor, local sharding helpers, a Mnesia adapter, and an election-only Raft state machine. Those components must not collectively imply that AaronDB is a secure network database, a distributed HA database, or a production MCP daemon.

The current `auth` module decodes capability-shaped JSON but does not verify a signature, issuer, expiry, or audience. The current MCP server dispatches JSON-RPC requests in process; it has no stdio transport or network listener. Sharding is local scatter/gather execution with explicit migration gaps. Raft is deliberately unwired and has no replicated log. Mnesia has recovery coverage but no production multi-node validation.

## Decision

AaronDB's supported deployment mode is an **embedded Gleam/Erlang library** with an optional **local stdio MCP adapter**.

The core database and its caller share a trusted process boundary. The stdio adapter is for a local MCP host that launches AaronDB as its child process. It must use newline-delimited JSON-RPC on stdin/stdout, reserve stdout for protocol messages, and send diagnostics to stderr.

Capability tokens remain an in-process authorization model. They are not authentication credentials and must not be represented as protection for a network boundary until a separately designed, signed and expiring token format exists.

## Threat Model and Persistence Guarantees

- The supported core assumes trusted application code and a trusted local host process.
- A local MCP host is responsible for process launch, user identity, and filesystem/process isolation.
- No HTTP, SSE, TCP, or distributed-Erlang endpoint is supported or implied by this decision.
- In-memory state is process-local and is lost on process exit unless the application explicitly uses a persistence adapter.
- The Mnesia adapter supports the existing recovery path; it is not yet a recommended multi-node durability or HA contract.

## Explicit Non-Goals

- Network-facing MCP service or remote multi-tenant authorization.
- Cryptographic token verification, key distribution, issuer trust, expiry, revocation, or audience validation.
- Distributed transactions, automatic shard migration, exact global aggregates, membership management, or shard failover.
- Raft-backed replication, quorum commits, or high availability.
- A production claim for multi-node Mnesia deployment.

## Consequences

- The next MCP work is a small stdio transport over the existing `mcp/server` actor, with process-level tests.
- `auth` remains deliberately limited to local capability checks; network authentication is deferred rather than partially implemented.
- Cognitive modules must be either integrated into the active solver with defined semantics or removed as an orphaned parallel model.
- Sharding remains Beta until a product commitment funds transactional migration and exact distributed aggregate semantics.
- Raft remains an inactive, documented stub. Mnesia remains recovery-oriented until operational failure testing establishes a broader contract.

## References

- [Feature maturity](../feature_maturity.md)
- [Project boundaries](../project_boundaries.md)
- [Architecture](../architecture.md)
