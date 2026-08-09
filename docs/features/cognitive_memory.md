# Cognitive Memory & Semantic Retrieval

> **Maturity: Stable (local explicit-fact solver).** AaronDB provides one local `Cognitive` Datalog clause over explicitly stored engram facts. It does **not** implement adaptive ACT-R decay, Hebbian learning, Bayesian updates, embeddings, or external retrieval. See `docs/feature_maturity.md` and [ADR 0002](../adr/0002-embedded-local-mcp-boundary.md).

AaronDB combines ordinary Datalog structure with semantic lookup over engram facts. The authoritative implementation is `src/aarondb/engine/cognitive.gleam`.

## Data model and relevance

A cognitive query matches entities that have both active:

- an `engram/concept` fact, and
- an `engram/context` fact.

Each supplied concept/context part is matched as an ordinary Datalog value. An unbound variable enumerates all active values. The solver intersects the matching entity sets.

`engram/relevance` is optional and is scoped to the same active temporal basis as the concept and context facts:

- no active relevance fact → relevance **1.0**;
- one or more active `Int`/`Float` relevance facts → the **maximum** numeric value;
- active relevance facts with no numeric value → relevance **0.0**.

The caller-supplied threshold is inclusive: an entity matches when `relevance >= threshold`. Relevance changes only when callers transact or retract ordinary facts; queries do not mutate scores, learn, decay, or rank results.

## Querying via Datalog

Use `q.cognitive` or `ast.Cognitive` to bind matching engram entities alongside ordinary relational clauses. The clause observes ordinary transaction-time and valid-time bases, so historical queries use relevance facts visible at that basis.

## Local boundary and non-goals

The solver runs against the local database state. It does not promise result ranking, embedding similarity, remote retrieval, adaptive learning, score decay, persistence beyond the selected storage adapter, or cross-node consistency.

The former unwired MuninnDB-derived `Engram` types and adaptive scoring math were removed so this is the only cognitive model in the repository. If adaptive learning is required later, introduce it as a new explicit engine feature with persistence semantics, ranking rules, and deterministic tests—do not reintroduce a parallel orphaned model.
