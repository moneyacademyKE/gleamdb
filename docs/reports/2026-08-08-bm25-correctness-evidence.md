# BM25 Correctness Evidence — 2026-08-08

AaronDB's local BM25 primitive has a committed golden corpus covering deterministic ranking, replacement, removal, empty documents, ASCII token boundaries, and the explicitly ASCII-only Unicode boundary. Incremental add/replace/remove state is compared against a clean `build` reconstruction and produces equal document statistics and ordered search results.

Verification command: `gleam test --target erlang`.

This evidence proves local caller-owned lifecycle consistency. It does not claim transaction integration, persistence, configurable analyzers, concurrency, or latency throughput. Those remain outside the Beta contract.
