import aarondb/algo/aggregate
import aarondb/algo/cracking
import aarondb/algo/vectorized
import aarondb/engine/cognitive
import aarondb/engine/entity
import aarondb/engine/executor
import aarondb/engine/graph_clauses
import aarondb/engine/morsel
import aarondb/engine/navigator
import aarondb/engine/predicate
import aarondb/engine/planner
import aarondb/engine/retrieval
import aarondb/engine/solver_context
import aarondb/engine/string_clause
import aarondb/engine/traversal
import aarondb/engine/virtual
import aarondb/fact
import aarondb/index
import aarondb/index/ets as ets_index
import aarondb/shared/ast
import aarondb/shared/query_types
import aarondb/shared/state
import aarondb/storage
import aarondb/storage/internal

import gleam/dict.{type Dict}
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/set.{type Set}

// Rule moved to types.gleam to avoid cycle

// Pull types moved to shared/types.gleam to avoid cycles

pub fn run(
  db_state: state.DbState,
  query: ast.Query,
  rules: List(ast.Rule),
  as_of_tx: Option(Int),
  as_of_valid: Option(Int),
) -> query_types.QueryResult {
  let _clauses = query.where
  let as_of_v = case as_of_valid {
    Some(vt) -> Some(vt)
    None -> Some(2_147_483_647)
    // Max Int (v1.9.0 default: inclusive of future valid time)
  }
  let all_rules = list.append(rules, db_state.stored_rules)
  let all_derived = derive_all_facts(db_state, all_rules, as_of_tx, as_of_v)
  let solver =
    solver_context.SolverContext(
      db_state: db_state,
      rules: all_rules,
      derived: all_derived,
      as_of_tx: as_of_tx,
      as_of_valid: as_of_v,
    )
  let initial_context = [dict.new()]

  let plan = planner.build(query)
  let planned_clauses = plan.clauses

  // [Dogfood Learning] Graph Type Safety: check if graph edges are Refs
  list.each(planned_clauses, fn(c) {
    case c {
      ast.PageRank(_, edge, _, _, _)
      | ast.CycleDetect(edge, _)
      | ast.StronglyConnectedComponents(edge, _, _)
      | ast.TopologicalSort(edge, _, _) -> {
        let config = dict.get(db_state.schema, edge)
        case config {
          Ok(conf) if conf.cardinality != fact.Many -> {
            // In a real logger we'd use that, for now print to stdout
            // which is visible in Gswarm logs
            let _ =
              aarondb_io_println(
                "⚠️ Warning: Graph edge '"
                <> edge
                <> "' should be Ref(EntityId) for optimal performance.",
              )
          }
          _ -> Nil
        }
      }
      _ -> Nil
    }
  })

  let execution =
    executor.execute(planned_clauses, initial_context, None, fn(clause, ctx, _) {
      solve_with_context(solver, clause, ctx)
    })

  let rows =
    execution.rows
    |> planner.order_rows(plan.query.order_by)
    |> planner.page_rows(plan.query.offset, plan.query.limit)

  query_types.QueryResult(
    rows: rows |> list.unique(),
    metadata: query_types.QueryMetadata(
      tx_id: as_of_tx,
      valid_time: as_of_valid,
      execution_time_ms: 0,
      index_hits: 0,
      plan: "",
      shard_id: None,
      aggregates: plan.aggregates,
    ),
    updated_columnar_store: execution.store,
  )
}

@external(erlang, "io", "format")
fn aarondb_io_println(x: String) -> Nil

fn derive_all_facts(
  db_state: state.DbState,
  rules: List(ast.Rule),
  as_of_tx: Option(Int),
  as_of_valid: Option(Int),
) -> Set(fact.Datom) {
  do_derive(db_state, rules, as_of_tx, as_of_valid, set.new())
}

fn do_derive(
  db_state: state.DbState,
  rules: List(ast.Rule),
  as_of_tx: Option(Int),
  as_of_valid: Option(Int),
  derived: Set(fact.Datom),
) -> Set(fact.Datom) {
  let initial_new = derived
  do_derive_recursive(
    db_state,
    rules,
    as_of_tx,
    as_of_valid,
    derived,
    initial_new,
    True,
  )
}

