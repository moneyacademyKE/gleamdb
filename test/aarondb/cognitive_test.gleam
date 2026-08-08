//// Tests for the cognitive layer (`cognitive/erf` + `cognitive/scoring`).
////
//// STATUS: these modules are ported from MuninnDB but are NOT wired into the
//// engine — the engine has its own Cognitive-clause solver (`engine/cognitive`)
//// that does not import `cognitive/erf` or `cognitive/scoring`. They are
//// retained here as a pure, tested library (Ebbinghaus forgetting, Bayesian
//// confidence, Hebbian weights) pending integration. These tests lock in their
//// behaviour so the math is verified even while unwired.

import aarondb/cognitive/erf.{Embed384, Engram, StateActive, TypeFact}
import aarondb/cognitive/scoring
import gleam/list
import gleam/option.{None}
import gleam/result
import gleeunit/should

// --- erf.gleam: Engram type model ----------------------------------------

pub fn engram_construction_test() {
  // Constructing an Engram exercises the full ported memory model end-to-end.
  let e =
    Engram(
      id: "01HQ123456",
      created_at: 0,
      updated_at: 0,
      last_access: 0,
      confidence: 0.9,
      relevance: 0.8,
      stability: 14.0,
      access_count: 1,
      state: StateActive,
      embed_dim: Embed384,
      concept: "neural networks",
      created_by: "rumelhart",
      content: "Learning representations by back-propagating errors",
      tags: ["ml", "history"],
      associations: [],
      embedding: None,
      summary: "Backpropagation",
      key_points: ["multilayer", "gradient descent"],
      memory_type: TypeFact,
      classification: 0,
    )

  e.concept |> should.equal("neural networks")
  e.state |> should.equal(StateActive)
  e.access_count |> should.equal(1)
}

// --- scoring.gleam: Ebbinghaus retention ---------------------------------

pub fn ebbinghaus_full_retention_at_day_zero_test() {
  // exp(0) = 1.0; well above the floor, so retention is full.
  scoring.ebbinghaus_with_floor(0.0, 14.0, 0.05) |> should.equal(1.0)
}

pub fn ebbinghaus_floors_at_long_intervals_test() {
  // After far more days than the stability, retention decays below the floor
  // and is clamped to it (the function returns the exact floor parameter).
  scoring.ebbinghaus_with_floor(1000.0, 14.0, 0.05) |> should.equal(0.05)
}

pub fn ebbinghaus_defaults_stability_when_nonpositive_test() {
  // stability <= 0 falls back to the default (14.0); day zero is still 1.0.
  scoring.ebbinghaus_with_floor(0.0, 0.0, 0.05) |> should.equal(1.0)
}

// --- scoring.gleam: stability --------------------------------------------

pub fn compute_stability_is_bounded_test() {
  let s = scoring.compute_stability(10, 7.0)
  should.be_true(s >=. scoring.default_stability)
  should.be_true(s <=. scoring.max_stability)
}

pub fn compute_stability_floor_applied_for_low_activity_test() {
  // Zero accesses still yields at least the default stability floor.
  let s = scoring.compute_stability(0, 0.0)
  should.be_true(s >=. scoring.default_stability)
}

// --- scoring.gleam: Hebbian ----------------------------------------------

pub fn hebbian_update_stays_in_unit_interval_test() {
  let w = scoring.hebbian_update(0.5, 0.5)
  should.be_true(w >. 0.0)
  should.be_true(w <=. 1.0)
}

pub fn hebbian_update_positive_signal_increases_weight_test() {
  // A positive effective signal nudges the weight up, but the ceiling is 1.0.
  // (Learning rate is 0.01, so movement is slow — we assert direction, not size.)
  let before = 0.5
  let after = scoring.hebbian_update(before, 1.0)
  should.be_true(after >. before)
  should.be_true(after <=. 1.0)
}

// --- scoring.gleam: softmax ----------------------------------------------

pub fn softmax_empty_test() {
  scoring.softmax([]) |> should.equal([])
}

pub fn softmax_uniform_test() {
  // Equal inputs produce equal weights of 1/n (0.25 here, exactly representable).
  let sm = scoring.softmax([2.0, 2.0, 2.0, 2.0])
  should.be_true(list.all(sm, fn(w) { w == 0.25 }))
}

pub fn softmax_sums_to_one_test() {
  let sm = scoring.softmax([1.0, 2.0, 3.0])
  let sum = result.unwrap(list.reduce(sm, fn(a, b) { a +. b }), 0.0)
  should.be_true(sum >. 0.999999 && sum <. 1.000001)
}

// --- scoring.gleam: Bayesian ---------------------------------------------

pub fn bayesian_update_symmetric_prior_test() {
  // prior 0.5, evidence 0.5 → posterior 0.5 (the smoothing terms cancel out).
  let p = scoring.bayesian_update(0.5, 0.5)
  should.be_true(p >. 0.49 && p <. 0.51)
}

pub fn bayesian_update_clamps_inputs_test() {
  // Out-of-range evidence (1.5) is clamped to 1.0, so it behaves identically.
  scoring.bayesian_update(0.5, 1.5)
  |> should.equal(scoring.bayesian_update(0.5, 1.0))
}
