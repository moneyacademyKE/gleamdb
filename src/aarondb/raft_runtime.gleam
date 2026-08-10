//// # raft_runtime — deterministic durable Raft protocol model
////
//// A transport-free reference runtime. Adapters persist `HardState` and deliver
//// authenticated RPCs; this module makes protocol decisions and never claims
//// network durability on its own.

import gleam/list
import gleam/option.{type Option, None, Some}

pub type NodeId =
  String

pub type LogIndex =
  Int

pub type Role {
  Follower
  Candidate
  Leader
}

pub type Member {
  Voter(id: NodeId)
  Learner(id: NodeId)
}

pub type LogEntry {
  LogEntry(term: Int, command: String)
}

pub type Snapshot {
  Snapshot(index: LogIndex, term: Int, state: String)
}

pub type HardState {
  HardState(term: Int, voted_for: Option(NodeId), commit_index: LogIndex)
}

/// The durable recovery boundary. Persist this value atomically before exposing
/// the corresponding reply or applying any command.
pub type Persisted {
  Persisted(
    hard: HardState,
    log: List(LogEntry),
    snapshot: Option(Snapshot),
    last_applied: LogIndex,
  )
}

pub type State {
  State(
    node: NodeId,
    role: Role,
    hard: HardState,
    members: List(Member),
    log: List(LogEntry),
    last_applied: LogIndex,
    leader: Option(NodeId),
    snapshot: Option(Snapshot),
  )
}

pub type Rpc {
  RequestVote(
    term: Int,
    candidate: NodeId,
    last_index: LogIndex,
    last_term: Int,
  )
  AppendEntries(
    term: Int,
    leader: NodeId,
    prev_index: LogIndex,
    prev_term: Int,
    entries: List(LogEntry),
    leader_commit: LogIndex,
  )
  InstallSnapshot(term: Int, leader: NodeId, snapshot: Snapshot)
  ReadIndex(term: Int, leader: NodeId, committed: LogIndex)
}

pub type Reply {
  VoteGranted(term: Int, granted: Bool)
  AppendAccepted(term: Int, matched: LogIndex)
  AppendRejected(term: Int, next_index: LogIndex)
  SnapshotAccepted(term: Int, index: LogIndex)
  ReadIndexAccepted(term: Int, index: LogIndex)
  StaleTerm(term: Int)
}

pub fn new(node: NodeId, members: List(Member)) -> State {
  State(node, Follower, HardState(0, None, -1), members, [], -1, None, None)
}

/// Restores only durable state. Leadership never survives recovery; the node must
/// establish a current-term quorum again.
pub fn recover(node: NodeId, members: List(Member), saved: Persisted) -> State {
  State(
    node,
    Follower,
    saved.hard,
    members,
    saved.log,
    saved.last_applied,
    None,
    saved.snapshot,
  )
}

pub fn persist(state: State) -> Persisted {
  Persisted(state.hard, state.log, state.snapshot, state.last_applied)
}

pub fn quorum(state: State) -> Int {
  list.length(voters(state.members)) / 2 + 1
}

pub fn last_index(state: State) -> LogIndex {
  snapshot_index(state.snapshot) + list.length(state.log)
}

pub fn last_term(state: State) -> Int {
  case list.reverse(state.log) {
    [LogEntry(term, _), ..] -> term
    [] -> snapshot_term(state.snapshot)
  }
}

/// Begins an election only for voting members. Persist the returned hard state
/// before dispatching vote RPCs.
pub fn start_election(state: State) -> State {
  case is_voter(state.members, state.node) {
    False -> state
    True ->
      State(
        ..state,
        role: Candidate,
        hard: HardState(
          state.hard.term + 1,
          Some(state.node),
          state.hard.commit_index,
        ),
        leader: None,
      )
  }
}

/// Turns a candidate into leader only from explicit, same-term quorum evidence.
pub fn win_election(state: State, granted_votes: Int) -> State {
  case state.role == Candidate && granted_votes >= quorum(state) {
    True -> State(..state, role: Leader, leader: Some(state.node))
    False -> state
  }
}

