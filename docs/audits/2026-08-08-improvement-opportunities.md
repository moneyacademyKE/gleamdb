# AaronDB Improvement Opportunity Audit

**Date:** 2026-08-08  
**Scope:** `/Users/moe/Desktop/gleamdb`, branch `docs/adr-embedded-local-mcp-boundary`  
**Language/toolchain:** Gleam targeting Erlang/OTP; Erlang FFI modules  
**Historical baseline:** `gleam format --check src test bench`, `gleam build`, and `gleam test` passed (**174 tests, 0 failures**) when this audit was written.

> **Resolution status:** The P0/P1/P2 recommendations in this audit were implemented for v4.0.0. The project now has safe term decoding, truthful actor timeouts, vector-dimension enforcement, non-destructive Mnesia initialization, CI docs/workflow linting, Apache-2.0 licensing, a security policy, and explicit local-only sharding boundaries. The observations below are retained as the evidence trail for those changes.

## Executive summary

The core has good test density (67 test files / 73 source modules) and a small dependency surface (four direct runtime dependencies). The best next improvements are not more features: they are closing three correctness/security contracts that currently look stronger than they are.

| Priority | Opportunity | Evidence | Recommendation |
|---|---|---|---|
| P0 | Unsafe public Erlang term deserialization | `src/aarondb/rule_serde.gleam:16-22`; `src/aarondb/index/ets.gleam:81-89` | Do not feed externally supplied bytes to `erlang:binary_to_term/1`. Add a safe FFI using `binary_to_term(Binary, [safe])`, use it at all decode boundaries, and validate the resulting shape before treating it as a `Rule` or index term. |
| P1 | Timeout APIs that can still block/panic | `src/aarondb/transactor.gleam:83-88`, `184-200`, `217-273`; `src/aarondb.gleam:43-67` | Make `start_with_timeout` use its parameter; replace public-facing `let assert Ok(...) = process.receive(...)` calls with `Result`-returning timeout-aware variants. Then make convenience APIs opt into the documented default deliberately. |
| P1 | Dimension mismatches silently alter vector similarity | `src/aarondb/vector.gleam:5-10`, `22-29`; used by `src/aarondb/engine/retrieval.gleam:20-25`, `128-134` | Establish one vector contract: reject unequal dimensions with `Result`, or validate vector dimensionality at schema/index insertion. Add mismatch tests to the retrieval and HNSW paths. |
| P1 | Mnesia initialization can delete persisted data | `src/aarondb_mnesia_ffi.erl:11-20` | Never automatically delete and recreate `datoms` on schema mismatch. Return a structured migration/incompatibility error; require an explicit admin migration/reset operation. |
| P2 | Sharding still exposes unsafe/partial public operations | `src/aarondb/sharded.gleam:494-502`, `565-627`, `632-639` | Keep sharding Beta until rebalance preserves source/retraction invariants, `pull` stops relying on `unsafe_coerce`, and migration is either implemented transactionally or hidden from the supported public surface. |
| P2 | Release and PR CI have gaps | `.github/workflows/ci.yml`; `.github/workflows/release.yml` | Add `gleam docs build` and `actionlint` to pull-request CI. Add a non-publishing release-workflow test/dispatch policy and record the owner’s Hex-key rotation before the next tag publish. |
| P2 | Package provenance/documentation hygiene | root listing and `gleam.toml` | Add an Apache-2.0 `LICENSE` file matching `gleam.toml`, a security policy, and a short supported-runtime matrix (embedded/local stdio only; sharding/Raft/Mnesia boundaries). |

## Findings

### P0 — Unsafe term deserialization

`rule_serde.deserialize/1` is public and base64-decodes caller-provided input before passing it to `erlang:binary_to_term/1`. Its comment acknowledges that it trusts the input. The ETS module exports a similar raw decode helper. Erlang external term decoding should use the safe option at a trust boundary and must not rely on an unchecked polymorphic return value.

**Why it matters:** malformed or adversarial serialized data can crash the VM-facing path; unrestricted external terms are not an appropriate public wire/storage format. The current test only proves a trusted round trip (`test/aarondb/rule_serde_test.gleam:5-16`).

**Smallest useful change:** keep term serialization internal, add a safe Erlang FFI decoder, return `Result`, and add malformed/base64-valid/non-Rule regression tests. For a portable public format, prefer explicit Gleam JSON/binary encoding of `Rule` rather than Erlang term serialization.

### P1 — Timeout API contract is not implemented consistently

`transactor.start_with_timeout(store, _timeout_ms)` ignores the parameter. Several public wrappers use a fixed five-second receive behind `let assert Ok(...)`, which converts ordinary actor unavailability into a crash rather than a `Result`.

**Why it matters:** callers choosing a timeout cannot rely on it; a slow or dead actor turns a recoverable operational condition into process failure. This particularly undermines the otherwise useful `new_with_adapter_and_timeout` API.

