import aarondb/continuation
import gleam/option.{Some}
import gleeunit/should

fn policy() {
  continuation.RetryPolicy(
    max_retries_per_provider: 2,
    base_backoff_ms: 100,
    providers: ["primary", "fallback"],
  )
}

fn work() {
  continuation.Work("certification-plan", "task-8", "effect:task-8")
}

pub fn transient_failures_wait_with_bounded_backoff_test() {
  let first =
    continuation.new(work(), policy())
    |> continuation.fail(
      "request-1",
      continuation.ProviderOverloaded,
      "overloaded",
      1000,
    )

  first.status |> should.equal(continuation.Waiting(1100))
  first.retry_count |> should.equal(1)

  let second =
    first
    |> continuation.fail(
      "request-2",
      continuation.Transient,
      "temporary transport error",
      1200,
    )

  second.status |> should.equal(continuation.Waiting(1400))
  second.retry_count |> should.equal(2)
}

pub fn exhausted_primary_selects_the_next_configured_provider_test() {
  let waiting =
    continuation.new(work(), policy())
    |> continuation.fail(
      "request-1",
      continuation.ProviderOverloaded,
      "overloaded",
      1000,
    )
    |> continuation.fail(
      "request-2",
      continuation.ProviderOverloaded,
      "overloaded",
      1200,
    )

  let switched =
    waiting
    |> continuation.fail(
      "request-3",
      continuation.ProviderOverloaded,
      "overloaded",
      1400,
    )

  switched.status
  |> should.equal(continuation.SwitchedToFallback("fallback"))
  continuation.current_provider(switched) |> should.equal(Some("fallback"))
  switched.retry_count |> should.equal(0)
}

pub fn exhaustion_creates_complete_issue_payload_test() {
  let exhausted =
    continuation.new(work(), policy())
    |> exhaust_provider("primary", 1000)
    |> exhaust_provider("fallback", 2000)

  let assert continuation.Escalated(payload) = exhausted.status
  payload.plan_id |> should.equal("certification-plan")
  payload.task_id |> should.equal("task-8")
  payload.effect_key |> should.equal("effect:task-8")
  payload.request_id |> should.equal("fallback-3")
  payload.first_failed_at_ms |> should.equal(1000)
  payload.last_failed_at_ms |> should.equal(2400)
  payload.failure_class |> should.equal(continuation.ProviderOverloaded)
  payload.retry_count |> should.equal(2)
  payload.fallback_outcome |> should.equal(continuation.FallbackExhausted)
  payload.message |> should.equal("fallback overloaded")
}

pub fn checkpoint_resume_preserves_waiting_work_without_duplicate_effects_test() {
  let waiting =
    continuation.new(work(), policy())
    |> continuation.fail(
      "request-1",
      continuation.Transient,
      "temporary transport error",
      1000,
    )
    |> continuation.checkpoint()
    |> continuation.resume()

  waiting.status |> should.equal(continuation.Waiting(1100))
  continuation.permit_effect(waiting)
  |> should.equal(continuation.EffectAuthorized)

  let completed = waiting |> continuation.record_effect()
  continuation.permit_effect(completed)
  |> should.equal(continuation.EffectAlreadyCompleted)

  let resumed = completed |> continuation.checkpoint() |> continuation.resume()
  resumed.status |> should.equal(continuation.Completed)
  continuation.permit_effect(resumed)
  |> should.equal(continuation.EffectAlreadyCompleted)
  continuation.record_effect(resumed) |> should.equal(resumed)
}

pub fn permanent_failure_escalates_without_retrying_test() {
  let failed =
    continuation.new(work(), policy())
    |> continuation.fail(
      "request-permanent",
      continuation.Permanent,
      "invalid request",
      7,
    )

  let assert continuation.Escalated(payload) = failed.status
  payload.retry_count |> should.equal(0)
  payload.fallback_outcome |> should.equal(continuation.NoFallbackAvailable)
  failed.evidence
  |> should.equal(
    Some(continuation.Evidence(
      "request-permanent",
      continuation.Permanent,
      7,
      7,
      "invalid request",
    )),
  )
}

fn exhaust_provider(state, provider, started_at_ms) {
  state
  |> continuation.fail(
    provider <> "-1",
    continuation.ProviderOverloaded,
    provider <> " overloaded",
    started_at_ms,
  )
  |> continuation.fail(
    provider <> "-2",
    continuation.ProviderOverloaded,
    provider <> " overloaded",
    started_at_ms + 200,
  )
  |> continuation.fail(
    provider <> "-3",
    continuation.ProviderOverloaded,
    provider <> " overloaded",
    started_at_ms + 400,
  )
}