fn do_derive_recursive(
  db_state: state.DbState,
  rules: List(ast.Rule),
  as_of_tx: Option(Int),
  as_of_valid: Option(Int),
  all_derived: Set(fact.Datom),
  last_new_derived: Set(fact.Datom),
  first_run: Bool,
) -> Set(fact.Datom) {
  case !first_run && set.size(last_new_derived) == 0 {
    True -> all_derived
    False -> {
      let next_new =
        list.fold(rules, set.new(), fn(acc, r) {
          // Semi-Naive Evaluation:
          // For each rule, we only want results that involve at least one fact 
          // from 'last_new_derived'. This avoids re-discovering the same facts.
          let #(results, _store) =
            solve_rule_body_semi_naive(
              db_state,
              r.body,
              all_derived,
              last_new_derived,
              as_of_tx,
              as_of_valid,
            )

          list.fold(results, acc, fn(inner_acc, ctx) {
            let e = resolve_part_optional(r.head.0, ctx)
            let v = resolve_part_optional(r.head.2, ctx)
            case e, v {
              Some(fact.Ref(fact.EntityId(eid_val))), Some(val) -> {
                let d =
                  fact.Datom(
                    entity: fact.EntityId(eid_val),
                    attribute: r.head.1,
                    value: val,
                    tx: 0,
                    tx_index: 0,
                    valid_time: 0,
                    operation: fact.Assert,
                  )
                case set.contains(all_derived, d) {
                  True -> inner_acc
                  False -> set.insert(inner_acc, d)
                }
              }
              Some(fact.Int(eid_val)), Some(val) -> {
                let d =
                  fact.Datom(
                    entity: fact.EntityId(eid_val),
                    attribute: r.head.1,
                    value: val,
                    tx: 0,
                    tx_index: 0,
                    valid_time: 0,
                    operation: fact.Assert,
                  )
                case set.contains(all_derived, d) {
                  True -> inner_acc
                  False -> set.insert(inner_acc, d)
                }
              }
              _, _ -> inner_acc
            }
          })
        })

      case set.size(next_new) == 0 {
        True -> all_derived
        False -> {
          let next_all = set.union(all_derived, next_new)
          do_derive_recursive(
            db_state,
            rules,
            as_of_tx,
            as_of_valid,
            next_all,
            next_new,
            False,
          )
        }
      }
    }
  }
}

fn solve_rule_body_semi_naive(
  db_state: state.DbState,
  body: List(ast.BodyClause),
  all_derived: Set(fact.Datom),
  _delta: Set(fact.Datom),
  as_of_tx: Option(Int),
  as_of_valid: Option(Int),
) -> #(
  List(Dict(String, fact.Value)),
  Option(Dict(String, List(internal.StorageChunk))),
) {
  list.fold(body, #([dict.new()], None), fn(acc, clause_i) {
    let #(ctxs, current_store) = acc
    list.fold(ctxs, #([], current_store), fn(inner_acc, ctx) {
      let #(acc_ctxs, acc_store) = inner_acc
      let #(new_ctxs, clause_store) =
        solve_clause_with_derived(
          db_state,
          clause_i,
          ctx,
          all_derived,
          as_of_tx,
          as_of_valid,
        )
      #(
        list.append(acc_ctxs, new_ctxs),
        merge_optional_stores(acc_store, clause_store),
      )
    })
  })
}

fn merge_optional_stores(
  s1: Option(Dict(String, List(internal.StorageChunk))),
  s2: Option(Dict(String, List(internal.StorageChunk))),
) -> Option(Dict(String, List(internal.StorageChunk))) {
  case s1, s2 {
    Some(m1), Some(m2) -> Some(dict.merge(m1, m2))
    Some(_), None -> s1
    None, Some(_) -> s2
    None, None -> None
  }
}

