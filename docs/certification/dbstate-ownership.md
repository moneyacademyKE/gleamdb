# DbState Ownership Boundary

## Purpose

`aarondb/shared/state.DbState` remains a public compatibility record. Replacing
it atomically would force a repository-wide breaking API migration and would be
incidental complexity rather than a safe domain extraction.

`aarondb/shared/ownership` is the authoritative ownership projection. It maps a
`DbState` into five explicit values:

| Component | Owns | Domain status |
|---|---|---|
| `Facts` | primary indexes, latest transaction, schema | deterministic domain data |
| `Indexes` | vector, BM25, ART, and columnar derived indexes | deterministic derived data |
| `Runtime` | storage adapter, subjects, PIDs, ETS identity | adapter-only handles |
| `Extensions` | functions, predicates, rules, custom indexes | optional subsystem data |
| `Operations` | configuration and query history | operational policy/observability |

## Migration rule

- New pure code accepts `Facts`, `Indexes`, or other narrow ownership values;
  it does not receive `Runtime`.
- Runtime actors may retain `DbState` while interpreting storage, process, and
  notification effects.
- Existing public record construction remains compatible until a separately
  approved breaking-release migration can remove it.
- The projection is total: every `DbState` field belongs to exactly one owner.

## Evidence

`test/aarondb/transactor_modules_test.gleam` characterizes the empty projection,
optional-extension absence, deterministic transaction advancement, and EAVT,
AEVT, AVET index coherence.
