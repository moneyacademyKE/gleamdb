# BM25 Search Contract

AaronDB's `aarondb/index/bm25` module is an in-memory BM25 index for a single string attribute. It is **Beta** and currently a standalone index primitive: it is not yet exposed through the database query DSL or maintained automatically by database transactions.

## Text analysis

- Text is lowercased.
- ASCII letters (`a-z`) and digits (`0-9`) form tokens.
- Every other grapheme is a token boundary.
- The index does not currently provide Unicode-aware tokenisation, stemming, stop-word removal, synonyms, or configurable analyzers.

## Document lifecycle

Documents are keyed by `EntityId`.

- `add(index, entity, text)` inserts or **replaces** that entity's document. Re-adding an entity does not double-count its document frequency or document length.
- `remove(index, entity, text)` is idempotent. The `text` argument is retained for compatibility but the index's own state is authoritative, so a stale historical value cannot corrupt the index.
- `build(datoms, attribute)` processes matching string datoms in input order; the last matching datom for an entity wins. Callers with history must supply their intended active snapshot.
- Only string datoms are indexed.

## Ranking

- `score(index, entity, query, k1, b)` uses the standard BM25 formula.
- `k1` must be non-negative; `b` must be in `[0.0, 1.0]`. Invalid values return `0.0` from this compatibility API.
- `search(index, query, k1, b, limit)` returns positive-score hits only, ordered by descending score and then ascending entity ID. This tie-break makes equal-score results deterministic.
- `limit` must be positive; invalid parameters or limits return `[]`.

## Scope limits

This contract does not claim:

- database-integrated text queries or transaction-driven BM25 maintenance;
- hybrid BM25/vector score combination semantics;
- persistent or distributed BM25 indexes;
- benchmarked ranking, update throughput, or latency guarantees.

Those are separate milestones. Until a transactor/query-engine integration exists, use this module deliberately as a caller-owned local index.