fn solve_clause(
  db_state: state.DbState,
  clause: ast.BodyClause,
  ctx: Dict(String, fact.Value),
  rules: List(ast.Rule),
  as_of_tx: Option(Int),
  as_of_valid: Option(Int),
) -> #(
  List(Dict(String, fact.Value)),
  Option(Dict(String, List(internal.StorageChunk))),
) {
  case clause {
    ast.Positive(c) -> {
      let #(res, store) =
        solve_positive_with_state(db_state, c, ctx, as_of_tx, as_of_valid)
      #(res, store)
    }
    ast.Negative(c) -> #(
      solve_negative(db_state, c, ctx, as_of_tx, as_of_valid),
      None,
    )
    ast.Aggregate(var, func, target_p, filter_clauses) -> {
      let target_var = case target_p {
        ast.Var(n) -> n
        _ -> ""
      }
      solve_aggregate(
        ctx,
        var,
        func,
        target_var,
        db_state,
        filter_clauses,
        rules,
        as_of_tx,
        as_of_valid,
      )
    }
    ast.Similarity(variable: var, target: target_p, threshold: threshold) -> {
      let vec = case resolve_part(target_p, ctx) {
        Some(fact.Vec(vs)) -> vs
        Some(fact.List(vs)) ->
          list.filter_map(vs, fn(v) {
            case v {
              fact.Float(f) -> Ok(f)
              _ -> Error(Nil)
            }
          })
        _ -> []
      }
      #(
        retrieval.similarity(
          db_state,
          var,
          vec,
          threshold,
          ctx,
          as_of_tx,
          as_of_valid,
        ),
        None,
      )
    }
    ast.SimilarityEntity(variable: var, target: target_p, threshold: threshold) -> {
      let vec = case resolve_part(target_p, ctx) {
        Some(fact.Vec(vs)) -> vs
        Some(fact.List(vs)) ->
          list.filter_map(vs, fn(v) {
            case v {
              fact.Float(f) -> Ok(f)
              _ -> Error(Nil)
            }
          })
        _ -> []
      }
      #(
        retrieval.similarity_entity(
          db_state,
          var,
          vec,
          threshold,
          ctx,
        ),
        None,
      )
    }
    ast.Cognitive(concept, context, threshold, engram_var) -> #(
      solve_cognitive(
        db_state,
        concept,
        context,
        threshold,
        engram_var,
        ctx,
        as_of_tx,
        as_of_valid,
      ),
      None,
    )
    ast.CustomIndex(variable: var, index_name: name, query: q, threshold: t) -> {
      let state_q = case q {
        ast.TextQuery(txt) -> state.TextQuery(txt)
        ast.NumericRange(min, max) -> state.NumericRange(min, max)
        ast.Custom(data) -> state.Custom(data)
      }
      #(
        retrieval.custom_index(
          db_state,
          var,
          name,
          state_q,
          t,
          ctx,
          as_of_tx,
          as_of_valid,
        ),
        None,
      )
    }
    ast.Filter(expr) -> {
          let compiled_pred = predicate.compile(expr)
      case compiled_pred(ctx) {
        True -> #([ctx], None)
        False -> #([], None)
      }
    }
    ast.Bind(var_p, val_p) -> {
      let var_name = case var_p {
        ast.Var(n) -> n
        _ -> ""
      }
      let val = resolve_part(val_p, ctx) |> option.unwrap(fact.Int(0))
      #([dict.insert(ctx, var_name, val)], None)
    }
    ast.Temporal(type_, time, op, var, entity, clauses) -> #(
      solve_temporal(db_state, type_, time, op, var, entity, clauses, ctx),
      None,
    )
    ast.ShortestPath(from, to, edge, path_var, cost_var, max_depth) -> #(
      graph_clauses.shortest_path(
        db_state,
        from,
        to,
        edge,
        path_var,
        cost_var,
        max_depth,
        ctx,
      ),
      None,
    )
    ast.PageRank(entity_var, edge, rank_var, damping, iterations) -> #(
      graph_clauses.pagerank(
        db_state,
        entity_var,
        edge,
        rank_var,
        damping,
        iterations,
        ctx,
      ),
      None,
    )
    ast.Virtual(pred, args, outputs) -> #(
      virtual.solve(db_state, pred, args, outputs, ctx),
      None,
    )
    ast.Reachable(from, edge, node_var) -> #(
      graph_clauses.reachable(db_state, from, edge, node_var, ctx),
      None,
    )
    ast.ConnectedComponents(edge, entity_var, component_var) -> #(
      graph_clauses.connected_components(db_state, edge, entity_var, component_var, ctx),
      None,
    )
    ast.Neighbors(from, edge, depth, node_var) -> #(
      graph_clauses.neighbors(db_state, from, edge, depth, node_var, ctx),
      None,
    )
    ast.CycleDetect(edge, cycle_var) -> #(
      graph_clauses.cycle_detect(db_state, edge, cycle_var, ctx),
      None,
    )
    ast.BetweennessCentrality(edge, entity_var, score_var) -> #(
      graph_clauses.betweenness(db_state, edge, entity_var, score_var, ctx),
      None,
    )
    ast.TopologicalSort(edge, entity_var, order_var) -> #(
      graph_clauses.topological_sort(db_state, edge, entity_var, order_var, ctx),
      None,
    )
    ast.StronglyConnectedComponents(edge, entity_var, component_var) -> #(
      graph_clauses.strongly_connected(db_state, edge, entity_var, component_var, ctx),
      None,
    )
    ast.StartsWith(var, prefix) -> #(
      string_clause.starts_with(db_state, var, prefix, ctx),
      None,
    )
    ast.Pull(var, entity, pattern) -> {
      case resolve_part(entity, ctx) {
        Some(fact.Ref(eid)) -> {
          let res = entity.pull(db_state, eid, pattern)
          #([dict.insert(ctx, var, entity.pull_result_to_value(res))], None)
        }
        Some(fact.Int(eid_int)) -> {
          let res = entity.pull(db_state, fact.EntityId(eid_int), pattern)
          #([dict.insert(ctx, var, entity.pull_result_to_value(res))], None)
        }
        _ -> #([], None)
      }
    }
    _ -> #([ctx], None)
  }
}

