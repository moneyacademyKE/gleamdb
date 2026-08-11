# Transient Failure Continuation Policy

`aarondb/continuation` models resumable work as data. It is intentionally not a
scheduler, provider client, or issue reporter: an adapter persists checkpoints
and performs the requested effects.

## State model

A `Continuation` contains:

| Field | Purpose |
|---|---|
| `Work` | approved plan/task identity plus idempotency `effect_key` |
| `RetryPolicy` | ordered providers, retry limit, and base backoff |
| provider/retry counters | deterministic current execution position |
| `Evidence` | request ID, failure class, timestamps, and message |
| completed effect keys | duplicate-effect prevention across resume |
| `Status` | ready, waiting, fallback selected, escalated, or completed |

## Decision rules

1. Persist `checkpoint/1` after every policy decision and reload with `resume/1`.
2. A permanent failure escalates immediately; it never retries.
3. A transient or overload failure retries up to the configured bound using
   deterministic linear backoff: `base_backoff_ms * retry_count`.
4. After retries are exhausted, select the next configured provider exactly
   once; when none remains, produce an `IssuePayload`.
5. Ask `permit_effect/1` before an external effect and call `record_effect/1`
   before acknowledging it. Repeating the record is idempotent.

## Escalation payload

`IssuePayload` carries the plan and task IDs, effect key, request ID, first and
last failure timestamps, failure class, retry count, fallback result, and the
failure message. It is deliberately a local value. Creating a GitHub issue is
an external side effect that requires repository/account governance and direct
user approval.

## Evidence

`test/aarondb/continuation_test.gleam` covers bounded backoff, deterministic
fallback, exhaustion payload construction, checkpoint/resume, duplicate-effect
prevention, and permanent failures. The final profile verification is recorded
in [Rich Hickey certification evidence](../reviews/rich-hickey-certification-evidence-2026-08-11.md).
