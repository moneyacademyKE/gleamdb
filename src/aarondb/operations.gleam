//// # operations — typed, honest distributed runtime status

import aarondb/consensus
import aarondb/identity
import aarondb/projection
import aarondb/projection_index
import aarondb/raft_runtime as raft
import gleam/list
import gleam/option.{type Option}

pub type QuorumHealth {
  Healthy
  Degraded
  Unavailable
}

pub type Alarm {
  QuorumLost
  ProjectionFailed(projection.Failure)
  IndexUnavailable(projection_index.Health)
  UnsafeRecovery(identity.RecoveryAlarm)
}

pub type Status {
  Status(
    leader: Option(raft.NodeId),
    commit_index: Int,
    replication_lag: Int,
    quorum: QuorumHealth,
    projection: projection.Status,
    index_health: projection_index.Health,
    lease_count: Int,
    alarms: List(Alarm),
  )
}

pub fn status(
  raft_state: raft.State,
  voter_count: Int,
  acknowledged: Int,
  follower_match_index: Int,
  projection_status: projection.Status,
  index: projection_index.Index,
  consensus_state: consensus.State,
  recovery: identity.RecoveryState,
) -> Status {
  let quorum = quorum_health(voter_count, acknowledged)
  let lag = max(0, raft_state.hard.commit_index - follower_match_index)
  Status(
    raft_state.leader,
    raft_state.hard.commit_index,
    lag,
    quorum,
    projection_status,
    index.health,
    list.length(consensus_state.leases),
    alarms(quorum, projection_status.failure, index.health, recovery.alarms),
  )
}

fn quorum_health(voters: Int, acknowledged: Int) -> QuorumHealth {
  let required = voters / 2 + 1
  case acknowledged >= required {
    True -> Healthy
    False ->
      case acknowledged > 0 {
        True -> Degraded
        False -> Unavailable
      }
  }
}

fn alarms(
  quorum: QuorumHealth,
  projection_failure: Option(projection.Failure),
  index_health: projection_index.Health,
  recovery_alarms: List(identity.RecoveryAlarm),
) -> List(Alarm) {
  let quorum_alarms = case quorum {
    Healthy -> []
    _ -> [QuorumLost]
  }
  let projection_alarms = case projection_failure {
    option.Some(failure) -> [ProjectionFailed(failure)]
    option.None -> []
  }
  let index_alarms = case index_health {
    projection_index.Queryable -> []
    other -> [IndexUnavailable(other)]
  }
  list.append(
    quorum_alarms,
    list.append(
      projection_alarms,
      list.append(
        index_alarms,
        list.map(recovery_alarms, fn(alarm) { UnsafeRecovery(alarm) }),
      ),
    ),
  )
}

fn max(left: Int, right: Int) -> Int {
  case left > right {
    True -> left
    False -> right
  }
}
