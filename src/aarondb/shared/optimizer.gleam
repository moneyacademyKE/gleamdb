import aarondb/fact
import aarondb/shared/ast.{
  type BodyClause, type Part, type Query, Aggregate, Bind, Cognitive, Filter,
  GraphGroupBy, Negative, PageRank, Positive, Query, ShortestPath, Similarity,
  StartsWith, Temporal, Val, Var, Virtual,
}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/set.{type Set}

import gleam/string

/// Optimizes a Query by reordering its where clauses for efficient execution.
/// Rich Hickey alignment: "Query optimization is a pure data transformation."
pub fn optimize(query: Query) -> Query {
  let planned_clauses = plan(query.where)
  Query(..query, where: planned_clauses)
}

pub fn explain(clauses: List(BodyClause)) -> String {
  let planned = plan(clauses)
  list.map(planned, fn(c) { "  - " <> clause_to_string(c) })
  |> list.prepend("Query Plan:")
  |> list.intersperse("\n")
  |> list.fold("", fn(acc, s) { acc <> s })
}

fn plan(clauses: List(BodyClause)) -> List(BodyClause) {
  let #(control, data) = list.partition(clauses, is_control_clause)
  let ordered_data = greedy_reorder(data, set.new())
  list.append(ordered_data, control)
}

fn is_control_clause(clause: BodyClause) -> Bool {
  case clause {
    GraphGroupBy(_) -> True
    _ -> False
  }
}

fn greedy_reorder(
  remaining: List(BodyClause),
  bound_vars: Set(String),
) -> List(BodyClause) {
  case find_best_clause(remaining, bound_vars) {
    Ok(#(best, others)) -> {
      let clause_vars = get_clause_vars(best)
      let next_bound = set.union(bound_vars, clause_vars)
      [best, ..greedy_reorder(others, next_bound)]
    }
    Error(Nil) -> []
  }
}

