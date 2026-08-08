import aarondb/fact
import aarondb/index/bm25
import gleeunit/should

pub fn golden_corpus_ranking_test() {
  let index =
    bm25.empty("body")
    |> bm25.add(fact.EntityId(1), "Gleam gleam database")
    |> bm25.add(fact.EntityId(2), "Gleam language")
    |> bm25.add(fact.EntityId(3), "Database engine")
    |> bm25.add(fact.EntityId(4), "unrelated")

  let results = bm25.search(index, "gleam database", 1.2, 0.75, 10)
  should.equal(result_ids(results), [
    fact.EntityId(1),
    fact.EntityId(2),
    fact.EntityId(3),
  ])
}

pub fn analyzer_boundary_and_unicode_contract_test() {
  let index =
    bm25.empty("body")
    |> bm25.add(fact.EntityId(1), "Hello, WORLD! version-2")
    |> bm25.add(fact.EntityId(2), "café Gleam")

  should.equal(
    result_ids(bm25.search(index, "hello world version 2", 1.2, 0.75, 10)),
    [fact.EntityId(1)],
  )
  // Non-ASCII graphemes are boundaries by the intentionally ASCII-only analyzer.
  should.equal(result_ids(bm25.search(index, "é", 1.2, 0.75, 10)), [])
  should.equal(result_ids(bm25.search(index, "gleam", 1.2, 0.75, 10)), [
    fact.EntityId(2),
  ])
}

pub fn incremental_updates_match_clean_rebuild_test() {
  let incremental =
    bm25.empty("body")
    |> bm25.add(fact.EntityId(1), "old text")
    |> bm25.add(fact.EntityId(2), "gleam database")
    |> bm25.add(fact.EntityId(1), "gleam gleam")
    |> bm25.remove(fact.EntityId(2), "stale caller text")
    |> bm25.add(fact.EntityId(3), "database")

  let rebuilt =
    bm25.build(
      [
        datom(1, "gleam gleam"),
        datom(3, "database"),
      ],
      "body",
    )

  should.equal(
    bm25.search(incremental, "gleam database", 1.2, 0.75, 10),
    bm25.search(rebuilt, "gleam database", 1.2, 0.75, 10),
  )
  should.equal(incremental.doc_count, rebuilt.doc_count)
  should.equal(incremental.doc_len, rebuilt.doc_len)
  should.equal(incremental.doc_freq, rebuilt.doc_freq)
}

pub fn empty_documents_are_indexable_but_do_not_match_test() {
  let index = bm25.empty("body") |> bm25.add(fact.EntityId(1), "")
  should.equal(index.doc_count, 1)
  should.equal(bm25.search(index, "anything", 1.2, 0.75, 10), [])
}

fn result_ids(results: List(bm25.SearchResult)) -> List(fact.EntityId) {
  case results {
    [] -> []
    [bm25.SearchResult(entity: entity, ..), ..rest] -> [
      entity,
      ..result_ids(rest)
    ]
  }
}

fn datom(entity: Int, text: String) -> fact.Datom {
  fact.Datom(
    entity: fact.EntityId(entity),
    attribute: "body",
    value: fact.Str(text),
    tx: 0,
    tx_index: 0,
    valid_time: 0,
    operation: fact.Assert,
  )
}