/// A leader may commit an index only after caller evidence proves current-term quorum replication.
pub fn commit_quorum(state: State, index: LogIndex, replicated: Int) -> State {
  case
    state.role == Leader
    && replicated >= quorum(state)
    && index > state.hard.commit_index
    && term_at(state, index) == state.hard.term
  {
    True ->
      State(
        ..state,
        hard: HardState(state.hard.term, state.hard.voted_for, index),
      )
    False -> state
  }
}

pub fn apply_committed(state: State) -> Result(State, String) {
  case state.last_applied < state.hard.commit_index {
    True -> Ok(State(..state, last_applied: state.hard.commit_index))
    False -> Ok(state)
  }
}

pub fn handle(state: State, rpc: Rpc) -> #(State, Reply) {
  case rpc {
    RequestVote(term, candidate, index, last) ->
      vote(state, term, candidate, index, last)
    AppendEntries(term, leader, prev_index, prev_term, entries, commit) ->
      append(state, term, leader, prev_index, prev_term, entries, commit)
    InstallSnapshot(term, leader, snapshot) ->
      install_snapshot(state, term, leader, snapshot)
    ReadIndex(term, leader, committed) ->
      read_index(state, term, leader, committed)
  }
}

/// The only automatic bootstrap: a one-voter cluster. Multi-node bootstrap
/// needs externally authenticated member configuration.
pub fn bootstrap_leader(state: State) -> State {
  case
    list.length(voters(state.members)) == 1
    && is_voter(state.members, state.node)
  {
    True -> State(..state, role: Leader, leader: Some(state.node))
    False -> state
  }
}

pub fn add_learner(state: State, id: NodeId) -> State {
  case is_member(state.members, id) {
    True -> state
    False -> State(..state, members: list.append(state.members, [Learner(id)]))
  }
}

/// Promotion is deliberately explicit so an adapter can make it a committed
/// joint-consensus configuration entry rather than a local mutation.
pub fn promote_voter(state: State, id: NodeId) -> State {
  State(
    ..state,
    members: list.map(state.members, fn(member) {
      case member {
        Learner(member_id) if member_id == id -> Voter(id)
        _ -> member
      }
    }),
  )
}

pub fn compact(
  state: State,
  index: LogIndex,
  state_image: String,
) -> Result(State, String) {
  case
    index <= state.hard.commit_index && index >= snapshot_index(state.snapshot)
  {
    True ->
      Ok(
        State(
          ..state,
          snapshot: Some(Snapshot(index, term_at(state, index), state_image)),
        ),
      )
    False -> Error("snapshot index must be committed and monotonic")
  }
}

fn vote(
  state: State,
  term: Int,
  candidate: NodeId,
  candidate_index: Int,
  candidate_term: Int,
) -> #(State, Reply) {
  case term < state.hard.term {
    True -> #(state, StaleTerm(state.hard.term))
    False -> {
      let stepped = step_down(state, term, None)
      let vote_is_available = case stepped.hard.voted_for {
        None -> True
        Some(voted) -> voted == candidate
      }
      let allowed =
        is_voter(stepped.members, candidate)
        && log_up_to_date(stepped, candidate_index, candidate_term)
        && vote_is_available
      case allowed {
        True -> {
          let next =
            State(
              ..stepped,
              hard: HardState(term, Some(candidate), stepped.hard.commit_index),
            )
          #(next, VoteGranted(term, True))
        }
        False -> #(stepped, VoteGranted(term, False))
      }
    }
  }
}