fn solve_with_context(
  solver: solver_context.SolverContext,
  clause: ast.BodyClause,
  ctx: Dict(String, fact.Value),
) -> #(
  List(Dict(String, fact.Value)),
  Option(Dict(String, List(internal.StorageChunk))),
) {
  solve_clause_with_derived(
    solver.db_state,
    clause,
    ctx,
    solver.derived,
    solver.as_of_tx,
    solver.as_of_valid,
  )
}

fn solve_positive_with_state(
  db_state: state.DbState,
  triple: ast.Clause,
  ctx: Dict(String, fact.Value),
  as_of_tx: Option(Int),
  as_of_valid: Option(Int),
) -> #(
  List(Dict(String, fact.Value)),
  Option(Dict(String, List(internal.StorageChunk))),
) {
  let #(e_p, attr, v_p) = triple
  let e_val = resolve_part(e_p, ctx)
  let v_val = resolve_part(v_p, ctx)

  // 1. Check if we should use Cracking (Columnar layout + range query)
  // For now, we'll implement JIT partitioning if it's columnar.
  let #(base_datoms, new_store) = case dict.get(db_state.columnar_store, attr) {
    Ok(chunks) -> {
      // If we have a constant value v_val, we can refine the index
      let updated_chunks = case v_val {
        Some(v) -> {
          list.map(chunks, fn(chunk) {
            let new_values = cracking.partition(chunk.values, v)
            internal.StorageChunk(..chunk, values: new_values)
          })
        }
        None -> chunks
      }

      // Convert chunks back to datoms for the solver (standard path)
      // Future: specialized columnar solver
      let datoms = vectorized.chunks_to_datoms(updated_chunks)
      #(datoms, Some(dict.from_list([#(attr, updated_chunks)])))
    }
    Error(_) -> {
      let adapter_datoms = case storage.query_datoms(db_state.adapter, triple) {
        Ok(datoms) if datoms != [] -> datoms
        _ -> []
      }

      let base_datoms = case adapter_datoms {
        [] -> {
          let memory_datoms = case e_val, v_val {
            Some(fact.Ref(fact.EntityId(e))), Some(v) ->
              index.get_datoms_by_entity_attr_val(
                db_state.eavt,
                fact.EntityId(e),
                attr,
                v,
              )
            Some(fact.Ref(fact.EntityId(e))), None ->
              index.get_datoms_by_entity_attr(
                db_state.eavt,
                fact.EntityId(e),
                attr,
              )
            Some(fact.Int(e)), Some(v) ->
              index.get_datoms_by_entity_attr_val(
                db_state.eavt,
                fact.EntityId(e),
                attr,
                v,
              )
            Some(fact.Int(e)), None ->
              index.get_datoms_by_entity_attr(
                db_state.eavt,
                fact.EntityId(e),
                attr,
              )
            None, Some(v) -> index.get_datoms_by_val(db_state.aevt, attr, v)
            None, None -> index.get_all_datoms_for_attr(db_state.eavt, attr)
            Some(_), _ -> []
          }

          let disk_datoms = case db_state.ets_name {
            Some(name) -> {
              case e_val, v_val {
                Some(fact.Ref(fact.EntityId(e))), Some(v) ->
                  ets_index.lookup_datoms(name <> "_eavt", fact.EntityId(e))
                  |> list.filter(fn(d: fact.Datom) {
                    d.attribute == attr && d.value == v
                  })
                Some(fact.Ref(fact.EntityId(e))), None ->
                  ets_index.lookup_datoms(name <> "_eavt", fact.EntityId(e))
                  |> list.filter(fn(d: fact.Datom) { d.attribute == attr })
                Some(fact.Int(e)), Some(v) ->
                  ets_index.lookup_datoms(name <> "_eavt", fact.EntityId(e))
                  |> list.filter(fn(d: fact.Datom) {
                    d.attribute == attr && d.value == v
                  })
                Some(fact.Int(e)), None ->
                  ets_index.lookup_datoms(name <> "_eavt", fact.EntityId(e))
                  |> list.filter(fn(d: fact.Datom) { d.attribute == attr })
                None, Some(v) ->
                  ets_index.lookup_datoms(name <> "_aevt", attr)
                  |> list.filter(fn(d: fact.Datom) { d.value == v })
                None, None -> ets_index.lookup_datoms(name <> "_aevt", attr)
                Some(_), _ -> []
              }
            }
            None -> []
          }

          list.append(memory_datoms, disk_datoms)
        }
        _ -> adapter_datoms
      }
      #(base_datoms, None)
    }
  }

  let active =
    base_datoms
    |> entity.filter_by_time(as_of_tx, as_of_valid)
    |> entity.filter_active(db_state)

  // Morsel-driven execution:
  // If we have contexts to evaluate against, run them through morsel workers
  // Chunk size is determined by config, defaulting to 1000 if not set
  let results =
    morsel.execute_morsels(active, [ctx], e_p, v_p, db_state.config.batch_size)

  #(results, new_store)
}

