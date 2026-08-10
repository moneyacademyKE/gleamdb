import aarondb/distributed_harness as harness
import gleeunit/should

pub fn schedules_are_repeatable_per_seed_test() {
  should.equal(harness.schedule(11), harness.schedule(11))
  should.equal(harness.schedule(11), [
    harness.Partition("a", "b"),
    harness.DuplicateRpc("append-7"),
    harness.Heal("a", "b"),
  ])
}

pub fn known_bad_split_brain_mutant_is_detected_test() {
  let run =
    harness.replay(11, [
      harness.Leaders(8, ["a", "b"]),
      harness.RecoveryAlarm(True),
    ])
  should.equal(harness.inspect(run), [harness.SplitBrain(8, ["a", "b"])])
}

pub fn known_bad_duplicate_apply_mutant_is_detected_test() {
  let run =
    harness.replay(23, [harness.Applied(9, 2), harness.RecoveryAlarm(True)])
  should.equal(harness.inspect(run), [harness.DuplicateApply(9, 2)])
}

pub fn known_bad_stale_fence_mutant_is_detected_test() {
  let run =
    harness.replay(37, [harness.Fence("db", 4, 3), harness.RecoveryAlarm(True)])
  should.equal(harness.inspect(run), [harness.StaleFenceAccepted("db", 4, 3)])
}

pub fn known_bad_unsafe_recovery_mutant_is_detected_test() {
  let run = harness.replay(23, [harness.RecoveryAlarm(False)])
  should.equal(harness.inspect(run), [harness.UnsafeRecoveryUnalarmed])
}

pub fn valid_history_has_no_safety_violation_test() {
  let run =
    harness.replay(37, [
      harness.Leaders(4, ["a"]),
      harness.Applied(12, 1),
      harness.Fence("db", 5, 5),
      harness.RecoveryAlarm(True),
    ])
  should.equal(harness.inspect(run), [])
}
