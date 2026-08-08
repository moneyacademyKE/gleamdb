import aarondb/fact
import aarondb/vec_index
import gleam/int
import gleam/list
import gleeunit/should

pub fn exact_search_orders_ties_by_entity_id_test() {
  let idx =
    vec_index.new_with_config(vec_index.deterministic_config([0, 0, 0]))
    |> vec_index.insert(fact.EntityId(3), [1.0, 0.0])
    |> vec_index.insert(fact.EntityId(1), [1.0, 0.0])
    |> vec_index.insert(fact.EntityId(2), [0.0, 1.0])

  let assert Ok(results) = vec_index.exact_search(idx, [1.0, 0.0], -1.0, 3)
  should.equal(results, [
    vec_index.SearchResult(fact.EntityId(1), 1.0),
    vec_index.SearchResult(fact.EntityId(3), 1.0),
    vec_index.SearchResult(fact.EntityId(2), 0.0),
  ])
}

pub fn deterministic_levels_produce_repeatable_results_test() {
  let config = vec_index.deterministic_config([2, 1, 0, 0, 1])
  let points = corpus()
  let first = list.fold(points, vec_index.new_with_config(config), insert_point)
  let second =
    list.fold(points, vec_index.new_with_config(config), insert_point)

  should.equal(first.layers, second.layers)
  should.equal(
    vec_index.search(first, [1.0, 0.0], -1.0, 5),
    vec_index.search(second, [1.0, 0.0], -1.0, 5),
  )
}

pub fn exact_oracle_and_hnsw_recall_corpus_test() {
  let idx =
    list.fold(
      corpus(),
      vec_index.new_with_config(vec_index.deterministic_config([2, 1, 1, 0, 0])),
      insert_point,
    )
  let assert Ok(exact) = vec_index.exact_search(idx, [0.98, 0.02], -1.0, 5)
  let approximate = vec_index.search(idx, [0.98, 0.02], -1.0, 5)

  should.equal(approximate, exact)
  should.equal(recall_at(approximate, exact, 5), 1.0)
}

pub fn thousand_operation_churn_preserves_membership_and_recall_test() {
  let idx =
    int.range(
      from: 1,
      to: 1001,
      with: vec_index.new_with_config(vec_index.deterministic_config([])),
      run: fn(index, operation) {
        let entity = fact.EntityId({ operation % 40 } + 1)
        case operation % 5 {
          0 -> vec_index.delete(index, entity)
          _ -> vec_index.insert(index, entity, churn_vector(operation))
        }
      },
    )

  let assert Ok(exact) = vec_index.exact_search(idx, [1.0, 0.0, 0.5], -1.0, 10)
  let approximate = vec_index.search(idx, [1.0, 0.0, 0.5], -1.0, 10)

  should.equal(approximate, exact)
  should.equal(recall_at(approximate, exact, 10), 1.0)
  list.each(approximate, fn(found) {
    should.be_true(vec_index.contains(idx, found.entity))
  })
}

fn corpus() -> List(#(fact.EntityId, List(Float))) {
  [
    #(fact.EntityId(1), [1.0, 0.0]),
    #(fact.EntityId(2), [0.95, 0.05]),
    #(fact.EntityId(3), [0.7, 0.3]),
    #(fact.EntityId(4), [0.0, 1.0]),
    #(fact.EntityId(5), [-1.0, 0.0]),
  ]
}

fn insert_point(
  index: vec_index.VecIndex,
  point: #(fact.EntityId, List(Float)),
) -> vec_index.VecIndex {
  vec_index.insert(index, point.0, point.1)
}

fn churn_vector(operation: Int) -> List(Float) {
  let lane = int.to_float(operation % 7)
  [1.0 +. lane, lane +. 1.0, 0.5]
}

fn recall_at(
  approximate: List(vec_index.SearchResult),
  exact: List(vec_index.SearchResult),
  k: Int,
) -> Float {
  let expected = exact |> list.take(k) |> list.map(fn(item) { item.entity })
  let found = approximate |> list.take(k) |> list.map(fn(item) { item.entity })
  let matches =
    list.filter(expected, fn(entity) { list.contains(found, entity) })
  case list.length(expected) {
    0 -> 1.0
    count -> int.to_float(list.length(matches)) /. int.to_float(count)
  }
}
