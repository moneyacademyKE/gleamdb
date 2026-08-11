import aarondb/fact
import aarondb/vec_index
import aarondb/vector
import gleam/list
import gleeunit/should

// --- Insert & Size Tests ---

pub fn empty_index_test() {
  let idx = vec_index.new()
  should.equal(vec_index.size(idx), 0)
  should.be_false(vec_index.contains(idx, fact.EntityId(1)))
}

pub fn insert_single_test() {
  let idx =
    vec_index.new()
    |> vec_index.insert(fact.EntityId(1), [1.0, 0.0, 0.0])

  should.equal(vec_index.size(idx), 1)
  should.be_true(vec_index.contains(idx, fact.EntityId(1)))
}

pub fn insert_multiple_test() {
  let idx =
    vec_index.new()
    |> vec_index.insert(fact.EntityId(1), [1.0, 0.0, 0.0])
    |> vec_index.insert(fact.EntityId(2), [0.0, 1.0, 0.0])
    |> vec_index.insert(fact.EntityId(3), [0.0, 0.0, 1.0])

  should.equal(vec_index.size(idx), 3)
}

// --- Search Tests ---

pub fn search_exact_match_test() {
  let idx =
    vec_index.new()
    |> vec_index.insert(fact.EntityId(1), [1.0, 0.0, 0.0])
    |> vec_index.insert(fact.EntityId(2), [0.0, 1.0, 0.0])
    |> vec_index.insert(fact.EntityId(3), [1.0, 0.1, 0.0])

  // Search for vectors similar to [1.0, 0.0, 0.0]
  let results = vec_index.search(idx, [1.0, 0.0, 0.0], 0.9, 10)

  // Entity 1 is exact match (cos=1.0), Entity 3 is close (~0.995)
  should.be_true(list.length(results) >= 2)

  // Best result should be entity 1
  let assert Ok(best) = list.first(results)
  should.equal(best.entity, fact.EntityId(1))
  should.be_true(best.score >=. 0.99)
}

pub fn search_threshold_filtering_test() {
  let idx =
    vec_index.new()
    |> vec_index.insert(fact.EntityId(1), [1.0, 0.0, 0.0])
    |> vec_index.insert(fact.EntityId(2), [0.0, 1.0, 0.0])

  // High threshold should only match exact direction
  let strict = vec_index.search(idx, [1.0, 0.0, 0.0], 0.99, 10)
  should.equal(list.length(strict), 1)

  // Zero threshold matches everything
  let loose = vec_index.search(idx, [1.0, 0.0, 0.0], 0.0, 10)
  should.equal(list.length(loose), 2)
}

pub fn search_empty_index_test() {
  let idx = vec_index.new()
  let results = vec_index.search(idx, [1.0, 0.0, 0.0], 0.5, 10)
  should.equal(list.length(results), 0)
}

pub fn search_top_k_test() {
  let idx =
    vec_index.new()
    |> vec_index.insert(fact.EntityId(1), [1.0, 0.0, 0.0])
    |> vec_index.insert(fact.EntityId(2), [0.9, 0.1, 0.0])
    |> vec_index.insert(fact.EntityId(3), [0.8, 0.2, 0.0])
    |> vec_index.insert(fact.EntityId(4), [0.7, 0.3, 0.0])
    |> vec_index.insert(fact.EntityId(5), [0.0, 1.0, 0.0])

  // Ask for top-2 similar to [1.0, 0.0, 0.0]
  let results = vec_index.search(idx, [1.0, 0.0, 0.0], 0.5, 2)
  should.equal(list.length(results), 2)

  // Results should be sorted by score descending
  let assert Ok(first) = list.first(results)
  let assert Ok(second) = results |> list.drop(1) |> list.first()
  should.be_true(first.score >=. second.score)
}

// --- Delete Tests ---

pub fn delete_test() {
  let idx =
    vec_index.new()
    |> vec_index.insert(fact.EntityId(1), [1.0, 0.0, 0.0])
    |> vec_index.insert(fact.EntityId(2), [0.0, 1.0, 0.0])

  let idx2 = vec_index.delete(idx, fact.EntityId(1))
  should.equal(vec_index.size(idx2), 1)
  should.be_false(vec_index.contains(idx2, fact.EntityId(1)))
  should.be_true(vec_index.contains(idx2, fact.EntityId(2)))
}

pub fn delete_and_search_test() {
  let idx =
    vec_index.new()
    |> vec_index.insert(fact.EntityId(1), [1.0, 0.0, 0.0])
    |> vec_index.insert(fact.EntityId(2), [0.9, 0.1, 0.0])
    |> vec_index.delete(fact.EntityId(1))

  let results = vec_index.search(idx, [1.0, 0.0, 0.0], 0.5, 10)
  // Entity 1 deleted, only entity 2 should remain
  should.equal(list.length(results), 1)
  let assert Ok(r) = list.first(results)
  should.equal(r.entity, fact.EntityId(2))
}

// --- Vector Module Enrichment Tests ---

pub fn euclidean_distance_test() {
  let d = vector.euclidean_distance([1.0, 0.0, 0.0], [0.0, 1.0, 0.0])
  // sqrt(2) ≈ 1.414
  should.be_true(d >. 1.4)
  should.be_true(d <. 1.5)
}

