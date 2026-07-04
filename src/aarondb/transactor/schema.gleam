import aarondb/fact
import aarondb/index
import aarondb/shared/state
import gleam/dict
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

pub fn validate_unique(
  state: state.DbState,
  attr: String,
) -> Option(String) {
  let datoms =
    index.filter_by_attribute(state.aevt, attr)
    |> list.filter(fn(d) { d.operation == fact.Assert })
  let val_map =
    list.fold(datoms, dict.new(), fn(acc, d) {
      let existing = dict.get(acc, d.value) |> result.unwrap([])
      dict.insert(acc, d.value, [d.entity, ..existing])
    })
  let has_dupes =
    dict.fold(val_map, False, fn(acc, _, eids) {
      acc || list.length(list.unique(eids)) > 1
    })
  case has_dupes {
    True ->
      Some("Cannot make non-unique attribute unique: existing data has duplicates")
    False -> None
  }
}

pub fn validate_cardinality_one(
  state: state.DbState,
  attr: String,
) -> Option(String) {
  let datoms =
    index.filter_by_attribute(state.aevt, attr)
    |> list.filter(fn(d) { d.operation == fact.Assert })
  let ent_map =
    list.fold(datoms, dict.new(), fn(acc, d) {
      let existing = dict.get(acc, d.entity) |> result.unwrap([])
      dict.insert(acc, d.entity, [d.value, ..existing])
    })
  let has_multi =
    dict.fold(ent_map, False, fn(acc, _, vals) {
      acc || list.length(list.unique(vals)) > 1
    })
  case has_multi {
    True ->
      Some("Cannot set cardinality to ONE: existing entities have multiple values")
    False -> None
  }
}

pub fn validate_composite(
  state: state.DbState,
  attrs: List(String),
) -> Bool {
  let entity_map =
    list.fold(attrs, dict.new(), fn(acc, attr) {
      let datoms =
        index.filter_by_attribute(state.aevt, attr)
        |> list.filter(fn(d) { d.operation == fact.Assert })
      list.fold(datoms, acc, fn(acc2, d) {
        let existing = dict.get(acc2, d.entity) |> result.unwrap([])
        dict.insert(acc2, d.entity, [#(attr, d.value), ..existing])
      })
    })

  let entity_pairs =
    dict.to_list(entity_map)
    |> list.filter(fn(item) { list.length(item.1) == list.length(attrs) })

  list.any(entity_pairs, fn(p1) {
    list.any(entity_pairs, fn(p2) {
      p1.0 != p2.0
      && list.all(attrs, fn(a) {
        let v1 = list.key_find(p1.1, a)
        let v2 = list.key_find(p2.1, a)
        v1 == v2
      })
    })
  })
}
