//// # distributed_harness — deterministic adversarial safety oracle
////
//// This module deliberately models reproducible fault schedules and invariant
//// checks only. The process/network adapter owns delivery; it records the
//// resulting observations here so a failure can be replayed without timing or
//// scheduler luck.

import gleam/list

pub type Fault {
  Partition(String, String)
  Heal(String, String)
  DuplicateRpc(String)
  ReorderRpc(String)
  Crash(String)
  Restart(String)
  DiskFault(String)
  SlowFollower(String)
  MembershipChurn(String)
  ClockSkew(String, Int)
}

pub type Observation {
  Leaders(term: Int, nodes: List(String))
  Applied(index: Int, copies: Int)
  Fence(resource: String, expected: Int, received: Int)
  RecoveryAlarm(present: Bool)
}

pub type Violation {
  SplitBrain(term: Int, leaders: List(String))
  DuplicateApply(index: Int, copies: Int)
  StaleFenceAccepted(resource: String, expected: Int, received: Int)
  UnsafeRecoveryUnalarmed
}

pub type Run {
  Run(seed: Int, schedule: List(Fault), observations: List(Observation))
}

pub type Artifact {
  Artifact(
    seed: Int,
    schedule: List(Fault),
    observations: List(Observation),
    violations: List(Violation),
  )
}

/// The stable seeds are a public replay corpus. Keep them fixed: changing a
/// seed changes a reproducibility contract and belongs in a release note.
pub fn schedule(seed: Int) -> List(Fault) {
  case seed {
    11 -> [
      Partition("a", "b"),
      DuplicateRpc("append-7"),
      Heal("a", "b"),
    ]
    23 -> [Crash("b"), Restart("b"), ReorderRpc("append-9")]
    37 -> [
      SlowFollower("c"),
      MembershipChurn("d"),
      ClockSkew("a", -5),
    ]
    41 -> [
      DiskFault("b"),
      Crash("b"),
      Restart("b"),
      ReorderRpc("snapshot-12"),
    ]
    _ -> [Partition("a", "c"), Heal("a", "c")]
  }
}

pub fn replay(seed: Int, observations: List(Observation)) -> Run {
  Run(seed, schedule(seed), observations)
}

pub fn inspect(run: Run) -> List(Violation) {
  inspect_observations(run.observations)
}

/// Persist this value exactly when an adapter run fails. It contains every
/// deterministic input needed to reproduce the invariant failure locally or
/// in CI; raw process logs may be attached alongside it but are not required
/// to reconstruct the schedule.
pub fn artifact(run: Run) -> Artifact {
  Artifact(run.seed, run.schedule, run.observations, inspect(run))
}

pub fn passed(run: Run) -> Bool {
  case inspect(run) {
    [] -> True
    _ -> False
  }
}

fn inspect_observations(observations: List(Observation)) -> List(Violation) {
  case observations {
    [] -> []
    [observation, ..rest] ->
      case violation(observation) {
        [] -> inspect_observations(rest)
        found -> list.append(found, inspect_observations(rest))
      }
  }
}

fn violation(observation: Observation) -> List(Violation) {
  case observation {
    Leaders(term, leaders) ->
      case list_length(leaders) > 1 {
        True -> [SplitBrain(term, leaders)]
        False -> []
      }
    Applied(index, copies) ->
      case copies > 1 {
        True -> [DuplicateApply(index, copies)]
        False -> []
      }
    Fence(resource, expected, received) ->
      case received < expected {
        True -> [StaleFenceAccepted(resource, expected, received)]
        False -> []
      }
    RecoveryAlarm(present) ->
      case present {
        True -> []
        False -> [UnsafeRecoveryUnalarmed]
      }
  }
}

fn list_length(items: List(a)) -> Int {
  case items {
    [] -> 0
    [_item, ..rest] -> 1 + list_length(rest)
  }
}
