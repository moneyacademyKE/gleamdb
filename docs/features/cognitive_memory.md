# Cognitive Memory & Semantic Retrieval

> **Maturity: Beta.** AaronDB provides a tested `Cognitive` Datalog clause over explicitly stored engram facts. It does **not** implement adaptive ACT-R decay, Hebbian learning, or Bayesian updates. See `docs/feature_maturity.md` and [ADR 0002](../adr/0002-embedded-local-mcp-boundary.md).

AaronDB combines ordinary Datalog structure with semantic lookup over engram facts. The authoritative implementation is `src/aarondb/engine/cognitive.gleam`.

## Data model

A cognitive query matches entities that have both:

- an `engram/concept` fact,
- an `engram/context` fact, and
- optionally an `engram/relevance` numeric fact.

The solver intersects active concept and context matches, then accepts entries meeting the caller's relevance threshold. Missing relevance defaults to `1.0`.

## Querying via Datalog

Use the `Cognitive` clause to bind matching engram entities alongside ordinary relational clauses. The exact builder and AST shapes are documented by the package API and tests.

## Non-goals

The former unwired MuninnDB-derived `Engram` types and adaptive scoring math were removed so this is the only cognitive model in the repository. If adaptive learning is required later, introduce it as a new explicit engine feature with persistence semantics, ranking rules, and deterministic tests—do not reintroduce a parallel orphaned model.
