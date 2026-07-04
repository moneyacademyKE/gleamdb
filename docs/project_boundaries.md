# Project Boundaries

AaronDB currently contains several ideas in one repository. This document defines the intended boundaries so future work can reduce complection instead of increasing it.

## Recommended Repository Shape

| Area | Purpose | Boundary |
| --- | --- | --- |
| Core engine | Facts, transactions, indexes, query execution | Should remain the default identity of the project |
| Distributed layer | Sharding, routing, distributed query coordination | Optional extension over the core |
| Search layer | Vector, BM25, ART, hybrid retrieval | Optional extension with explicit cost and storage trade-offs |
| Agent layer | MCP, RAG, capability-gated tools | Separate integration surface, not core DB identity |
| CMS layer | GleamCMS editor, router, themes, builder | Product built on top of AaronDB, not part of the essential engine |

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
- Vector and BM25 search adapters
- MCP and cognitive memory workflows
- CMS application code

## Near-Term Rules For Changes

1. Keep new DB behavior in the core only when it improves facts, queries, transactions, or constraints.
2. Add new product or agent behavior under extension-oriented modules, not directly into the core API.
3. Prefer documenting maturity and boundaries before expanding claims.
4. Avoid examples in the README that depend on functions not exported by the current package.

## Why This Boundary Helps

- It keeps the strongest part of the system legible.
- It reduces pressure on `DbState` to become a product omnibus.
- It lets the distributed, agent, and CMS layers evolve without redefining the database contract.