fn append(
  state: State,
  term: Int,
  leader: NodeId,
  prev: Int,
  prev_term: Int,
  entries: List(LogEntry),
  committed: Int,
) -> #(State, Reply) {
  case term < state.hard.term {
    True -> #(state, StaleTerm(state.hard.term))
    False -> {
      let follower = case leader == state.node {
        True -> state
        False -> step_down(state, term, Some(leader))
      }
      case term_at(follower, prev) == prev_term {
        False -> #(follower, AppendRejected(term, last_index(follower)))
        True -> {
          let next_log = truncate_and_append(follower, prev, entries)
          let candidate_commit =
            min(
              committed,
              snapshot_index(follower.snapshot) + list.length(next_log),
            )
          let next =
            State(
              ..follower,
              log: next_log,
              hard: HardState(
                term,
                follower.hard.voted_for,
                max(follower.hard.commit_index, candidate_commit),
              ),
            )
          #(next, AppendAccepted(term, last_index(next)))
        }
      }
    }
  }
}

fn install_snapshot(
  state: State,
  term: Int,
  leader: NodeId,
  snapshot: Snapshot,
) -> #(State, Reply) {
  case term < state.hard.term || snapshot.index < state.hard.commit_index {
    True -> #(state, StaleTerm(state.hard.term))
    False -> {
      let next =
        State(
          ..step_down(state, term, Some(leader)),
          snapshot: Some(snapshot),
          log: [],
          last_applied: snapshot.index,
          hard: HardState(term, None, snapshot.index),
        )
      #(next, SnapshotAccepted(term, snapshot.index))
    }
  }
}

fn read_index(
  state: State,
  term: Int,
  leader: NodeId,
  committed: Int,
) -> #(State, Reply) {
  case term < state.hard.term || state.leader != Some(leader) {
    True -> #(state, StaleTerm(state.hard.term))
    False -> #(
      state,
      ReadIndexAccepted(term, min(committed, state.hard.commit_index)),
    )
  }
}

fn step_down(state: State, term: Int, leader: Option(NodeId)) -> State {
  State(
    ..state,
    role: Follower,
    leader: leader,
    hard: HardState(term, None, state.hard.commit_index),
  )
}

fn log_up_to_date(state: State, index: Int, term: Int) -> Bool {
  case term > last_term(state) {
    True -> True
    False -> term == last_term(state) && index >= last_index(state)
  }
}

fn snapshot_index(snapshot: Option(Snapshot)) -> Int {
  case snapshot {
    Some(Snapshot(index, _, _)) -> index
    None -> -1
  }
}

fn snapshot_term(snapshot: Option(Snapshot)) -> Int {
  case snapshot {
    Some(Snapshot(_, term, _)) -> term
    None -> 0
  }
}

fn term_at(state: State, index: Int) -> Int {
  case index == snapshot_index(state.snapshot) {
    True -> snapshot_term(state.snapshot)
    False -> term_at_log(state.log, index - snapshot_index(state.snapshot) - 1)
  }
}

fn term_at_log(log: List(LogEntry), wanted: Int) -> Int {
  case log {
    [] -> -1
    [LogEntry(term, _), ..rest] ->
      case wanted == 0 {
        True -> term
        False -> term_at_log(rest, wanted - 1)
      }
  }
}

fn truncate_and_append(
  state: State,
  prev: Int,
  entries: List(LogEntry),
) -> List(LogEntry) {
  list.append(take(state.log, prev - snapshot_index(state.snapshot)), entries)
}

fn take(items: List(a), count: Int) -> List(a) {
  case items, count {
    _, 0 -> []
    [], _ -> []
    [item, ..rest], _ -> [item, ..take(rest, count - 1)]
  }
}

fn min(left: Int, right: Int) -> Int {
  case left < right {
    True -> left
    False -> right
  }
}

fn max(left: Int, right: Int) -> Int {
  case left > right {
    True -> left
    False -> right
  }
}

fn voters(members: List(Member)) -> List(Member) {
  list.filter(members, fn(member) {
    case member {
      Voter(_) -> True
      _ -> False
    }
  })
}

fn is_voter(members: List(Member), id: NodeId) -> Bool {
  list.any(members, fn(member) {
    case member {
      Voter(member_id) -> member_id == id
      _ -> False
    }
  })
}

fn is_member(members: List(Member), id: NodeId) -> Bool {
  list.any(members, fn(member) {
    case member {
      Voter(member_id) -> member_id == id
      Learner(member_id) -> member_id == id
    }
  })
}
