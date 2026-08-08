# Project Boundaries

AaronDB currently contains several ideas in one repository. This document defines the intended boundaries so future work can reduce complection instead of increasing it. The authoritative supported deployment mode, threat model, persistence guarantees, and non-goals live in [ADR 0002](adr/0002-embedded-local-mcp-boundary.md).

## Recommended Repository Shape

| Area | Purpose | Boundary |
| --- | --- | --- |
| Core engine | Facts, transactions, indexes, query execution | Default identity of the project; embedded and trusted in-process |
| Distributed layer | Sharding, routing, distributed query coordination | Optional local extension; no HA, migration, or remote-cluster contract |
| Search layer | Vector, standalone BM25, ART | Optional local indexes with explicit contracts; hybrid retrieval and automatic DB integration are not supported |
| Agent layer | MCP, RAG, capability-gated tools | Local process integration surface; stdio adapter is the next supported transport |
| Auth layer | Capability checks | Local authorization model, not network authentication or signed identity |
| Persistence | In-memory state plus Mnesia adapter | Recovery-oriented adapter, not a production multi-node guarantee |
| CMS layer | Removed in v3.0.0 | No HTTP/CMS product surface remains in this repository |

## What Belongs In Core

- Datoms and value encoding
- Transaction processing
- In-memory indexes
- Query AST and DSL
- Pull, history, diff, and temporal APIs
- Schema constraints

## What Should Be Treated As Extensions

- Sharded fabric and distributed query helpers
- Leader election and HA protocols
- Vector, standalone BM25, and ART search adapters
- MCP and cognitive memory workflows

## Near-Term Rules For Changes

1. Keep new DB behavior in the core only when it improves facts, queries, transactions, or constraints.
2. Add new product or agent behavior under extension-oriented modules, not directly into the core API.
3. Follow [ADR 0002](adr/0002-embedded-local-mcp-boundary.md) before adding a transport, security claim, persistence guarantee, or distributed behavior.
4. Do not claim network-facing MCP, signed authentication, distributed HA, automatic migration, or production multi-node Mnesia support until the corresponding contract and verification exist.
5. Avoid examples in the README that depend on functions not exported by the current package.

## Why This Boundary Helps

- It keeps the strongest part of the system legible.
- It reduces pressure on `DbState` to become a product omnibus.
- It lets optional layers evolve without redefining the database contract.
- It prevents a local integration feature from accidentally becoming an implied production-service promise.
