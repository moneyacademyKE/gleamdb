//// # continuation — deterministic transient-failure policy
////
//// This is a pure model for resuming approved work after a provider or transport
//// interruption. An adapter persists `Checkpoint` and performs the chosen effect;
//// this module never retries, sleeps, switches providers, or files an issue itself.

import gleam/list
import gleam/option.{type Option, None, Some}

pub type FailureClass {
  Transient
  ProviderOverloaded
  Permanent
}

pub type RetryPolicy {
  RetryPolicy(
    max_retries_per_provider: Int,
    base_backoff_ms: Int,
    providers: List(String),
  )
}

pub type Work {
  Work(plan_id: String, task_id: String, effect_key: String)
}

pub type Evidence {
  Evidence(
    request_id: String,
    failure_class: FailureClass,
    first_failed_at_ms: Int,
    last_failed_at_ms: Int,
    message: String,
  )
}

pub type FallbackOutcome {
  NoFallbackAvailable
  FallbackSelected(provider: String)
  FallbackExhausted
}

pub type IssuePayload {
  IssuePayload(
    plan_id: String,
    task_id: String,
    effect_key: String,
    request_id: String,
    first_failed_at_ms: Int,
    last_failed_at_ms: Int,
    failure_class: FailureClass,
    retry_count: Int,
    fallback_outcome: FallbackOutcome,
    message: String,
  )
}

pub type Status {
  Ready
  Waiting(retry_at_ms: Int)
  SwitchedToFallback(provider: String)
  Escalated(payload: IssuePayload)
  Completed
}

pub type Continuation {
  Continuation(
    work: Work,
    policy: RetryPolicy,
    provider_index: Int,
    retry_count: Int,
    evidence: Option(Evidence),
    completed_effect_keys: List(String),
    status: Status,
  )
}

/// `Checkpoint` is the complete durable value an adapter must save after every
/// decision. Reloading it with `resume` is identity-preserving and cannot repeat
/// an already recorded effect.
pub type Checkpoint {
  Checkpoint(continuation: Continuation)
}

pub type EffectPermit {
  EffectAuthorized
  EffectAlreadyCompleted
}

pub fn new(work: Work, policy: RetryPolicy) -> Continuation {
  Continuation(work, policy, 0, 0, None, [], Ready)
}

pub fn checkpoint(continuation: Continuation) -> Checkpoint {
  Checkpoint(continuation)
}

pub fn resume(checkpoint: Checkpoint) -> Continuation {
  let Checkpoint(continuation) = checkpoint
  continuation
}

pub fn current_provider(continuation: Continuation) -> Option(String) {
  provider_at(continuation.policy.providers, continuation.provider_index)
}

/// The adapter asks permission before performing the named external effect.
pub fn permit_effect(continuation: Continuation) -> EffectPermit {
  case
    list.contains(
      continuation.completed_effect_keys,
      continuation.work.effect_key,
    )
  {
    True -> EffectAlreadyCompleted
    False -> EffectAuthorized
  }
}

/// Record completion before acknowledging an effect. Repeating this operation is
/// deliberately idempotent so an interrupted acknowledgement cannot duplicate it.
pub fn record_effect(continuation: Continuation) -> Continuation {
  case permit_effect(continuation) {
    EffectAlreadyCompleted -> continuation
    EffectAuthorized ->
      Continuation(
        ..continuation,
        completed_effect_keys: [
          continuation.work.effect_key,
          ..continuation.completed_effect_keys
        ],
        status: Completed,
      )
  }
}

/// Decide the next retry/fallback/escalation transition for a failure observed at
/// `now_ms`. A permanent failure never retries. Backoff is deterministic linear
/// data: `base_backoff_ms * next_retry_count`.
pub fn fail(
  continuation: Continuation,
  request_id: String,
  failure_class: FailureClass,
  message: String,
  now_ms: Int,
) -> Continuation {
  let evidence =
    next_evidence(
      continuation.evidence,
      request_id,
      failure_class,
      message,
      now_ms,
    )
  case continuation.status {
    Completed -> continuation
    Escalated(_) -> continuation
    _ ->
      decide(Continuation(..continuation, evidence: Some(evidence)), evidence)
  }
}

fn decide(continuation: Continuation, evidence: Evidence) -> Continuation {
  case evidence.failure_class {
    Permanent -> escalate(continuation, evidence, NoFallbackAvailable)
    _ ->
      case
        continuation.retry_count < continuation.policy.max_retries_per_provider
      {
        True -> wait_for_retry(continuation, evidence)
        False -> switch_or_escalate(continuation, evidence)
      }
  }
}

fn wait_for_retry(
  continuation: Continuation,
  evidence: Evidence,
) -> Continuation {
  let next_retry = continuation.retry_count + 1
  Continuation(
    ..continuation,
    retry_count: next_retry,
    status: Waiting(
      evidence.last_failed_at_ms
      + continuation.policy.base_backoff_ms
      * next_retry,
    ),
  )
}

fn switch_or_escalate(
  continuation: Continuation,
  evidence: Evidence,
) -> Continuation {
  let next_index = continuation.provider_index + 1
  case provider_at(continuation.policy.providers, next_index) {
    Some(provider) ->
      Continuation(
        ..continuation,
        provider_index: next_index,
        retry_count: 0,
        status: SwitchedToFallback(provider),
      )
    None -> escalate(continuation, evidence, FallbackExhausted)
  }
}

fn escalate(
  continuation: Continuation,
  evidence: Evidence,
  fallback_outcome: FallbackOutcome,
) -> Continuation {
  let Work(plan_id, task_id, effect_key) = continuation.work
  Continuation(
    ..continuation,
    status: Escalated(IssuePayload(
      plan_id,
      task_id,
      effect_key,
      evidence.request_id,
      evidence.first_failed_at_ms,
      evidence.last_failed_at_ms,
      evidence.failure_class,
      continuation.retry_count,
      fallback_outcome,
      evidence.message,
    )),
  )
}

fn next_evidence(
  previous: Option(Evidence),
  request_id: String,
  failure_class: FailureClass,
  message: String,
  now_ms: Int,
) -> Evidence {
  case previous {
    Some(Evidence(_, _, first_failed_at_ms, _, _)) ->
      Evidence(request_id, failure_class, first_failed_at_ms, now_ms, message)
    None -> Evidence(request_id, failure_class, now_ms, now_ms, message)
  }
}

fn provider_at(providers: List(String), index: Int) -> Option(String) {
  case index < 0 {
    True -> None
    False -> list_at(providers, index)
  }
}

fn list_at(items: List(a), index: Int) -> Option(a) {
  case items, index {
    [], _ -> None
    [item, ..], 0 -> Some(item)
    [_, ..rest], _ -> list_at(rest, index - 1)
  }
}