pub fn normalize_test() {
  let n = vector.normalize([3.0, 4.0])
  // Should be [0.6, 0.8]
  let mag = vector.magnitude(n)
  should.be_true(mag >. 0.999)
  should.be_true(mag <. 1.001)
}

pub fn dimensions_test() {
  should.equal(vector.dimensions([1.0, 2.0, 3.0]), 3)
  should.equal(vector.dimensions([]), 0)
}

// --- NSW Graph Connectivity ---

pub fn mismatched_dimensions_are_rejected_test() {
  let assert Ok(idx) =
    vec_index.new()
    |> vec_index.try_insert(fact.EntityId(1), [1.0, 0.0, 0.0])

  should.be_error(vec_index.try_insert(idx, fact.EntityId(2), [1.0, 0.0]))
  should.be_error(vec_index.try_search(idx, [1.0, 0.0], 0.0, 10))

  // The compatibility wrappers also refuse to score mismatched vectors.
  should.equal(
    vec_index.size(vec_index.insert(idx, fact.EntityId(2), [1.0, 0.0])),
    1,
  )
  should.equal(vec_index.search(idx, [1.0, 0.0], 0.0, 10), [])
}

pub fn invalid_vectors_and_queries_are_rejected_test() {
  let idx = vec_index.new()
  should.be_error(vec_index.try_insert(idx, fact.EntityId(1), []))
  should.be_error(vec_index.try_insert(idx, fact.EntityId(1), [0.0, 0.0]))

  let assert Ok(idx) = vec_index.try_insert(idx, fact.EntityId(1), [1.0, 0.0])

  should.be_error(vec_index.try_search(idx, [], 0.0, 1))
  should.be_error(vec_index.try_search(idx, [0.0, 0.0], 0.0, 1))
  should.be_error(vec_index.try_search(idx, [1.0, 0.0], -1.1, 1))
  should.be_error(vec_index.try_search(idx, [1.0, 0.0], 1.1, 1))
  should.be_error(vec_index.try_search(idx, [1.0, 0.0], 0.0, 0))
  // Total compatibility wrappers preserve their historic failure behavior.
  should.equal(vec_index.search(idx, [0.0, 0.0], 0.0, 1), [])
}

pub fn threshold_is_inclusive_and_scores_are_descending_test() {
  let idx =
    vec_index.new()
    |> vec_index.insert(fact.EntityId(1), [1.0, 0.0])
    |> vec_index.insert(fact.EntityId(2), [0.8, 0.6])

  // The exact match is included at the inclusive upper boundary.
  let exact = vec_index.search(idx, [1.0, 0.0], 1.0, 10)
  should.equal(exact, [vec_index.SearchResult(fact.EntityId(1), 1.0)])

  let results = vec_index.search(idx, [1.0, 0.0], -1.0, 10)
  let assert Ok(first) = list.first(results)
  let assert Ok(second) = results |> list.drop(1) |> list.first()
  should.be_true(first.score >=. second.score)
}

pub fn delete_removes_a_result_from_a_subsequent_search_test() {
  let idx =
    vec_index.new()
    |> vec_index.insert(fact.EntityId(1), [1.0, 0.0])
    |> vec_index.insert(fact.EntityId(2), [0.0, 1.0])
    |> vec_index.delete(fact.EntityId(1))

  let results = vec_index.search(idx, [1.0, 0.0], -1.0, 10)
  should.be_false(
    list.any(results, fn(result) { result.entity == fact.EntityId(1) }),
  )
}

// --- Deterministic oracle tests ---

pub fn exact_search_is_deterministic_and_breaks_ties_by_entity_id_test() {
  let idx =
    vec_index.new_with_config(vec_index.deterministic_config([0, 0, 0]))
    |> vec_index.insert(fact.EntityId(3), [1.0, 0.0])
    |> vec_index.insert(fact.EntityId(1), [1.0, 0.0])
    |> vec_index.insert(fact.EntityId(2), [0.0, 1.0])

  let assert Ok(results) = vec_index.exact_search(idx, [1.0, 0.0], -1.0, 3)
  should.equal(list.map(results, fn(result) { result.entity }), [
    fact.EntityId(1),
    fact.EntityId(3),
    fact.EntityId(2),
  ])

  let approximate = vec_index.search(idx, [1.0, 0.0], -1.0, 3)
  should.equal(approximate, vec_index.search(idx, [1.0, 0.0], -1.0, 3))
}

pub fn exact_search_covers_empty_deleted_and_invalid_inputs_test() {
  let empty = vec_index.new_with_config(vec_index.deterministic_config([]))
  let assert Ok(empty_results) =
    vec_index.exact_search(empty, [1.0, 0.0], -1.0, 1)
  should.equal(empty_results, [])

  let idx =
    empty
    |> vec_index.insert(fact.EntityId(1), [1.0, 0.0])
    |> vec_index.delete(fact.EntityId(1))
  let assert Ok(deleted_results) =
    vec_index.exact_search(idx, [1.0, 0.0], -1.0, 1)
  should.equal(deleted_results, [])

  should.be_error(vec_index.exact_search(empty, [], -1.0, 1))
  should.be_error(vec_index.exact_search(empty, [0.0, 0.0], -1.0, 1))
}
