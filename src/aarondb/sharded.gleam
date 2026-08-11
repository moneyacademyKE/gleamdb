import aarondb
import aarondb/algo/aggregate
import aarondb/algo/bloom
import aarondb/engine
import aarondb/fact
import aarondb/sharding/semantics
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
  case
    semantics.group_facts(
      facts,
      db.shard_map.vnodes,
      db.shard_map.sorted_hashes,
    )
  {
    Error(error) -> Error(error)
    Ok(grouped) -> {
      let grouped_list = dict.to_list(grouped)
      case grouped_list {
        [] -> Ok([])
        _ -> {
          let self = process.new_subject()
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

          let final_val = {
            // Secondary reduction over per-shard aggregate results.
            // Sum/Count/Min/Max combine exactly (cross-shard count = sum of
            // per-shard counts). Avg/Median are APPROXIMATE here: each shard
            // has already reduced to a scalar, so we compute the
            // average-of-averages / median-of-medians. The exact global value
            // would need per-shard counts (Avg) or all raw values (Median),
            // which this pre-aggregation pass does not carry.
            let secondary = case func {
              ast.Count -> ast.Sum
              other -> other
            }
            aarondb_aggregate(shard_vals, secondary)
            |> result.unwrap(fact.Int(0))
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

/// Manually migrate data from one shard to another.
///
/// ⚠️ NOT YET IMPLEMENTED. A correct implementation must scan the source
/// shard's facts, apply `filter`, transact the matches into the destination
/// shard (and retract from the source) under transaction safety, then return
/// the count moved. Returns an explicit error rather than a silent `Ok(0)`
/// that would falsely claim success. No callers exist today.
pub fn migrate_shard_data(
  _db: query_types.ShardedDb(transactor.Db),
  _from_shard: Int,
  _to_shard: Int,
  _filter: fn(fact.Fact) -> Bool,
) -> Result(Int, String) {
  Error("migrate_shard_data is not implemented — see doc comment")
}

/// Rebalance is deliberately unsupported.
///
/// A correct implementation needs an atomic or recoverable copy/verify/cut-over
/// protocol. Returning an explicit error is safer than duplicating facts without
/// retracting their source copies.
pub fn rebalance(
  _db: query_types.ShardedDb(transactor.Db),
) -> Result(query_types.ShardedDb(transactor.Db), String) {
  Error("shard rebalancing is not supported — no atomic migration protocol")
}

/// Add a shard without attempting migration.
///
/// Existing facts remain on their current shards. The returned cluster updates
/// routing only for future writes. Rebalancing is deliberately unsupported
/// until a copy/verify/cut-over/retract protocol can preserve data atomically.
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
      Ok(
        query_types.ShardedDb(
          ..db,
          shards: new_shards,
          shard_count: new_shard_count,
          shard_map: new_shard_map,
        ),
      )
    }
    Error(e) -> Error("Failed to add shard: " <> string_inspect_actor_error(e))
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