fn solve_positive(
  db_state: state.DbState,
  triple: ast.Clause,
  ctx: Dict(String, fact.Value),
  as_of_tx: Option(Int),
  as_of_valid: Option(Int),
) -> List(Dict(String, fact.Value)) {
  solve_positive_with_state(db_state, triple, ctx, as_of_tx, as_of_valid).0
}

fn solve_negative(
  db_state: state.DbState,
  triple: ast.Clause,
  ctx: Dict(String, fact.Value),
  as_of_tx: Option(Int),
  as_of_valid: Option(Int),
) -> List(Dict(String, fact.Value)) {
  case solve_positive(db_state, triple, ctx, as_of_tx, as_of_valid) {
    [] -> [ctx]
    _ -> []
  }
}

fn solve_clause_with_derived(
  db_state: state.DbState,
  clause: ast.BodyClause,
  ctx: Dict(String, fact.Value),
  all_derived: Set(fact.Datom),
  as_of_tx: Option(Int),
  as_of_valid: Option(Int),
) -> #(
  List(Dict(String, fact.Value)),
  Option(Dict(String, List(internal.StorageChunk))),
) {
  case clause {
    ast.Positive(trip) -> #(
      solve_triple_with_derived(
        db_state,
        trip,
        ctx,
        all_derived,
        as_of_tx,
        as_of_valid,
      ),
      None,
    )
    ast.Negative(trip) -> {
      case
        solve_triple_with_derived(
          db_state,
          trip,
          ctx,
          all_derived,
          as_of_tx,
          as_of_valid,
        )
      {
        [] -> #([ctx], None)
        _ -> #([], None)
      }
    }
    _ ->
      solve_clause(
        db_state,
        clause,
        ctx,
        db_state.stored_rules,
        as_of_tx,
        as_of_valid,
      )
  }
}

fn solve_triple_with_derived(
  db_state: state.DbState,
  triple: ast.Clause,
  ctx: Dict(String, fact.Value),
  derived: Set(fact.Datom),
  as_of_tx: Option(Int),
  as_of_valid: Option(Int),
) -> List(Dict(String, fact.Value)) {
  let #(e_p, attr, v_p) = triple
  let e_val = resolve_part(e_p, ctx)
  let v_val = resolve_part(v_p, ctx)

  let base_datoms = case db_state.ets_name {
    Some(name) -> {
      case e_val, v_val {
        Some(fact.Ref(fact.EntityId(e))), Some(v) -> {
          ets_index.lookup_datoms(name <> "_eavt", fact.EntityId(e))
          |> list.filter(fn(d: fact.Datom) {
            d.attribute == attr && d.value == v
          })
        }
        Some(fact.Ref(fact.EntityId(e))), None -> {
          ets_index.lookup_datoms(name <> "_eavt", fact.EntityId(e))
          |> list.filter(fn(d: fact.Datom) { d.attribute == attr })
        }
        Some(fact.Int(e)), Some(v) -> {
          ets_index.lookup_datoms(name <> "_eavt", fact.EntityId(e))
          |> list.filter(fn(d: fact.Datom) {
            d.attribute == attr && d.value == v
          })
        }
        Some(fact.Int(e)), None -> {
          ets_index.lookup_datoms(name <> "_eavt", fact.EntityId(e))
          |> list.filter(fn(d: fact.Datom) { d.attribute == attr })
        }
        None, Some(v) -> {
          ets_index.lookup_datoms(name <> "_aevt", attr)
          |> list.filter(fn(d: fact.Datom) { d.value == v })
        }
        None, None -> {
          ets_index.lookup_datoms(name <> "_aevt", attr)
        }
        Some(_), _ -> []
      }
    }
    None -> {
      case e_val, v_val {
        Some(fact.Ref(fact.EntityId(e))), Some(v) ->
          index.get_datoms_by_entity_attr_val(
            db_state.eavt,
            fact.EntityId(e),
            attr,
            v,
          )
        Some(fact.Ref(fact.EntityId(e))), None ->
          index.get_datoms_by_entity_attr(db_state.eavt, fact.EntityId(e), attr)
        Some(fact.Int(e)), Some(v) ->
          index.get_datoms_by_entity_attr_val(
            db_state.eavt,
            fact.EntityId(e),
            attr,
            v,
          )
        Some(fact.Int(e)), None ->
          index.get_datoms_by_entity_attr(db_state.eavt, fact.EntityId(e), attr)
        None, Some(v) -> index.get_datoms_by_val(db_state.aevt, attr, v)
        None, None -> index.get_all_datoms_for_attr(db_state.eavt, attr)
        Some(_), _ -> []
      }
    }
  }

  let derived_datoms =
    set.to_list(derived)
    |> list.filter(fn(d) {
      let attr_match = d.attribute == attr
      let e_match = case e_val {
        Some(fact.Ref(fact.EntityId(e))) -> {
          let fact.EntityId(eid_int) = d.entity
          eid_int == e
        }
        Some(fact.Int(e)) -> {
          let fact.EntityId(eid_int) = d.entity
          eid_int == e
        }
        _ -> True
      }
      let v_match = case v_val {
        Some(v) -> d.value == v
        _ -> True
      }
      attr_match && e_match && v_match
    })

  let all = list.append(base_datoms, derived_datoms)

  let active =
    all
    |> entity.filter_by_time(as_of_tx, as_of_valid)
    |> entity.filter_active(db_state)
    |> list.filter(fn(d) { d.operation == fact.Assert })

  list.map(active, fn(d: fact.Datom) {
    let b = ctx
    let b = case e_p {
      ast.Var(n) -> {
        let id_val = fact.Ref(d.entity)
        dict.insert(b, n, id_val)
      }
      _ -> b
    }
    let b = case v_p {
      ast.Var(n) -> dict.insert(b, n, d.value)
      _ -> b
    }
    b
  })
}

