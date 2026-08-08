import aarondb/fact
import aarondb/index/bm25
import aarondb/scoring
import gleam/list
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

fn create_text_datom(entity: Int, text: String) -> fact.Datom {
  fact.Datom(
    entity: fact.EntityId(entity),
    attribute: "msg/content",
    value: fact.Str(text),
    tx: 100,
    tx_index: 0,
    valid_time: 2_147_483_647,
    operation: fact.Assert,
  )
}

pub fn bm25_index_test() {
  let datoms = [
    create_text_datom(1, "hello world"),
    create_text_datom(2, "hello gleam"),
    create_text_datom(3, "gleam is awesome"),
  ]

  let index = bm25.build(datoms, "msg/content")

  index.doc_count |> should.equal(3)

  should.be_true(bm25.score(index, fact.EntityId(1), "hello", 1.2, 0.75) >. 0.0)
  should.be_true(bm25.score(index, fact.EntityId(2), "hello", 1.2, 0.75) >. 0.0)
  should.be_true(bm25.score(index, fact.EntityId(2), "gleam", 1.2, 0.75) >. 0.0)
  should.be_true(bm25.score(index, fact.EntityId(3), "gleam", 1.2, 0.75) >. 0.0)

  let s1_world = bm25.score(index, fact.EntityId(1), "world", 1.2, 0.75)
  let s1_hello = bm25.score(index, fact.EntityId(1), "hello", 1.2, 0.75)
  should.be_true(s1_world >. s1_hello)

  bm25.score(index, fact.EntityId(1), "missing", 1.2, 0.75)
  |> should.equal(0.0)
}

pub fn replacement_preserves_document_statistics_test() {
  let index =
    bm25.empty("msg/content")
    |> bm25.add(fact.EntityId(1), "alpha alpha")
    |> bm25.add(fact.EntityId(2), "beta")
    |> bm25.add(fact.EntityId(1), "beta")

  index.doc_count |> should.equal(2)
  bm25.score(index, fact.EntityId(1), "alpha", 1.2, 0.75)
  |> should.equal(0.0)
  should.be_true(bm25.score(index, fact.EntityId(1), "beta", 1.2, 0.75) >. 0.0)
}

pub fn stale_text_removal_is_safe_and_idempotent_test() {
  let index =
    bm25.empty("msg/content")
    |> bm25.add(fact.EntityId(1), "alpha beta")
    |> bm25.add(fact.EntityId(2), "beta")

  let removed = bm25.remove(index, fact.EntityId(1), "not the indexed text")
  let removed_twice = bm25.remove(removed, fact.EntityId(1), "also stale")

  removed.doc_count |> should.equal(1)
  removed_twice.doc_count |> should.equal(1)
  bm25.score(removed_twice, fact.EntityId(1), "beta", 1.2, 0.75)
  |> should.equal(0.0)
  should.be_true(
    bm25.score(removed_twice, fact.EntityId(2), "beta", 1.2, 0.75) >. 0.0,
  )
}

pub fn search_is_deterministic_and_excludes_non_matches_test() {
  let index =
    bm25.empty("msg/content")
    |> bm25.add(fact.EntityId(2), "common")
    |> bm25.add(fact.EntityId(1), "common")
    |> bm25.add(fact.EntityId(3), "other")

  bm25.search(index, "common", 1.2, 0.75, 10)
  |> should.equal([
    bm25.SearchResult(
      entity: fact.EntityId(1),
      score: bm25.score(index, fact.EntityId(1), "common", 1.2, 0.75),
    ),
    bm25.SearchResult(
      entity: fact.EntityId(2),
      score: bm25.score(index, fact.EntityId(2), "common", 1.2, 0.75),
    ),
  ])
}

pub fn invalid_parameters_and_limit_return_empty_results_test() {
  let index = bm25.empty("msg/content") |> bm25.add(fact.EntityId(1), "hello")

  bm25.score(index, fact.EntityId(1), "hello", -1.0, 0.75)
  |> should.equal(0.0)
  bm25.score(index, fact.EntityId(1), "hello", 1.2, 1.1)
  |> should.equal(0.0)
  bm25.search(index, "hello", -1.0, 0.75, 10) |> should.equal([])
  bm25.search(index, "hello", 1.2, 0.75, 0) |> should.equal([])
}

pub fn weighted_union_test() {
  let r1 = scoring.ScoredResult(fact.EntityId(1), 1.0)
  let r2 = scoring.ScoredResult(fact.EntityId(2), 0.5)
  let res_a = [r1, r2]

  let r3 = scoring.ScoredResult(fact.EntityId(2), 1.0)
  let r4 = scoring.ScoredResult(fact.EntityId(3), 0.5)
  let res_b = [r3, r4]

  let combined = scoring.weighted_union(res_a, res_b, 0.5, 0.5, scoring.MinMax)

  list.length(combined) |> should.equal(3)

  let assert Ok(first) = list.first(combined)
  first.score |> should.equal(0.5)
}
