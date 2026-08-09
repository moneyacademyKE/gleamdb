//// A local, in-memory BM25 index for one string attribute.
////
//// ## Contract
////
//// Documents are keyed by entity. `add` replaces an existing entity document
//// atomically within the immutable index; callers do not need to retract the
//// prior text first. `remove` is idempotent and removes the indexed entity
//// regardless of the supplied historical text, which prevents stale input from
//// corrupting document-frequency statistics.
////
//// Tokenisation lowercases ASCII letters and digits, splits every other
//// grapheme as a boundary, and does not apply stemming or stop-word removal.
//// Ranking uses BM25's standard `k1`/`b` formula. Search returns only positive
//// scores, ordered by descending score and then ascending entity ID to make ties
//// deterministic. This module is an index primitive: database transaction and
//// query-engine integration are not claimed by this contract.

import aarondb/fact
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/list
import gleam/order
import gleam/result
import gleam/string

pub type BM25Index {
  BM25Index(
    // term -> (entity -> term_frequency)
    term_freq: Dict(String, Dict(fact.EntityId, Int)),
    // term -> document_frequency (count of entities containing term)
    doc_freq: Dict(String, Int),
    // entity -> document_length (total terms in attribute value)
    doc_len: Dict(fact.EntityId, Int),
    // average document length across all entities
    avg_doc_len: Float,
    // total documents (entities with this attribute)
    doc_count: Int,
    // indexed attribute
    attribute: String,
  )
}

/// A deterministic BM25 search result.
pub type SearchResult {
  SearchResult(entity: fact.EntityId, score: Float)
}

pub fn empty(attribute: String) -> BM25Index {
  BM25Index(
    term_freq: dict.new(),
    doc_freq: dict.new(),
    doc_len: dict.new(),
    avg_doc_len: 0.0,
    doc_count: 0,
    attribute: attribute,
  )
}

/// Builds an index from string datoms for `attribute`.
///
/// If input contains multiple datoms for an entity, the last datom in input
/// wins, matching `add` replacement semantics. Callers that retain historical
/// datoms should filter to their desired active snapshot before building.
pub fn build(datoms: List(fact.Datom), attribute: String) -> BM25Index {
  datoms
  |> list.filter(fn(d) { d.attribute == attribute })
  |> list.fold(empty(attribute), fn(idx, datom) {
    case datom.value {
      fact.Str(text) -> add(idx, datom.entity, text)
      _ -> idx
    }
  })
}

/// Adds or replaces one entity document.
pub fn add(index: BM25Index, entity: fact.EntityId, text: String) -> BM25Index {
  let base = remove_entity(index, entity)
  let terms = tokenize(text)
  let doc_length = list.length(terms)

  let term_counts =
    list.fold(terms, dict.new(), fn(acc, term) {
      case dict.get(acc, term) {
        Ok(count) -> dict.insert(acc, term, count + 1)
        Error(_) -> dict.insert(acc, term, 1)
      }
    })

  let #(new_tf, new_df) =
    dict.fold(
      term_counts,
      #(base.term_freq, base.doc_freq),
      fn(acc, term, count) {
        let #(tf_acc, df_acc) = acc
        let term_entry = case dict.get(tf_acc, term) {
          Ok(entry) -> dict.insert(entry, entity, count)
          Error(_) -> dict.from_list([#(entity, count)])
        }
        let df = dict.get(df_acc, term) |> result.unwrap(0)
        #(
          dict.insert(tf_acc, term, term_entry),
          dict.insert(df_acc, term, df + 1),
        )
      },
    )

  let old_total_len = base.avg_doc_len *. int.to_float(base.doc_count)
  let new_count = base.doc_count + 1
  let new_avg_len =
    { old_total_len +. int.to_float(doc_length) } /. int.to_float(new_count)

  BM25Index(
    term_freq: new_tf,
    doc_freq: new_df,
    doc_len: dict.insert(base.doc_len, entity, doc_length),
    avg_doc_len: new_avg_len,
    doc_count: new_count,
    attribute: base.attribute,
  )
}

/// Removes an entity document. The supplied text is intentionally ignored:
/// indexed state is the source of truth, so removal is safe and idempotent.
pub fn remove(
  index: BM25Index,
  entity: fact.EntityId,
  _text: String,
) -> BM25Index {
  remove_entity(index, entity)
}

/// Removes an entity document using the index's own term and length state.
pub fn remove_entity(index: BM25Index, entity: fact.EntityId) -> BM25Index {
  let old_length = dict.get(index.doc_len, entity)

  case old_length {
    Error(_) -> index
    Ok(doc_length) -> {
      let #(new_tf, new_df) =
        dict.fold(
          index.term_freq,
          #(dict.new(), dict.new()),
          fn(acc, term, entries) {
            let #(tf_acc, df_acc) = acc
            case dict.get(entries, entity) {
              Error(_) -> {
                let df = dict.get(index.doc_freq, term) |> result.unwrap(0)
                #(
                  dict.insert(tf_acc, term, entries),
                  dict.insert(df_acc, term, df),
                )
              }
              Ok(_) -> {
                let remaining = dict.delete(entries, entity)
                let tf_next = case dict.size(remaining) {
                  0 -> tf_acc
                  _ -> dict.insert(tf_acc, term, remaining)
                }
                let df = dict.get(index.doc_freq, term) |> result.unwrap(0)
                let df_next = case df <= 1 {
                  True -> df_acc
                  False -> dict.insert(df_acc, term, df - 1)
                }
                #(tf_next, df_next)
              }
            }
          },
        )

      let new_count = int.max(0, index.doc_count - 1)
      let old_total_len = index.avg_doc_len *. int.to_float(index.doc_count)
      let new_avg_len = case new_count {
        0 -> 0.0
        _ ->
          { old_total_len -. int.to_float(doc_length) }
          /. int.to_float(new_count)
      }

      BM25Index(
        term_freq: new_tf,
        doc_freq: new_df,
        doc_len: dict.delete(index.doc_len, entity),
        avg_doc_len: new_avg_len,
        doc_count: new_count,
        attribute: index.attribute,
      )
    }
  }
}

