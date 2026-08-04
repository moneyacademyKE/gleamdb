//// # cognitive/erf — memory model (ported from MuninnDB; currently unwired)
////
//// Pure type definitions for the cognitive memory model (Engram, Association,
//// lifecycle states, relation and memory types). NOT imported by the engine —
//// `engine/cognitive` implements its own Cognitive-clause solver. Retained as
//// a pure library pending integration; covered by `test/cognitive_test.gleam`.

import gleam/option.{type Option}

pub type Ulid =
  String

pub type LifecycleState {
  StatePlanning
  StateActive
  StatePaused
  StateBlocked
  StateCompleted
  StateCancelled
  StateArchived
  StateSoftDeleted
}

pub type RelType {
  RelSupports
  RelContradicts
  RelDependsOn
  RelSupersedes
  RelRelatesTo
  RelIsPartOf
  RelCauses
  RelPrecededBy
  RelFollowedBy
  RelCreatedByPerson
  RelBelongsToProject
  RelReferences
  RelImplements
  RelBlocks
  RelResolves
  RelUserDefined
}

pub type EmbedDimension {
  EmbedNone
  Embed384
  Embed768
  Embed1536
  Embed3072
  EmbedOther
}

pub type MemoryType {
  TypeFact
  TypeDecision
  TypeObservation
  TypePreference
  TypeIssue
  TypeTask
  TypeProcedure
  TypeEvent
  TypeGoal
  TypeConstraint
  TypeIdentity
  TypeReference
}

pub type Association {
  Association(
    target_id: Ulid,
    rel_type: RelType,
    weight: Float,
    confidence: Float,
    created_at: Int,
    last_activated: Int,
  )
}

pub type Engram {
  Engram(
    id: Ulid,
    created_at: Int,
    updated_at: Int,
    last_access: Int,
    confidence: Float,
    relevance: Float,
    stability: Float,
    access_count: Int,
    state: LifecycleState,
    embed_dim: EmbedDimension,
    concept: String,
    created_by: String,
    content: String,
    tags: List(String),
    associations: List(Association),
    embedding: Option(List(Float)),
    summary: String,
    key_points: List(String),
    memory_type: MemoryType,
    classification: Int,
  )
}