**Smallest useful change:** make start boot acknowledgment use `timeout_ms`; add `get_state_with_timeout`, `retract_with_timeout`, and Result-returning registration/configuration functions; retain existing convenience APIs only if their panic-on-timeout behavior is explicitly documented as legacy.

### P1 — Vector dimension mismatch has conflicting semantics

`aarondb/math.cosine_similarity` correctly returns an error for mismatched vectors, but `aarondb/vector.dot_product` truncates to the shorter list and `aarondb/vector.cosine_similarity` returns a `Float`. The retrieval subsystem uses the latter for similarity clauses.

**Why it matters:** a malformed embedding can produce a plausible similarity score instead of being rejected. That gives false matches and makes HNSW/retrieval results dependent on accidental list length.

**Smallest useful change:** make vector similarity return `Result(Float, VectorError)` for dimension mismatch and zero magnitude, or reject inconsistent dimensions when a vector attribute/index is created. Add retrieval-level regression tests, not only pure-math tests.

### P1 — Mnesia schema mismatch is destructive

The FFI checks table attributes and calls `mnesia:delete_table(datoms)` on any mismatch, then recreates it. Initialization proceeds even when schema creation/startup errors are ignored.

**Why it matters:** changing a schema or encountering an unexpected table shape can silently erase durable user data during startup. This is much worse than a startup failure.

**Smallest useful change:** make `init` return a tagged `Result`; preserve the table; expose an explicit backup/migrate/reset administration path. Add an integration test proving an incompatible schema fails without data deletion.

### P2 — Sharding is deliberately bounded, but its public API still invites unsafe use

The current branch documents sharding as local/Beta, but `pull` applies `unsafe_coerce` to cross-process results. `rebalance` only writes routed facts and does not prove source retractions or atomicity. `migrate_shard_data` correctly returns an explicit error, but remains public.

**Recommendation:** either hide these APIs from the public supported surface until their invariants are implemented, or give every incomplete entry point a `*_unsupported` name/type that forces callers to handle the limitation. Do not add distributed features until migration atomicity, duplicate prevention, and error recovery are tested.

### P2 — CI and release assurance are narrower than the product surface

PR CI performs format and tests only. Documentation is built only in the release workflow. `actionlint` was available locally and accepted both workflow files, but it is not enforced in CI. The release workflow’s publish path must remain blocked until the owner rotates the exposed Hex key and replaces the GitHub secret.

**Recommendation:** add docs and workflow linting to PR CI; retain a `workflow_dispatch` non-publishing test; document the release checklist and key-rotation confirmation without recording the replacement secret.

### P2 — Packaging and security policy are missing

`gleam.toml` declares Apache-2.0, but the repository root has no `LICENSE` file. There is no `SECURITY.md`, contributor policy, or explicit vulnerability-reporting channel.

**Recommendation:** add `LICENSE`, `SECURITY.md`, and a concise support matrix. This is low code effort and materially improves package trust and downstream adoption.

## Healthy patterns

- **Verification is real:** format, build, and all 174 tests pass on the audited branch.
- **Test density is strong:** 67 test modules for 73 source modules; the test suite covers core query, transaction, index, vector, MCP, and sharding surfaces.
- **Dependency surface is small:** `gleam_stdlib`, `gleam_erlang`, `gleam_otp`, and `gleam_json` at runtime; `gleeunit` for development.
- **CI exists and runs on pull requests and main branches.**
- **Release workflow is structurally sound:** it verifies tag/version parity, creates a GitHub release, and has a non-publishing manual route. Local `actionlint` completed without findings.
- **Git discipline is healthy:** 24 of 26 commit subjects in the previous three months use Conventional Commit prefixes.
- **Generated build and Mnesia runtime artifacts are ignored, not tracked.**

## Maintenability opportunities

The largest production modules are `algo/graph.gleam` (775 LOC), `sharded.gleam` (740), root `aarondb.gleam` (548), `transactor.gleam` (501), and `vec_index.gleam` (482). The first split target should be `sharded.gleam`: it currently combines cluster boot, routing, scatter/gather, aggregation, pull, vector search, lifecycle, rebalance, and migration planning. Split only along these already-existing cohesive boundaries; do not create tiny-file confetti.

## What was examined

- Current branch and its delta from `master`
- All source/test file inventories and test-to-source ratio
- Native Gleam format/build/test run
- CI/release workflow source and local workflow lint
- FFI boundaries, public timeout APIs, serialization, vector retrieval, Mnesia adapter, and sharding boundaries
- Git hygiene/churn and ignored artifact checks

## What was not examined

- No live multi-node Mnesia, partition, or failure-injection run
- No fuzz/property test campaign
- No dependency CVE scanner was run because a Gleam/Hex vulnerability scanner was not available in this environment
- `gitleaks` was not installed, so no dedicated secret scan was run
- No code changes were made by this audit
