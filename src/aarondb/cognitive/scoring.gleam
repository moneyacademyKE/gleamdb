//// # cognitive/scoring — retention/confidence math (ported; currently unwired)
////
//// Pure cognitive-memory scoring: Ebbinghaus forgetting with a floor, stability
//// growth, Hebbian association updates, softmax, and Bayesian confidence
//// updates. NOT imported by the engine. Retained as a tested pure library
//// pending integration; covered by `test/cognitive_test.gleam`.

import gleam/float
import gleam/list

@external(erlang, "math", "exp")
pub fn exp(x: Float) -> Float

@external(erlang, "math", "log")
pub fn log(x: Float) -> Float

@external(erlang, "math", "log10")
pub fn log10(x: Float) -> Float

@external(erlang, "math", "log2")
pub fn log2(x: Float) -> Float

@external(erlang, "math", "tanh")
pub fn tanh(x: Float) -> Float

pub const default_floor = 0.05

pub const default_stability = 14.0

pub const max_stability = 365.0

pub const stability_growth_rate = 20.0

pub const spacing_optimal = 7.0

pub const spacing_bonus_factor = 0.5

pub const hebbian_learning_rate = 0.01

/// EbbinghausWithFloor computes the Ebbinghaus retention with a floor value.
pub fn ebbinghaus_with_floor(
  days_since_access: Float,
  stability: Float,
  floor: Float,
) -> Float {
  let stab = case stability <=. 0.0 {
    True -> default_stability
    False -> stability
  }
  let r = exp(0.0 -. days_since_access /. stab)
  case r <. floor {
    True -> floor
    False -> r
  }
}

/// ComputeStability computes new stability from access count and spacing.
pub fn compute_stability(
  access_count: Int,
  avg_days_between_accesses: Float,
) -> Float {
  // Use log(1.0 + access_count) since log1p isn't standard
  let count_float = int_to_float(access_count)
  let base = log(1.0 +. count_float) *. stability_growth_rate
  let spacing = tanh(avg_days_between_accesses /. spacing_optimal)
  let stability = base *. { 1.0 +. spacing_bonus_factor *. spacing }

  let stability1 = case stability >. max_stability {
    True -> max_stability
    False -> stability
  }
  case stability1 <. default_stability {
    True -> default_stability
    False -> stability1
  }
}

/// Hebbian update for association weight
pub fn hebbian_update(current_weight: Float, effective_signal: Float) -> Float {
  let clamped_current = case current_weight <=. 0.0 {
    True -> 0.01
    False -> current_weight
  }

  let log_new =
    log(clamped_current)
    +. effective_signal
    *. log(1.0 +. hebbian_learning_rate)
  let new_weight = exp(log_new)
  case new_weight >. 1.0 {
    True -> 1.0
    False -> new_weight
  }
}

/// Softmax normalizes the weight vector so values sum to 1.
pub fn softmax(weights: List(Float)) -> List(Float) {
  let max_w = case list.reduce(weights, fn(acc, w) { float.max(acc, w) }) {
    Ok(m) -> m
    Error(_) -> 0.0
  }

  let shifted_exps = list.map(weights, fn(w) { exp(w -. max_w) })

  let sum = case list.reduce(shifted_exps, fn(acc, e) { acc +. e }) {
    Ok(s) -> s
    Error(_) -> 1.0
  }

  list.map(shifted_exps, fn(e) { e /. sum })
}

@external(erlang, "erlang", "float")
fn int_to_float(x: Int) -> Float

pub const laplace_smoothing_alpha = 0.025

pub const laplace_smoothing_scale = 0.95

pub const evidence_contradiction = 0.1

pub const evidence_co_activation = 0.65

pub const evidence_user_confirmed = 0.95

pub const evidence_user_rejected = 0.05

/// Bayesian update applies a Bayesian update to the prior confidence.
pub fn bayesian_update(prior: Float, evidence: Float) -> Float {
  let p = case prior <. 0.0 {
    True -> 0.0
    False ->
      case prior >. 1.0 {
        True -> 1.0
        False -> prior
      }
  }
  let e = case evidence <. 0.0 {
    True -> 0.0
    False ->
      case evidence >. 1.0 {
        True -> 1.0
        False -> evidence
      }
  }

  let numerator = p *. e
  let denominator = numerator +. { 1.0 -. p } *. { 1.0 -. e }

  let d = case denominator <. 0.000000001 {
    True -> 0.000000001
    False -> denominator
  }

  let posterior = numerator /. d
  laplace_smoothing_scale *. posterior +. laplace_smoothing_alpha
}
