import aarondb
import aarondb/fact.{EntityId, Str, Uid}
import aarondb/federation
import aarondb/shared/ast
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{None}

/// Reproducible local federation evidence harness.
///
/// Run with `gleam run -m federation_benchmark`. It creates two local actors,
/// inserts deterministic data, and measures repeated fail-fast reads. The
/// result is machine-local evidence, not a remote or HA performance claim.
pub fn main() {
  let alpha = aarondb.new()
  let beta = aarondb.new()
  let assert Ok(_) = seed(alpha, 1, 500, "alpha")
  let assert Ok(_) = seed(beta, 10_001, 500, "beta")
  let assert Ok(federation) =
    federation.new([
      federation.Source("beta", beta),
      federation.Source("alpha", alpha),
    ])

  let query = people_query()
  let start = now()
  let result = run_reads(federation, query, 100)
  let elapsed = now() - start
  let assert Ok(federation.FederatedResult(rows:, ..)) = result
  io.println(
    "sources=2 rows="
    <> int.to_string(list.length(rows))
    <> " reads=100 total_ms="
    <> int.to_string(nanoseconds_to_milliseconds(elapsed)),
  )
}

fn seed(
  db: aarondb.Db,
  start: Int,
  count: Int,
  prefix: String,
) -> Result(aarondb.DbState, String) {
  let facts =
    int.range(from: start, to: start + count - 1, with: [], run: fn(acc, id) {
      [
        #(Uid(EntityId(id)), "person/name", Str(prefix <> int.to_string(id))),
        ..acc
      ]
    })
  aarondb.transact(db, facts)
}

fn run_reads(
  federation: federation.Federation,
  query: ast.Query,
  count: Int,
) -> Result(federation.FederatedResult, federation.FederationError) {
  int.range(
    from: 1,
    to: count,
    with: federation.query(federation, query),
    run: fn(result, _) {
      case result {
        Ok(_) -> federation.query(federation, query)
        Error(error) -> Error(error)
      }
    },
  )
}

fn people_query() -> ast.Query {
  ast.Query(
    find: ["name"],
    where: [ast.Positive(#(ast.Var("e"), "person/name", ast.Var("name")))],
    order_by: None,
    limit: None,
    offset: None,
  )
}

fn nanoseconds_to_milliseconds(value: Int) -> Int {
  value / 1_000_000
}

@external(erlang, "erlang", "system_time")
fn now() -> Int
