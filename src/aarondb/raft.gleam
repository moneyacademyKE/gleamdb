//// # raft — INACTIVE clustering scaffold (unwired stub)
////
//// ⚠️ STATUS: A complete, pure, unit-tested **leader-election** state machine,
//// now **unwired** from the engine. The single-node AaronDB core no longer
//// holds, initialises, or drives any raft state:
////
////   - `DbState` no longer has a `raft_state` field.
////   - The transactor has no `RaftMsg` variant and never calls `handle_message`.
////   - `aarondb.is_leader` has been removed.
////
//// SCOPE: This is Raft **election only**. The log-replication half
//// (AppendEntries, commit index, log matching, apply) was never present, so
//// it could not deliver replicated consistency on its own.
////
//// The pure protocol logic is covered by `test/aarondb/raft_test`. It is
//// retained as a deliberate, documented stub — a clustering seed, not active
//// code. Do not partially activate it. Revival requires an approved distributed
//// design with peer transport/configuration, durable state, AppendEntries/log
//// replication, membership changes, quorum commit, and partition/failure tests.

import gleam/erlang/process.{type Pid}
import gleam/list
import gleam/option.{type Option, None, Some}

// --- Types ---

/// The three roles in Raft's election protocol.
pub type RaftRole {
  Follower
  Candidate
  Leader
}

/// The pure state of the inactive Raft election machine.
/// No runtime component interprets its effects.
pub type RaftState {
  RaftState(
    role: RaftRole,
    current_term: Int,
    voted_for: Option(Pid),
    peers: List(Pid),
    votes_received: Int,
    leader_pid: Option(Pid),
  )
}

/// Effects emitted after a state transition (data, not side effects).
/// This de-complects the pure state machine from side effects.
pub type RaftEffect {
  SendHeartbeat(to: Pid, term: Int, leader: Pid)
  SendVoteRequest(to: Pid, term: Int, candidate: Pid)
  SendVoteResponse(to: Pid, term: Int, granted: Bool)
  RegisterAsLeader
  UnregisterAsLeader
  ResetElectionTimer
  StartHeartbeatTimer
  StopHeartbeatTimer
}

/// Messages the Raft state machine can process.
pub type RaftMessage {
  Heartbeat(term: Int, leader: Pid)
  HeartbeatResponse(term: Int, from: Pid)
  VoteRequest(term: Int, candidate: Pid)
  VoteResponse(term: Int, granted: Bool, from: Pid)
  ElectionTimeout
  HeartbeatTick
}

// --- Constructor ---

/// Create a new Raft state in Follower role at term 0.
pub fn new(peers: List(Pid)) -> RaftState {
  RaftState(
    role: Follower,
    current_term: 0,
    voted_for: None,
    peers: peers,
    votes_received: 0,
    leader_pid: None,
  )
}

// --- Pure State Machine ---

/// Process a Raft message and return the new state + effects.
/// This is the ONLY entry point. It is pure — no side effects.
pub fn handle_message(
  state: RaftState,
  msg: RaftMessage,
  self_pid: Pid,
) -> #(RaftState, List(RaftEffect)) {
  case msg {
    ElectionTimeout -> handle_election_timeout(state, self_pid)
    HeartbeatTick -> handle_heartbeat_tick(state, self_pid)
    Heartbeat(term, leader) -> handle_heartbeat(state, term, leader)
    HeartbeatResponse(term, _from) -> handle_heartbeat_response(state, term)
    VoteRequest(term, candidate) ->
      handle_vote_request(state, term, candidate, self_pid)
    VoteResponse(term, granted, _from) ->
      handle_vote_response(state, term, granted, self_pid)
  }
}

// --- Handlers ---

/// Election timeout fires. Follower or Candidate becomes Candidate for a new term.
fn handle_election_timeout(
  state: RaftState,
  self_pid: Pid,
) -> #(RaftState, List(RaftEffect)) {
  case state.role {
    Leader -> #(state, [])
    // Leaders don't timeout
    _ -> {
      let new_term = state.current_term + 1
      let new_state =
        RaftState(
          ..state,
          role: Candidate,
          current_term: new_term,
          voted_for: Some(self_pid),
          votes_received: 1,
          // Vote for self
          leader_pid: None,
        )

      // Request votes from all peers
      let vote_effects =
        list.map(state.peers, fn(peer) {
          SendVoteRequest(to: peer, term: new_term, candidate: self_pid)
        })

      // Check if we already have majority (single-node cluster)
      case has_majority(new_state) {
        True -> {
          let leader_state = RaftState(..new_state, role: Leader)
          let effects =
            list.append(vote_effects, [
              RegisterAsLeader,
              StartHeartbeatTimer,
            ])
          #(leader_state, effects)
        }
        False -> {
          #(new_state, list.append(vote_effects, [ResetElectionTimer]))
        }
      }
    }
  }
}

/// Heartbeat tick fires. Leader sends heartbeats to all peers.
fn handle_heartbeat_tick(
  state: RaftState,
  self_pid: Pid,
) -> #(RaftState, List(RaftEffect)) {
  case state.role {
    Leader -> {
      let effects =
        list.map(state.peers, fn(peer) {
          SendHeartbeat(to: peer, term: state.current_term, leader: self_pid)
        })
      #(state, effects)
    }
    _ -> #(state, [])
    // Only leaders send heartbeats
  }
}

