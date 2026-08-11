# Rich Hickey Certification Evidence — `embedded-core-v1`

**Date:** 2026-08-11
**Repository:** AaronDB (`~/Desktop/gleamdb`)
**Profile:** `embedded-core-v1`
**Verdict:** **10/10 for the named local structural profile. This is not a
whole-repository or universal distributed-systems certification.**

## Certified closure

The profile certifies the data-oriented embedded core and selected deterministic
optional algorithms. It excludes actor runtime, process subjects, storage, FFI,
transport, cluster runtime, MCP, and compatibility wrappers from the pure
closure. The machine-readable declaration is
`docs/certification/embedded-core-v1.json`; import direction is enforced by
`docs/certification/module-boundaries.edn`.

| Boundary | Certified property | Evidence |
|---|---|---|
| Facts and query data | Explicit datoms, ASTs, commands, and state transitions | Profile module allowlist and unit tests |
| Transaction domain | Ordered transaction data → `Outcome | Error`; persistence/notification remain runtime effects | `src/aarondb/transactor/domain.gleam`; `transactor_modules_test.gleam` |
| State ownership | Total projection of public `DbState` into facts, derived indexes, runtime handles, optional extensions, and operations | `shared/ownership.gleam`; [ownership boundary](../certification/dbstate-ownership.md) |
| Vector indexing | Validation and deterministic exact oracle are separated from approximate HNSW façade | `vec_index/validation.gleam`, `vec_index/exact.gleam`, tests |
| Sharding | Routing/reduction/retry/deadline policy is pure data; scatter/gather remains runtime code | `sharding/semantics.gleam`, `sharding_semantics_test.gleam` |
| Failure semantics | Explicit deadline-aware compatibility replacement APIs plus bounded retry/fallback/checkpoint model | `continuation.gleam`, `continuation_test.gleam`, `ergonomics_test.gleam` |

## Final verification

Executed from the current working tree on 2026-08-11, with
`/opt/homebrew/bin` prepended to `PATH` so the installed Gleam, Erlang, and
Babashka binaries are available.

| Gate | Command | Result |
|---|---|---|
| Formatting | `gleam format --check src test bench` | PASS |
| Type checking | `gleam check` | PASS |
| Documentation | `gleam docs build` | PASS |
| Full test suite | `gleam test` | PASS — **319 passed, 0 failures** |
| Boundary fixtures | `sh scripts/test_module_boundaries.sh` | PASS |
| Profile verification | `sh scripts/verify_embedded_core_v1.sh` | PASS — `EMBEDDED_CORE_V1_OK` |
| Diff hygiene | `git diff --check` | PASS |

## Deliberate trade-offs

`DbState` stays as a public compatibility record in this release. Replacing it
atomically would be a broad breaking change across production users and tests.
The new `ownership.view/1` is total and makes the five ownership domains
explicit now; new pure code should accept the narrow component it needs. A
future breaking release may remove flat construction after migration evidence
exists.

The profile intentionally does not certify distributed maturity. Sharding is
still local scatter/gather; cluster and broader stability claims remain
separately evidence-bound. See
[Broader Stability Review](broader-stability-review-2026-08-10.md) for the
current independent-host, WAN, soak, and upgrade/rollback NO-GO conditions.

## Certification statement

AaronDB earns **10/10 Rich Hickey structural certification under
`embedded-core-v1`**: the named closure is explicit data, pure models do not
import adapters, effects are interpreted at runtime boundaries, compatibility
is fenced, deterministic algorithmic oracles are retained, and the complete
profile gate passes.

It would be dishonest to apply that score to every experimental or distributed
surface in the repository. Those surfaces keep their own maturity labels and
must meet their own evidence profiles.

> **Rich Hickey check:** the improvement is not a fashionable rewrite. The
> system now names its data ownership, makes effect boundaries executable, and
> refuses to let local evidence impersonate a distributed claim.