fn resolve_part(
  part: ast.Part,
  ctx: Dict(String, fact.Value),
) -> Option(fact.Value) {
  case part {
    ast.Var(name) -> option.from_result(dict.get(ctx, name))
    ast.Val(val) -> Some(val)
    ast.Uid(uid) -> Some(fact.Ref(uid))
    ast.AttrVal(s) -> Some(fact.Str(s))
    ast.Lookup(#(_, val)) -> Some(val)
  }
}

fn resolve_part_optional(
  part: ast.Part,
  ctx: Dict(String, fact.Value),
) -> Option(fact.Value) {
  case part {
    ast.Var(name) -> option.from_result(dict.get(ctx, name))
    ast.Val(val) -> Some(val)
    ast.Uid(uid) -> Some(fact.Ref(uid))
    ast.AttrVal(s) -> Some(fact.Str(s))
    ast.Lookup(#(_, val)) -> Some(val)
  }
}

fn do_solve_clauses(
  solver: solver_context.SolverContext,
  clauses: List(ast.BodyClause),
  contexts: List(Dict(String, fact.Value)),
  initial_store: Option(Dict(String, List(internal.StorageChunk))),
) -> #(
  List(Dict(String, fact.Value)),
  Option(Dict(String, List(internal.StorageChunk))),
) {
  case clauses {
    [] -> #(contexts, initial_store)
    [first, ..rest] -> {
      let #(next_contexts, next_store) = case
        list.length(contexts) > solver.db_state.config.parallel_threshold
      {
        True -> {
          // Parallel path
          let subject = process.new_subject()
          process.spawn(fn() {
            let res =
              list.fold(contexts, #([], initial_store), fn(acc, ctx) {
                let #(acc_ctxs, acc_store) = acc
                let #(new_ctxs, clause_store) =
                  solve_clause(
                    solver.db_state,
                    first,
                    ctx,
                    solver.rules,
                    solver.as_of_tx,
                    solver.as_of_valid,
                  )
                #(
                  list.append(acc_ctxs, new_ctxs),
                  merge_optional_stores(acc_store, clause_store),
                )
              })
            process.send(subject, res)
          })
          let assert Ok(res) = process.receive(subject, 60_000)
          res
        }
        False -> {
          list.fold(contexts, #([], initial_store), fn(acc, ctx) {
            let #(acc_ctxs, acc_store) = acc
            let #(new_ctxs, clause_store) =
              solve_clause(
                solver.db_state,
                first,
                ctx,
                solver.rules,
                solver.as_of_tx,
                solver.as_of_valid,
              )
            #(
              list.append(acc_ctxs, new_ctxs),
              merge_optional_stores(acc_store, clause_store),
            )
          })
        }
      }
      do_solve_clauses(
        solver,
        rest,
        next_contexts,
        next_store,
      )
    }
  }
}

