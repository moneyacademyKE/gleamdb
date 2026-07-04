# Cognitive Memory & Semantic Retrieval

> **Maturity: Experimental.** The cognitive clause is implemented and tested, but the full ACT-R decay and Hebbian learning lifecycle is still maturing. See `docs/feature_maturity.md`.

AaronDB provides a paradigm shift by merging deductive logic (Datalog) with
inductive, associative memory (Cognitive Models) naturally in the database
querying language.

This mechanism derives from the integration of the MuninnDB Go engine, now
completely native on the Erlang/BEAM VM via Gleam.

## The Philosophical Foundation

Traditional databases require you to know exactly *how* a relationship is encoded
(Foreign Keys, explicit JOIN paths). Human memory works via associative semantic
triggers: remembering "Apple" brings up "Red", "Fruit", and "Steve Jobs"
depending strictly on the context and frequency of the firing.

By combining Datalog (`exact structure`) with Cognitive Primitives (`associative
meaning`), AaronDB supports highly intelligent, context-aware queries.

## Cognitive Primitives

1. **ACT-R Base-Level Learning (Decay)**
   Facts encoded as `Engrams` do not exist forever unconditionally. Their
   "Activation Score" logarithmically decays over time unless they are actively
   strengthened or retrieved. This mimics human memory and acts as an automatic
   relevancy filter.

2. **Hebbian Association**
   "Nodes that fire together, wire together." When two distinct Engrams are
   queried simultaneously within the same temporal context, the synaptic weight
   (Hebbian Score) between them increases.

3. **Bayesian Confidence**
   A standard naive Bayes updater maintains probability confidence scores based
   on evidence collection.

## Querying via Datalog

We expose this to developers as a first-class Datalog predicate: `Cognitive()`.

### Example: Semantic Association

```gleam
import aarondb/q
import aarondb/shared/types.{Part}

let query = q.new()
  // Retrieve traditional user details
  |> q.where(q.v("u"), "user/name", q.s("Alice"))
  
  // Mix in Cognitive association:
  // Find concepts associated with the "context" node that pass the 0.75 threshold
  |> q.cognitive(
       concept: Part("AI_Agent"), 
       context: Part("Trading_Strategy"), 
       threshold: 0.75, 
       engram_var: "strategy_node"
     )
  
  // Use the resulting node back in relational logic
  |> q.where(q.v("u"), "user/active_strategy", q.v("strategy_node"))
  |> q.to_clauses()
```

### Automatic Execution

Under the hood, AaronDB's logical navigator `navigator.gleam` costs the
`Cognitive` predicate operation naturally alongside standard indices. It
retrieves the vector or semantic associations from ETS indices, evaluates the
mathematical decay algorithms concurrently, and yields bindings into the logical
unification flow.