/// Scores an entity for a query using standard BM25 parameters.
///
/// `k1` must be non-negative and `b` must be in `[0.0, 1.0]`; invalid
/// parameters return `0.0` to preserve this total compatibility API.
pub fn score(
  index: BM25Index,
  entity: fact.EntityId,
  query: String,
  k1: Float,
  b: Float,
) -> Float {
  case valid_parameters(k1, b) {
    False -> 0.0
    True -> score_valid(index, entity, query, k1, b)
  }
}

/// Searches every indexed entity and returns deterministic positive-score hits.
/// `limit` must be positive; invalid BM25 parameters or limit return `[]`.
pub fn search(
  index: BM25Index,
  query: String,
  k1: Float,
  b: Float,
  limit: Int,
) -> List(SearchResult) {
  case valid_parameters(k1, b) && limit > 0 {
    False -> []
    True ->
      dict.keys(index.doc_len)
      |> list.map(fn(entity) {
        SearchResult(entity, score_valid(index, entity, query, k1, b))
      })
      |> list.filter(fn(result) { result.score >. 0.0 })
      |> list.sort(compare_results)
      |> list.take(limit)
  }
}

fn compare_results(a: SearchResult, b: SearchResult) {
  case float.compare(b.score, a.score) {
    order.Eq ->
      int.compare(fact.eid_to_integer(a.entity), fact.eid_to_integer(b.entity))
    other -> other
  }
}

fn valid_parameters(k1: Float, b: Float) -> Bool {
  k1 >=. 0.0 && b >=. 0.0 && b <=. 1.0
}

fn score_valid(
  index: BM25Index,
  entity: fact.EntityId,
  query: String,
  k1: Float,
  b: Float,
) -> Float {
  let terms = tokenize(query)

  list.fold(terms, 0.0, fn(acc, term) {
    let tf = get_term_freq(index, entity, term)
    let df = get_doc_freq(index, term)
    let doc_len = get_doc_len(index, entity)
    let idf_numerator = int.to_float(index.doc_count) -. int.to_float(df) +. 0.5
    let idf_denominator = int.to_float(df) +. 0.5
    let idf =
      float.logarithm(1.0 +. idf_numerator /. idf_denominator)
      |> result.unwrap(0.0)
    let safe_idf = float.max(0.0, idf)
    let tf_float = int.to_float(tf)
    let numerator = tf_float *. { k1 +. 1.0 }
    let avg_dl_safe = case index.avg_doc_len {
      0.0 -> 1.0
      val -> val
    }
    let denominator =
      tf_float
      +. k1
      *. { 1.0 -. b +. b *. { int.to_float(doc_len) /. avg_dl_safe } }

    case denominator {
      0.0 -> acc
      _ -> acc +. safe_idf *. { numerator /. denominator }
    }
  })
}

fn tokenize(text: String) -> List(String) {
  text
  |> string.lowercase()
  |> string.to_graphemes()
  |> list.map(fn(char) {
    case is_alphanumeric(char) {
      True -> char
      False -> " "
    }
  })
  |> string.concat()
  |> string.split(" ")
  |> list.filter(fn(s) { string.length(s) > 0 })
}

fn is_alphanumeric(char: String) -> Bool {
  let code = case string.to_utf_codepoints(char) {
    [cp] -> string.utf_codepoint_to_int(cp)
    _ -> 0
  }
  { code >= 48 && code <= 57 }
  || { code >= 65 && code <= 90 }
  || { code >= 97 && code <= 122 }
}

fn get_term_freq(index: BM25Index, entity: fact.EntityId, term: String) -> Int {
  case dict.get(index.term_freq, term) {
    Ok(entity_map) -> dict.get(entity_map, entity) |> result.unwrap(0)
    Error(_) -> 0
  }
}

fn get_doc_freq(index: BM25Index, term: String) -> Int {
  dict.get(index.doc_freq, term) |> result.unwrap(0)
}

fn get_doc_len(index: BM25Index, entity: fact.EntityId) -> Int {
  dict.get(index.doc_len, entity) |> result.unwrap(0)
}