fn solve_aggregate(
  ctx: Dict(String, fact.Value),
  var: String,
  func: ast.AggFunc,
  target_var: String,
  db_state: state.DbState,
  clauses: List(ast.BodyClause),
  rules: List(ast.Rule),
  as_of_tx: Option(Int),
  as_of_valid: Option(Int),
) -> #(
  List(Dict(String, fact.Value)),
  Option(Dict(String, List(internal.StorageChunk))),
) {
  // Phase 55: HTAP Optimized Aggregate
  let config =
    dict.get(db_state.schema, target_var)
    |> result.unwrap(fact.AttributeConfig(
      unique: False,
      component: False,
      retention: fact.All,
      cardinality: fact.Many,
      check: None,
      composite_group: None,
      layout: fact.Row,
      tier: fact.Memory,
      eviction: fact.AlwaysInMemory,
    ))

  case config.layout, clauses {
    fact.Columnar, filters -> {
      // Optimized Columnar Aggregate
      let chunks =
        dict.get(db_state.columnar_store, target_var) |> result.unwrap([])

      // Phase 56: JIT Cracking
      // Search for cracking candidates in filters
      let cracking_pivots =
        list.filter_map(filters, fn(c) {
          case c {
            ast.Filter(ast.Gt(ast.Var(v), ast.Val(p))) if v == target_var ->
              Ok(p)
            ast.Filter(ast.Lt(ast.Var(v), ast.Val(p))) if v == target_var ->
              Ok(p)
            _ -> Error(Nil)
          }
        })

      let #(updated_chunks, was_cracked) = case cracking_pivots {
        [pivot, ..] -> {
          let nc = list.map(chunks, fn(c) { cracking.crack_chunk(c, pivot) })
          #(nc, True)
        }
        _ -> #(chunks, False)
      }

      // Calculate Aggregate
      let agg_val = case func {
        ast.Sum ->
          fact.Float(
            list.fold(updated_chunks, 0.0, fn(acc, c) {
              acc +. vectorized.sum_column(c)
            }),
          )
        ast.Avg -> {
          let total_sum =
            list.fold(updated_chunks, 0.0, fn(acc, c) {
              acc +. vectorized.sum_column(c)
            })
          let total_count =
            list.fold(updated_chunks, 0, fn(acc, c) {
              acc + vectorized.count_node(c.values)
            })
          case total_count {
            0 -> fact.Float(0.0)
            _ -> fact.Float(total_sum /. int.to_float(total_count))
          }
        }
        _ -> {
          let target_values =
            get_aggregate_values_row_based(
              solver_context.SolverContext(
                db_state: db_state,
                rules: rules,
                derived: set.new(),
                as_of_tx: as_of_tx,
                as_of_valid: as_of_valid,
              ),
              clauses,
              ctx,
              target_var,
            )
          case aggregate.aggregate(target_values, func) {
            Ok(val) -> val
            Error(_) -> fact.Int(0)
          }
        }
      }

      // In this Phase 56 MVP, we only support cracking on aggregates without complex join-filters
      // If there are other filters, we might still need to fallback or combine.
      // For now, if was_cracked, we note the updated state.

      let res_ctx = [dict.insert(ctx, var, agg_val)]
      let updated_store = case was_cracked {
        True -> Some(dict.from_list([#(target_var, updated_chunks)]))
        False -> None
      }
      #(res_ctx, updated_store)
    }
    _, _ -> {
      // Row-based or with filters
      let target_values =
        get_aggregate_values_row_based(
          solver_context.SolverContext(
            db_state: db_state,
            rules: rules,
            derived: set.new(),
            as_of_tx: as_of_tx,
            as_of_valid: as_of_valid,
          ),
          clauses,
          ctx,
          target_var,
        )
      case aggregate.aggregate(target_values, func) {
        Ok(val) -> #([dict.insert(ctx, var, val)], None)
        Error(_) -> #([], None)
      }
    }
  }
}

fn get_aggregate_values_row_based(
  solver: solver_context.SolverContext,
  clauses: List(ast.BodyClause),
  ctx: Dict(String, fact.Value),
  target_var: String,
) -> List(fact.Value) {
  let #(sub_results, _store) = case clauses {
    [] -> #([ctx], None)
    _ ->
      do_solve_clauses(
        solver,
        clauses,
        [ctx],
        None,
      )
  }

  list.filter_map(sub_results, fn(res) { dict.get(res, target_var) })
}

pub fn entity_history(
  db_state: state.DbState,
  eid: fact.EntityId,
) -> List(fact.Datom) {
  entity.entity_history(db_state, eid)
}

pub fn pull(
  db_state: state.DbState,
  eid: fact.EntityId,
  pattern: ast.PullPattern,
) -> query_types.PullResult {
  entity.pull(db_state, eid, pattern)
}

pub fn pull_result_to_value(res: query_types.PullResult) -> fact.Value {
  entity.pull_result_to_value(res)
}

pub fn traverse(
  db_state: state.DbState,
  start_id: Int,
  expr: query_types.TraversalExpr,
  max_depth: Int,
) -> Result(List(fact.Value), String) {
  traversal.traverse(db_state, start_id, expr, max_depth)
}

fn solve_temporal(
  db_state: state.DbState,
  type_: ast.TemporalType,
  time: Int,
  op: ast.TemporalOp,
  variable: String,
  entity_p: ast.Part,
  clauses: List(ast.BodyClause),
  ctx: Dict(String, fact.Value),
) -> List(Dict(String, fact.Value)) {
  let _e_val = resolve_part(entity_p, ctx)

  let as_of_tx = case type_ {
    ast.Tx -> {
      case op {
        ast.At -> Some(time)
        ast.Since -> Some(time)
        // Placeholder for more complex interval logic
        ast.Until -> Some(time)
        _ -> None
      }
    }
    _ -> None
  }

  let as_of_valid = case type_ {
    ast.Valid -> {
      case op {
        ast.At -> Some(time)
        ast.Since -> Some(time)
        ast.Until -> Some(time)
        _ -> None
      }
    }
    _ -> None
  }

  // Solve the nested clauses with the temporal coordinates
  let initial_context = [ctx]
  let #(rows, _) =
    list.fold(clauses, #(initial_context, None), fn(acc, clause) {
      let #(contexts, current_store) = acc
      list.fold(contexts, #([], current_store), fn(inner_acc, c) {
        let #(acc_ctxs, acc_store) = inner_acc
        let #(new_ctxs, clause_store) =
          solve_clause_with_derived(
            db_state,
            clause,
            c,
            set.new(),
            // No derived facts for nested temporal yet
            as_of_tx,
            as_of_valid,
          )
        #(
          list.append(acc_ctxs, new_ctxs),
          merge_optional_stores(acc_store, clause_store),
        )
      })
    })

  // Bind the temporal coordinate to the variable if requested
  list.map(rows, fn(r) { dict.insert(r, variable, fact.Int(time)) })
}

