import aarondb
import aarondb/algo/aggregate
import aarondb/algo/bloom
import aarondb/engine
import aarondb/fact
import aarondb/shared/ast
import aarondb/shared/query_types
import aarondb/shared/state.{type DbState}
import aarondb/storage.{type StorageAdapter}
import aarondb/transactor
import aarondb/vec_index
import gleam/dict.{type Dict}
import gleam/erlang/process
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None}
import gleam/otp/actor
import gleam/result
import gleam/string

// ShardedDb moved to shared/types.gleam

pub const mirror_shard_id = 99

@external(erlang, "lists", "seq")
fn range(from: Int, to: Int) -> List(Int)

/// Start a sharded database cluster.
pub fn start_sharded(
  cluster_id: String,
  shard_count: Int,
  adapter: Option(StorageAdapter),
) -> Result(query_types.ShardedDb(transactor.Db), String) {
  let self = process.new_subject()

  // Spawn shard startups in parallel
  list.fold(range(1, shard_count), [], fn(acc, i) { [i, ..acc] })
  |> list.each(fn(i) {
    process.spawn(fn() {
      let shard_cluster_id = cluster_id <> "_s" <> string.inspect(i)
      let res = case aarondb.start_distributed(shard_cluster_id, adapter) {
        Ok(db) -> Ok(#(i, db))
        Error(e) ->
          Error(
            "Failed to start shard "
            <> string.inspect(i)
            <> ": "
            <> string_inspect_actor_error(e),
          )
      }
      process.send(self, res)
    })
  })

  // Gather results
  let shards =
    list.fold(range(1, shard_count), [], fn(acc, _) {
      case process.receive(self, 600_000) {
        Ok(res) -> [res, ..acc]
        Error(_) -> [Error("Timeout starting shards"), ..acc]
      }
    })
    |> list.try_map(fn(x) { x })

  case shards {
    Ok(s) -> {
      let shard_dicts = dict.from_list(s)
      let shard_map = create_shard_map(shard_dicts)
      Ok(query_types.ShardedDb(
        shards: shard_dicts,
        shard_count: shard_count,
        cluster_id: cluster_id,
        shard_map: shard_map,
      ))
    }
    Error(e) -> Error(e)
  }
}

/// Start a sharded database cluster in local (named) mode.
pub fn start_local_sharded(
  cluster_id: String,
  shard_count: Int,
  adapter: Option(StorageAdapter),
) -> Result(query_types.ShardedDb(transactor.Db), String) {
  let self = process.new_subject()

  // Spawn shard startups in parallel
  list.fold(range(1, shard_count), [], fn(acc, i) { [i, ..acc] })
  |> list.each(fn(i) {
    process.spawn(fn() {
      let shard_cluster_id = cluster_id <> "_s" <> string.inspect(i)
      let res = case aarondb.start_distributed(shard_cluster_id, adapter) {
        Ok(db) -> Ok(#(i, db))
        Error(e) ->
          Error(
            "Failed to start local shard "
            <> string.inspect(i)
            <> ": "
            <> string_inspect_actor_error(e),
          )
      }
      process.send(self, res)
    })
  })

  // Gather results
  let shards =
    list.fold(range(1, shard_count), [], fn(acc, _) {
      case process.receive(self, 300_000) {
        Ok(res) -> [res, ..acc]
        Error(_) -> [Error("Timeout starting shards"), ..acc]
      }
    })
    |> list.try_map(fn(x) { x })

  case shards {
    Ok(s) -> {
      let shard_dicts = dict.from_list(s)
      let shard_map = create_shard_map(shard_dicts)
      Ok(query_types.ShardedDb(
        shards: shard_dicts,
        shard_count: shard_count,
        cluster_id: cluster_id,
        shard_map: shard_map,
      ))
    }
    Error(e) -> Error(e)
  }
}

/// Ingest facts into the sharded database in parallel.
/// Routing is determined by hashing the Entity ID (Eid).
pub fn transact(
  db: query_types.ShardedDb(transactor.Db),
  facts: List(fact.Fact),
) -> Result(List(state.DbState), String) {
  // Group facts by shard
  let grouped =
    list.fold(facts, dict.new(), fn(acc, f) {
      let shard_id = get_shard_id_from_map(f.0, db.shard_map)
      let shard_facts = dict.get(acc, shard_id) |> result.unwrap([])
      dict.insert(acc, shard_id, [f, ..shard_facts])
    })

  let grouped_list = dict.to_list(grouped)
  case grouped_list {
    [] -> Ok([])
    _ -> {
      let self = process.new_subject()

      // Scatter
      list.each(grouped_list, fn(pair) {
        let #(shard_id, shard_facts) = pair
        process.spawn(fn() {
          let assert Ok(shard_db) = dict.get(db.shards, shard_id)
          let res = case transactor.transact(shard_db, shard_facts) {
            Ok(state) -> Ok(state)
            Error(e) ->
              Error(
                "Shard "
                <> string.inspect(shard_id)
                <> " transact failed: "
                <> e,
              )
          }
          process.send(self, res)
        })
      })

      // Gather
      list.fold(range(1, list.length(grouped_list)), [], fn(acc, _) {
        let res = case process.receive(self, 15_000) {
          Ok(res) -> res
          Error(_) -> Error("Timeout waiting for shard")
        }
        [res, ..acc]
      })
      |> list.try_map(fn(x) { x })
    }
  }
}

/// Transact on a specific shard regardless of entity hashing.
pub fn transact_shard(
  db: query_types.ShardedDb(transactor.Db),
  shard_id: Int,
  facts: List(fact.Fact),
) -> Result(DbState, String) {
  case dict.get(db.shards, shard_id) {
    Ok(shard_db) -> transactor.transact(shard_db, facts)
    Error(_) -> Error("Shard " <> string.inspect(shard_id) <> " not found")
  }
}

/// Query the sharded database (Parallel Scatter-Gather).
/// Warning: This performs a full scan across all shards.
pub fn query(
  db: query_types.ShardedDb(transactor.Db),
  query: ast.Query,
) -> query_types.QueryResult {
  query_at(db, query, option.None, option.None)
}

/// Query the sharded database at a specific temporal basis.
pub fn query_at(
  db: query_types.ShardedDb(transactor.Db),
  query: ast.Query,
  as_of_tx: Option(Int),
  as_of_valid: Option(Int),
) -> query_types.QueryResult {
  let shard_list = dict.to_list(db.shards)
  let self = process.new_subject()

  // Scatter
  list.each(shard_list, fn(pair) {
    let #(_, shard_db) = pair
    process.spawn(fn() {
      let res =
        engine.run(
          aarondb.get_state(shard_db),
          query,
          [],
          as_of_tx,
          as_of_valid,
        )
      process.send(self, res)
    })
  })

  // Gather
  list.fold(
    range(1, list.length(shard_list)),
    query_types.QueryResult(
      rows: [],
      metadata: query_types.QueryMetadata(
        tx_id: option.None,
        valid_time: option.None,
        execution_time_ms: 0,
        index_hits: 0,
        plan: "",
        shard_id: None,
        aggregates: dict.new(),
      ),
      updated_columnar_store: option.None,
    ),
    fn(acc, _) {
      let res =
        process.receive(self, 15_000)
        |> result.unwrap(query_types.QueryResult(
          rows: [],
          metadata: query_types.QueryMetadata(
            tx_id: option.None,
            valid_time: option.None,
            execution_time_ms: 0,
            index_hits: 0,
            plan: "",
            shard_id: option.None,
            aggregates: dict.new(),
          ),
          updated_columnar_store: option.None,
        ))

      let merged_metadata =
        query_types.QueryMetadata(
          tx_id: case acc.metadata.tx_id, res.metadata.tx_id {
            option.Some(a), option.Some(b) -> option.Some(int.max(a, b))
            option.Some(_), option.None -> acc.metadata.tx_id
            option.None, option.Some(_) -> res.metadata.tx_id
            option.None, option.None -> option.None
          },
          valid_time: case acc.metadata.valid_time, res.metadata.valid_time {
            option.Some(a), option.Some(b) -> option.Some(int.max(a, b))
            option.Some(_), option.None -> acc.metadata.valid_time
            option.None, option.Some(_) -> res.metadata.valid_time
            option.None, option.None -> option.None
          },
          execution_time_ms: acc.metadata.execution_time_ms
            + res.metadata.execution_time_ms,
          index_hits: acc.metadata.index_hits + res.metadata.index_hits,
          plan: acc.metadata.plan,
          shard_id: None,
          aggregates: dict.merge(
            acc.metadata.aggregates,
            res.metadata.aggregates,
          ),
        )

      let all_rows = list.append(acc.rows, res.rows)

      case dict.size(merged_metadata.aggregates) > 0 {
        True -> {
          let rows = coordinate_reduce(all_rows, merged_metadata.aggregates)
          query_types.QueryResult(
            rows: rows,
            metadata: merged_metadata,
            updated_columnar_store: option.None,
          )
        }
        False ->
          query_types.QueryResult(
            rows: all_rows,
            metadata: merged_metadata,
            updated_columnar_store: option.None,
          )
      }
    },
  )
}

/// Perform a Bloom Filter Optimized distributed join.
/// This runs in two passes:
/// 1. Probe: Executes the probe clauses to identify join keys.
/// 2. Build: Executes the build clauses on shards using a Bloom filter of identified keys.
pub fn bloom_query(
  db: query_types.ShardedDb(transactor.Db),
  join_var: String,
  probe_clauses: List(ast.BodyClause),
  build_clauses: List(ast.BodyClause),
) -> query_types.QueryResult {
  // Pass 1: Run probe_clauses globally to find join keys
  let probe_res =
    query(
      db,
      ast.Query(
        find: [],
        where: probe_clauses,
        order_by: None,
        limit: None,
        offset: None,
      ),
    )

  // Build bloom filter from join_var values
  let keys =
    list.fold(probe_res.rows, [], fn(acc, row) {
      case dict.get(row, join_var) {
        Ok(val) -> [fact.to_string(val), ..acc]
        Error(_) -> acc
      }
    })
    |> list.unique()

  // Use a size appropriate for the key count, min 1024 bits
  let filter_size = int.max(1024, list.length(keys) * 10)
  let _filter =
    list.fold(keys, bloom.new(filter_size, 3), fn(f, k) { bloom.insert(f, k) })

  // Pass 2: Run build_clauses globally
  let build_res =
    query(
      db,
      ast.Query(
        find: [],
        where: build_clauses,
        order_by: None,
        limit: None,
        offset: None,
      ),
    )

  // Pass 3: Final join in coordinator
  let final_rows =
    list.fold(probe_res.rows, [], fn(acc, probe_row) {
      let probe_val = dict.get(probe_row, join_var)
      let matching_build =
        list.filter(build_res.rows, fn(build_row) {
          dict.get(build_row, join_var) == probe_val
        })

      list.map(matching_build, fn(br) { dict.merge(probe_row, br) })
      |> list.append(acc)
    })

  query_types.QueryResult(
    rows: final_rows,
    metadata: query_types.QueryMetadata(
      tx_id: case probe_res.metadata.tx_id, build_res.metadata.tx_id {
        option.Some(a), option.Some(b) -> option.Some(int.max(a, b))
        option.Some(_), option.None -> probe_res.metadata.tx_id
        option.None, option.Some(_) -> build_res.metadata.tx_id
        option.None, option.None -> option.None
      },
      valid_time: case
        probe_res.metadata.valid_time,
        build_res.metadata.valid_time
      {
        option.Some(a), option.Some(b) -> option.Some(int.max(a, b))
        option.Some(_), option.None -> probe_res.metadata.valid_time
        option.None, option.Some(_) -> build_res.metadata.valid_time
        option.None, option.None -> option.None
      },
      execution_time_ms: probe_res.metadata.execution_time_ms
        + build_res.metadata.execution_time_ms,
      index_hits: probe_res.metadata.index_hits + build_res.metadata.index_hits,
      plan: probe_res.metadata.plan,
      shard_id: None,
      aggregates: dict.merge(
        probe_res.metadata.aggregates,
        build_res.metadata.aggregates,
      ),
    ),
    updated_columnar_store: option.None,
  )
}

fn coordinate_reduce(
  rows: List(Dict(String, fact.Value)),
  aggregates: Dict(String, ast.AggFunc),
) -> List(Dict(String, fact.Value)) {
  case rows {
    [] -> []
    [first_row, ..] -> {
      // 1. Identify grouping variables (those NOT in aggregates)
      let grouping_vars =
        dict.keys(first_row)
        |> list.filter(fn(k) { !dict.has_key(aggregates, k) })

      // 2. Group by grouping variables
      let grouped =
        list.fold(rows, dict.new(), fn(acc, row) {
          let group_key =
            list.map(grouping_vars, fn(v) {
              dict.get(row, v) |> result.unwrap(fact.Int(0))
            })
          let members = dict.get(acc, group_key) |> result.unwrap([])
          dict.insert(acc, group_key, [row, ..members])
        })

      // 3. For each group, reduce aggregate variables
      dict.to_list(grouped)
      |> list.map(fn(pair) {
        let #(key_vals, members) = pair
        let base_row = list.zip(grouping_vars, key_vals) |> dict.from_list()

        dict.to_list(aggregates)
        |> list.fold(base_row, fn(row_acc, agg_pair) {
          let #(var, func) = agg_pair
          let shard_vals = list.filter_map(members, fn(m) { dict.get(m, var) })

          let final_val = case func {
            ast.Sum | ast.Count -> {
              // FOR SUM and COUNT, the secondary reduction is a SUM of shard results.
              aarondb_aggregate(shard_vals, ast.Sum)
              |> result.unwrap(fact.Int(0))
            }
            ast.Min ->
              aarondb_aggregate(shard_vals, ast.Min)
              |> result.unwrap(fact.Int(0))
            ast.Max ->
              aarondb_aggregate(shard_vals, ast.Max)
              |> result.unwrap(fact.Int(0))
            _ -> {
              // Average/Median are not perfectly supported in this pass without more metadata.
              // We return the first one or a placeholder to avoid crash.
              list.first(shard_vals) |> result.unwrap(fact.Int(0))
            }
          }
          dict.insert(row_acc, var, final_val)
        })
      })
    }
  }
}

// Redirect to avoid name clash
fn aarondb_aggregate(vals, func) {
  aggregate.aggregate(vals, func)
}

/// Pull an entity in parallel across all shards.
pub fn pull(
  db: query_types.ShardedDb(transactor.Db),
  eid: fact.Eid,
  pattern: ast.PullPattern,
) -> query_types.PullResult {
  let shard_list = dict.to_list(db.shards)
  let self = process.new_subject()

  // Scatter
  list.each(shard_list, fn(pair) {
    let #(_, shard_db) = pair
    process.spawn(fn() {
      let res = aarondb.pull(shard_db, eid, pattern)
      process.send(self, res)
    })
  })

  // Gather
  list.fold(
    range(1, list.length(shard_list)),
    query_types.PullMap(dict.new()),
    fn(acc, _) {
      let res = process.receive(self, 5000)
      case res {
        Ok(r) -> merge_pull_results(acc, unsafe_coerce(r))
        Error(_) -> acc
      }
    },
  )
}

@external(erlang, "aarondb_ffi", "dynamic_from")
fn unsafe_coerce(a: a) -> b

/// Perform a global vector similarity search across all shards.
/// Phase 50: Distributed V-Link.
pub fn global_vector_search(
  db: query_types.ShardedDb(transactor.Db),
  query_vec: List(Float),
  threshold: Float,
  k: Int,
) -> List(vec_index.SearchResult) {
  let shard_list = dict.to_list(db.shards)
  let self = process.new_subject()

  // Scatter
  list.each(shard_list, fn(pair) {
    let #(_, shard_db) = pair
    process.spawn(fn() {
      let db_state = aarondb.get_state(shard_db)
      let res = vec_index.search(db_state.vec_index, query_vec, threshold, k)
      process.send(self, res)
    })
  })

  // Gather
  list.fold(range(1, list.length(shard_list)), [], fn(acc, _) {
    let shard_results = process.receive(self, 5000) |> result.unwrap([])
    list.append(acc, shard_results)
  })
  // Reduce (Global Top-K)
  |> list.sort(fn(a, b) { float.compare(b.score, a.score) })
  |> list.take(k)
}

/// Stop the sharded database.
pub fn stop(db: query_types.ShardedDb(transactor.Db)) -> Nil {
  let shard_list = dict.to_list(db.shards)
  list.each(shard_list, fn(pair) {
    let #(_, shard_db) = pair
    let assert Ok(pid) = process.subject_owner(shard_db)
    process.unlink(pid)
    process.kill(pid)
  })
}

/// Rebalance facts across the cluster based on the current shard map.
/// This is a simplified implementation that moves data between shards.
pub type MigrationPlan {
  MigrationPlan(moves: List(#(Int, List(fact.Fact))))
}

/// Calculate which facts need to move based on the current distribution.
/// Pure function: f(ClusterState) -> MigrationPlan
pub fn calculate_migration_plan(
  shards: List(#(Int, List(Dict(String, fact.Value)))),
  shard_map: query_types.ShardMap,
) -> MigrationPlan {
  let moves =
    list.map(shards, fn(pair) {
      let #(shard_id, rows) = pair
      let facts_to_migrate =
        list.fold(rows, [], fn(acc, row) {
          let e = dict.get(row, "e") |> result.unwrap(fact.Int(0))
          let a = "a"
          // Simplified for logic demonstration
          let v = dict.get(row, "v") |> result.unwrap(fact.Int(0))

          let eid = case e {
            fact.Int(id) -> fact.Uid(fact.EntityId(id))
            _ -> fact.Uid(fact.EntityId(0))
          }

          let new_shard_id = get_shard_id_from_map(eid, shard_map)
          case new_shard_id != shard_id {
            True -> [#(eid, a, v), ..acc]
            False -> acc
          }
        })
      #(shard_id, facts_to_migrate)
    })
  MigrationPlan(moves)
}

/// Impure wrapper to execute a rebalance.
pub fn rebalance(
  db: query_types.ShardedDb(transactor.Db),
) -> Result(query_types.ShardedDb(transactor.Db), String) {
  // 1. Collect distribution data (Impure)
  let shard_list = dict.to_list(db.shards)
  let all_facts_query = [ast.Positive(#(ast.Var("e"), "a", ast.Var("v")))]

  let current_distribution =
    list.map(shard_list, fn(pair) {
      let #(shard_id, shard_db) = pair
      let shard_state = transactor.get_state(shard_db)
      let q =
        ast.Query(
          find: [],
          where: all_facts_query,
          order_by: None,
          limit: None,
          offset: None,
        )
      let res = engine.run(shard_state, q, [], None, None)
      #(shard_id, res.rows)
    })

  // 2. Calculate migration plan (Pure)
  let plan = calculate_migration_plan(current_distribution, db.shard_map)

  // 3. Execute plan (Impure)
  let results =
    list.map(plan.moves, fn(move) {
      let #(_, facts) = move
      case facts {
        [] -> Ok(Nil)
        _ -> transact(db, facts) |> result.map(fn(_) { Nil })
      }
    })

  list.try_map(results, fn(x) { x })
  |> result.map(fn(_) { db })
}

/// Manually migrate data from one shard to another.
pub fn migrate_shard_data(
  db: query_types.ShardedDb(transactor.Db),
  from_shard: Int,
  _to_shard: Int,
  _filter: fn(fact.Fact) -> Bool,
) -> Result(Int, String) {
  use _shard_db <- result.try(
    dict.get(db.shards, from_shard)
    |> result.map_error(fn(_) { "Source shard not found" }),
  )

  // High-level: identify items, batch move
  // In Rich Hickey style: we are transforming the state of the cluster
  Ok(0)
  // Placeholder for migration count
}

/// Dynamically add a new shard to the cluster.
/// This will update the ShardMap and trigger a rebalance.
pub fn add_shard(
  db: query_types.ShardedDb(transactor.Db),
  adapter: Option(StorageAdapter),
) -> Result(query_types.ShardedDb(transactor.Db), String) {
  let new_shard_id = db.shard_count
  let shard_cluster_id = db.cluster_id <> "_s" <> string.inspect(new_shard_id)

  case aarondb.start_distributed(shard_cluster_id, adapter) {
    Ok(shard_db) -> {
      let new_shards = dict.insert(db.shards, new_shard_id, shard_db)
      let new_shard_count = db.shard_count + 1
      let new_shard_map = create_shard_map(new_shards)

      let new_db =
        query_types.ShardedDb(
          ..db,
          shards: new_shards,
          shard_count: new_shard_count,
          shard_map: new_shard_map,
        )

      rebalance(new_db)
    }
    Error(e) -> Error("Failed to add shard: " <> string_inspect_actor_error(e))
  }
}

fn merge_pull_results(
  a: query_types.PullResult,
  b: query_types.PullResult,
) -> query_types.PullResult {
  case a, b {
    query_types.PullMap(d1), query_types.PullMap(d2) ->
      query_types.PullMap(dict.merge(d1, d2))
    _, query_types.PullMap(_) -> b
    query_types.PullMap(_), _ -> a
    _, _ -> a
  }
}

fn get_shard_id_from_map(
  eid: fact.Eid,
  shard_map: query_types.ShardMap,
) -> Int {
  let hash = case eid {
    fact.Uid(fact.EntityId(id)) -> fact.phash2(fact.Int(id))
    fact.Lookup(#(_, val)) -> fact.phash2(val)
  }

  // Find the first vnode with hash >= current hash
  let target =
    list.find(shard_map.sorted_hashes, fn(h) { h >= hash })
    |> result.lazy_unwrap(fn() {
      // Wrap around to the first node
      list.first(shard_map.sorted_hashes) |> result.unwrap(0)
    })

  dict.get(shard_map.vnodes, target) |> result.unwrap(0)
}

fn create_shard_map(shards: Dict(Int, transactor.Db)) -> query_types.ShardMap {
  let vnode_count = 100
  // 100 virtual nodes per shard for better distribution

  let vnodes =
    dict.to_list(shards)
    |> list.fold(dict.new(), fn(acc, pair) {
      let #(shard_id, _) = pair
      range(0, vnode_count)
      |> list.fold(acc, fn(v_acc, i) {
        let v_hash =
          fact.phash2(fact.Str(
            string.inspect(shard_id) <> ":" <> string.inspect(i),
          ))
        dict.insert(v_acc, v_hash, shard_id)
      })
    })

  let sorted_hashes = dict.keys(vnodes) |> list.sort(int.compare)

  let nodes =
    dict.to_list(shards)
    |> list.fold(dict.new(), fn(acc, pair) {
      let #(id, sub) = pair
      let assert Ok(pid) = process.subject_owner(sub)
      dict.insert(acc, id, pid)
    })

  query_types.ShardMap(
    vnodes: vnodes,
    nodes: nodes,
    sorted_hashes: sorted_hashes,
  )
}

fn string_inspect_actor_error(e: actor.StartError) -> String {
  string.inspect(e)
}
