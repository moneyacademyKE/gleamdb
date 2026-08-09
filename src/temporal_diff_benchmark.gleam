import aarondb
import aarondb/fact
import aarondb/shared/ast
import gleam/int
import gleam/io
import gleam/list

/// Reproducible local temporal-query and diff evidence harness.
///
/// Run with `gleam run -m temporal_diff_benchmark`. It measures one in-memory
/// actor in one BEAM process. Results are regression evidence only, not a
/// portable latency, retention, or capacity guarantee.
pub fn main() {
  let db = aarondb.new()
  let transaction_count = 250
  let entity_count = 25
  let setup_start = now()
  let assert Ok(first_state) =
    aarondb.transact(db, [
      #(fact.Uid(fact.EntityId(1)), "event/value", fact.Int(1)),
    ])
  let last_state =
    int.range(
      from: 2,
      to: transaction_count,
      with: first_state,
      run: fn(_state, tx) {
        let entity_id = case tx % entity_count {
          0 -> entity_count
          remainder -> remainder
        }
        let entity = fact.Uid(fact.EntityId(entity_id))
        let assert Ok(next) =
          aarondb.transact(db, [#(entity, "event/value", fact.Int(tx))])
        next
      },
    )
  let setup_ns = now() - setup_start

  let assert Ok(temporal_limits) =
    aarondb.temporal_scan_limits(transaction_count + 10)
  let assert Ok(diff_limits) = aarondb.diff_scan_limits(transaction_count + 10)
  let clause = aarondb.p(#(ast.Var("entity"), "event/value", ast.Var("value")))

  let temporal_times =
    samples(100, fn(_) {
      let start = now()
      let _ =
        aarondb.as_of_bounded(
          db,
          last_state.latest_tx,
          [clause],
          temporal_limits,
        )
      nanoseconds_to_milliseconds(now() - start)
    })

  let diff_times =
    samples(100, fn(_) {
      let start = now()
      let _ =
        aarondb.diff_bounded(
          db,
          first_state.latest_tx,
          last_state.latest_tx,
          diff_limits,
        )
      nanoseconds_to_milliseconds(now() - start)
    })

  io.println("transaction_count=" <> int.to_string(transaction_count))
  io.println("entity_count=" <> int.to_string(entity_count))
  io.println("sample_count=100")
  io.println(
    "setup_ms=" <> int.to_string(nanoseconds_to_milliseconds(setup_ns)),
  )
  print_latency("temporal_snapshot", temporal_times)
  print_latency("bounded_diff", diff_times)
}

fn samples(count: Int, sample: fn(Nil) -> Int) -> List(Int) {
  list.repeat(Nil, count) |> list.map(sample)
}

fn print_latency(label: String, samples: List(Int)) {
  let sorted = list.sort(samples, int.compare)
  let count = list.length(sorted)
  let total = list.fold(samples, 0, fn(sum, value) { sum + value })
  let assert Ok(p50) =
    list.drop(sorted, percentile_index(count, 50)) |> list.first()
  let assert Ok(p95) =
    list.drop(sorted, percentile_index(count, 95)) |> list.first()
  io.println(label <> "_total_ms=" <> int.to_string(total))
  io.println(label <> "_p50_ms=" <> int.to_string(p50))
  io.println(label <> "_p95_ms=" <> int.to_string(p95))
}

fn percentile_index(count: Int, percentile: Int) -> Int {
  let percentage = count * percentile / 100
  int.max(0, percentage - 1)
}

fn nanoseconds_to_milliseconds(value: Int) -> Int {
  value / 1_000_000
}

@external(erlang, "erlang", "system_time")
fn now() -> Int
