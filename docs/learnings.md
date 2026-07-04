# Learnings from Achieving Test Coverage

This document outlines the philosophical learnings from achieving broader test coverage in the `aarondb` project, specifically applying the **Rich Hickey** methodology of simplicity and immutability.

## 1. Emphasize Data-Driven Structural Boundaries
When testing components like the `aarondb/q` query builder, it is critical not to test what the DSL does internally in ways that are brittle. **Simplicity** means checking that the pure transformation reliably produces the expected raw data (the AST clauses). A test should be a sequence of operations verified by pattern-matching the resulting list of AST structures.

## 2. Serialization is Value Reconstitution
For `aarondb/fact` and `aarondb/rule_serde`, serialization and persistence convey facts about the world. A Datom or a Rule isn't behavior; it's a value. Testing serialization (`encode_compact`, `decode_compact`) involved pure round-trip evaluation. We simply checked whether the value reconstituted on the other side retained its original identity.

## 3. Avoid Complecting the Environment
Testing the `aarondb/cache` module using the actor model required verifying eviction policies without standing up the overarching distributed transactional datastore. By injecting a dummy invalidation function and pumping pure data into the actor boundary, the caching logic was tested in isolation. We avoided complecting our local cache assertions with the rest of the database logic.

## 4. Keep the Core Legible
The repository now contains a stronger distinction between core and extension layers. The main learning is that a broad idea space is not the same thing as a cohesive architecture. The transactor, datom model, indexes, and query engine form the durable center. MCP, CMS, and distributed platform layers should be described and evolved as extensions so the core remains understandable.

## 5. Refactor by Green Slices
The engine refactor worked because each extraction preserved behavior and ran the full suite before proceeding. Entity helpers, traversal, predicates, graph clauses, retrieval, virtual predicates, and cognitive solving now have their own modules. The remaining `engine.gleam` should stay focused on orchestration, rule derivation, aggregate coordination, temporal coordination, and the core solver loop.

## 6. Separate Planning From Execution
The solver redesign introduced explicit planner and executor phases without rewriting clause semantics. `engine/planner.gleam` owns optimized query shape and top-level result shaping. `engine/executor.gleam` owns clause iteration and delegates solving through a callback. `engine/solver_context.gleam` makes the execution basis explicit, reducing argument sprawl while preserving the tested behavior of the existing solver.

These principles ensure that our test coverage does not become a tightly-coupled burden, but rather a flexible verification of independent state transformations.