/// Receive a heartbeat from a leader.
fn handle_heartbeat(
  state: RaftState,
  term: Int,
  leader: Pid,
) -> #(RaftState, List(RaftEffect)) {
  case term >= state.current_term {
    True -> {
      // Valid leader — become/stay follower, reset election timer
      let new_state =
        RaftState(
          ..state,
          role: Follower,
          current_term: term,
          leader_pid: Some(leader),
          voted_for: None,
          votes_received: 0,
        )
      let effects = case state.role {
        Leader -> [UnregisterAsLeader, StopHeartbeatTimer, ResetElectionTimer]
        _ -> [ResetElectionTimer]
      }
      #(new_state, effects)
    }
    False -> {
      // Stale heartbeat — ignore
      #(state, [])
    }
  }
}

/// Receive a heartbeat response (leader uses this for liveness tracking).
fn handle_heartbeat_response(
  state: RaftState,
  term: Int,
) -> #(RaftState, List(RaftEffect)) {
  case term > state.current_term {
    True -> {
      // Higher term seen — step down
      let new_state =
        RaftState(
          ..state,
          role: Follower,
          current_term: term,
          voted_for: None,
          votes_received: 0,
          leader_pid: None,
        )
      let effects = case state.role {
        Leader -> [UnregisterAsLeader, StopHeartbeatTimer, ResetElectionTimer]
        _ -> [ResetElectionTimer]
      }
      #(new_state, effects)
    }
    False -> #(state, [])
  }
}

/// Handle incoming vote request from a candidate.
fn handle_vote_request(
  state: RaftState,
  term: Int,
  candidate: Pid,
  _self_pid: Pid,
) -> #(RaftState, List(RaftEffect)) {
  case term > state.current_term {
    True -> {
      // Higher term — grant vote, become follower
      let new_state =
        RaftState(
          ..state,
          role: Follower,
          current_term: term,
          voted_for: Some(candidate),
          votes_received: 0,
          leader_pid: None,
        )
      let effects = case state.role {
        Leader -> [
          UnregisterAsLeader,
          StopHeartbeatTimer,
          SendVoteResponse(to: candidate, term: term, granted: True),
          ResetElectionTimer,
        ]
        _ -> [
          SendVoteResponse(to: candidate, term: term, granted: True),
          ResetElectionTimer,
        ]
      }
      #(new_state, effects)
    }
    False -> {
      case term == state.current_term {
        True -> {
          // Same term — grant only if we haven't voted yet
          case state.voted_for {
            None -> {
              let new_state = RaftState(..state, voted_for: Some(candidate))
              #(new_state, [
                SendVoteResponse(to: candidate, term: term, granted: True),
                ResetElectionTimer,
              ])
            }
            Some(prev) -> {
              // Already voted — grant only if for the same candidate
              let granted = prev == candidate
              #(state, [
                SendVoteResponse(to: candidate, term: term, granted: granted),
              ])
            }
          }
        }
        False -> {
          // Stale term — reject
          #(state, [
            SendVoteResponse(
              to: candidate,
              term: state.current_term,
              granted: False,
            ),
          ])
        }
      }
    }
  }
}

/// Handle incoming vote response.
fn handle_vote_response(
  state: RaftState,
  term: Int,
  granted: Bool,
  _self_pid: Pid,
) -> #(RaftState, List(RaftEffect)) {
  case state.role {
    Candidate -> {
      case term == state.current_term && granted {
        True -> {
          let new_state =
            RaftState(..state, votes_received: state.votes_received + 1)
          case has_majority(new_state) {
            True -> {
              // Won election!
              let leader_state = RaftState(..new_state, role: Leader)
              #(leader_state, [RegisterAsLeader, StartHeartbeatTimer])
            }
            False -> #(new_state, [])
          }
        }
        False -> {
          case term > state.current_term {
            True -> {
              // Higher term — step down
              let new_state =
                RaftState(
                  ..state,
                  role: Follower,
                  current_term: term,
                  voted_for: None,
                  votes_received: 0,
                  leader_pid: None,
                )
              #(new_state, [ResetElectionTimer])
            }
            False -> #(state, [])
          }
        }
      }
    }
    _ -> #(state, [])
    // Ignore stale vote responses
  }
}

// --- Helpers ---

/// Check if we have a majority of votes (> half the cluster).
fn has_majority(state: RaftState) -> Bool {
  let cluster_size = list.length(state.peers) + 1
  // peers + self
  state.votes_received > cluster_size / 2
}

/// Check if this node is the current leader.
pub fn is_leader(state: RaftState) -> Bool {
  state.role == Leader
}

/// Add a peer to the cluster.
pub fn add_peer(state: RaftState, peer: Pid) -> RaftState {
  RaftState(..state, peers: [peer, ..state.peers])
}

/// Remove a peer from the cluster.
pub fn remove_peer(state: RaftState, peer: Pid) -> RaftState {
  RaftState(..state, peers: list.filter(state.peers, fn(p) { p != peer }))
}