fn find_best_clause(
  clauses: List(BodyClause),
  bound_vars: Set(String),
) -> Result(#(BodyClause, List(BodyClause)), Nil) {
  let scored = list.map(clauses, fn(c) { #(c, estimate_cost(c, bound_vars)) })
  let sorted = list.sort(scored, fn(a, b) { int.compare(a.1, b.1) })

  case sorted {
    [#(best, _), ..rest] -> Ok(#(best, list.map(rest, fn(pair) { pair.0 })))
    [] -> Error(Nil)
  }
}

fn estimate_cost(clause: BodyClause, bound_vars: Set(String)) -> Int {
  case clause {
    Positive(#(e, _a, v)) -> {
      let e_bound = is_part_bound(e, bound_vars)
      let v_bound = is_part_bound(v, bound_vars)
      case e_bound, v_bound {
        True, True -> 1
        True, False -> 10
        False, True -> 100
        False, False -> 1000
      }
    }
    Negative(_) -> 5000
    Filter(expr) -> {
      let expr_vars = get_expr_vars(expr)
      let all_bound =
        set.fold(expr_vars, True, fn(acc, v) {
          acc && set.contains(bound_vars, v)
        })
      case all_bound {
        True -> 2
        False -> 8000
      }
    }
    Bind(_, _) -> 2
    Aggregate(_, _, _, sub_filter) -> 2000 + list.length(sub_filter) * 100
    Similarity(_, _, _) -> 50
    Temporal(_, _, _, _, _, _) -> 150
    ShortestPath(_, _, _, _, _, _) -> 500
    PageRank(_, _, _, _, _) -> 1000
    Cognitive(_, _, _, _) -> 500
    StartsWith(var, _) -> {
      case set.contains(bound_vars, var) {
        True -> 10
        False -> 50
      }
    }
    Virtual(_, args, _) -> {
      let bound_args = list.filter(args, fn(a) { is_part_bound(a, bound_vars) })
      1000 - list.length(bound_args) * 100
    }
    _ -> 9999
  }
}

fn is_part_bound(part: Part, bound_vars: Set(String)) -> Bool {
  case part {
    Val(_) -> True
    Var(name) -> set.contains(bound_vars, name)
    ast.Uid(_) -> True
    ast.AttrVal(_) -> True
    ast.Lookup(_) -> True
  }
}

fn get_clause_vars(clause: BodyClause) -> Set(String) {
  case clause {
    Positive(#(e, _, v)) -> set.from_list(list.filter_map([e, v], get_var_name))
    Negative(#(e, _, v)) -> set.from_list(list.filter_map([e, v], get_var_name))
    Filter(expr) -> get_expr_vars(expr)
    Bind(var, val) -> {
      let s = case get_var_name(var) {
        Ok(n) -> set.from_list([n])
        Error(_) -> set.new()
      }
      case get_var_name(val) {
        Ok(n) -> set.insert(s, n)
        Error(_) -> s
      }
    }
    Aggregate(var, _, target, filter) -> {
      let sub_vars =
        list.map(filter, get_clause_vars) |> list.fold(set.new(), set.union)
      let s = set.insert(sub_vars, var)
      case get_var_name(target) {
        Ok(n) -> set.insert(s, n)
        Error(_) -> s
      }
    }
    StartsWith(var, _) -> set.from_list([var])
    Similarity(var, target, _) -> {
      let s = set.from_list([var])
      case get_var_name(target) {
        Ok(n) -> set.insert(s, n)
        Error(_) -> s
      }
    }
    Temporal(_, _, _, var, entity, _) -> {
      let s = set.from_list([var])
      case get_var_name(entity) {
        Ok(name) -> set.insert(s, name)
        Error(_) -> s
      }
    }
    Cognitive(concept, context, _, engram_var) -> {
      let s = set.from_list([engram_var])
      let s = case get_var_name(concept) {
        Ok(n) -> set.insert(s, n)
        Error(_) -> s
      }
      case get_var_name(context) {
        Ok(n) -> set.insert(s, n)
        Error(_) -> s
      }
    }
    ShortestPath(from, to, _, path_var, cost_var, _max_depth) -> {
      let s = set.from_list([path_var])
      let s = case cost_var {
        Some(cv) -> set.insert(s, cv)
        None -> s
      }
      let s = case get_var_name(from) {
        Ok(n) -> set.insert(s, n)
        Error(_) -> s
      }
      case get_var_name(to) {
        Ok(n) -> set.insert(s, n)
        Error(_) -> s
      }
    }
    PageRank(entity_var, _, rank_var, _, _) ->
      set.from_list([entity_var, rank_var])
    Virtual(_, args, outputs) -> {
      let arg_vars = list.filter_map(args, get_var_name) |> set.from_list()
      let output_vars = set.from_list(outputs)
      set.union(arg_vars, output_vars)
    }
    _ -> set.new()
  }
}

fn get_var_name(part: Part) -> Result(String, Nil) {
  case part {
    Var(name) -> Ok(name)
    _ -> Error(Nil)
  }
}

fn get_expr_vars(expr: ast.Expression) -> Set(String) {
  case expr {
    ast.Eq(a, b) | ast.Neq(a, b) | ast.Gt(a, b) | ast.Lt(a, b) -> {
      set.from_list(list.filter_map([a, b], get_var_name))
    }
    ast.And(l, r) | ast.Or(l, r) ->
      set.union(get_expr_vars(l), get_expr_vars(r))
  }
}

fn clause_to_string(clause: BodyClause) -> String {
  case clause {
    Positive(#(e, a, v)) ->
      "Positive("
      <> part_to_string(e)
      <> ", "
      <> a
      <> ", "
      <> part_to_string(v)
      <> ")"
    Negative(#(e, a, v)) ->
      "Negative("
      <> part_to_string(e)
      <> ", "
      <> a
      <> ", "
      <> part_to_string(v)
      <> ")"
    Filter(_) -> "Filter(...)"
    Similarity(v, _, _) -> "Similarity(" <> v <> ")"
    Temporal(_, _, _, v, e, _) ->
      "Temporal(" <> v <> ", " <> part_to_string(e) <> ")"
    Cognitive(concept, context, _, var) ->
      "Cognitive(concept="
      <> part_to_string(concept)
      <> ", context="
      <> part_to_string(context)
      <> ", var="
      <> var
      <> ")"
    Virtual(p, args, outputs) ->
      "Virtual("
      <> p
      <> ", count="
      <> int.to_string(list.length(args))
      <> ", outputs="
      <> string.inspect(outputs)
      <> ")"
    ShortestPath(_, _, e, v, _, _) ->
      "ShortestPath(edge=" <> e <> ", var=" <> v <> ")"
    _ -> "OtherClause"
  }
}

fn part_to_string(p: Part) -> String {
  case p {
    Var(n) -> "?" <> n
    Val(v) -> fact.to_string(v)
    ast.Uid(_) -> "UID"
    ast.AttrVal(v) -> v
    ast.Lookup(_) -> "Lookup"
  }
}