// `search_prefix` traverses the tree and collects values.
// In `art.gleam`, `collect_all_values` returns `List(fact.EntityId)`.
// It doesn't yield the implementation keys (the actual strings).

// Issue: The current ART implementation indexes Value -> EntityId.
// It efficiently finds Entities.
// But `StartsWith(var, "foo")` binds `var` to the *Value* string?
// Typically `var` is a Value in Datalog.

// If the query is:
// `Fact(e, "name", name), StartsWith(name, "Al")`
// We can use ART to find all Entities `e` where "name" starts with "Al".
// But `StartsWith` is a filter on `name`.

// If `name` is unbound, `StartsWith` acts as a generator?
// Infinite generator if not restricted?
// Usually `StartsWith` is used as a constraint on an existing bound variable or an attribute lookup.

// If we want to use ART for `StartsWith`, we need to iterate the ART keys.
// The current `art.gleam` `search_prefix` returns EntityIds, which means it found values matching.
// But it loses the actual value string.
// To bind `name` to "Alice", "Alan", etc., we need the keys from ART.

// OPTIMIZATION:
// For now, let's implement `StartsWith` as a filter only (requires bound variable).
// AND if we want to support efficient lookup, we'd need a `search_prefix_keys` in ART.
// Let's stick to Filter behavior for now, and maybe generator if simple.

// Wait, if I want to use the index, I should probably expose `search_prefix_keys`.
// Let's implement it as a Filter for now to be safe and correct.
pub fn diff(
  db_state: state.DbState,
  from_tx: Int,
  to_tx: Int,
) -> List(fact.Datom) {
  index.get_all_datoms(db_state.eavt)
  |> list.filter(fn(d) { d.tx > from_tx && d.tx <= to_tx })
}

pub fn explain(clauses: List(ast.BodyClause)) -> String {
  navigator.explain(clauses)
}

pub fn filter_by_time(
  datoms: List(fact.Datom),
  tx_limit: Option(Int),
  valid_limit: Option(Int),
) -> List(fact.Datom) {
  datoms
  |> list.filter(fn(d) {
    let tx_ok = case tx_limit {
      Some(tx) -> d.tx <= tx
      None -> True
    }
    let valid_ok = case valid_limit {
      Some(vt) -> d.valid_time <= vt
      None -> True
    }
    tx_ok && valid_ok
  })
}

pub fn solve_cognitive(
  db_state: state.DbState,
  concept: ast.Part,
  context: ast.Part,
  threshold: Float,
  engram_var: String,
  ctx: Dict(String, fact.Value),
  as_of_tx: Option(Int),
  as_of_valid: Option(Int),
) -> List(Dict(String, fact.Value)) {
  cognitive.solve(
    db_state,
    concept,
    context,
    threshold,
    engram_var,
    ctx,
    as_of_tx,
    as_of_valid,
  )
}
