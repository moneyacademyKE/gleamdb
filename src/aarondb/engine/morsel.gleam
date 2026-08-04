import aarondb/fact
import aarondb/shared/ast as types
import gleam/dict.{type Dict}
import gleam/erlang/process
import gleam/list

// A message from a worker back to the coordinator
type WorkerResult {
  WorkerResult(rows: List(Dict(String, fact.Value)))
}

/// Evaluates a compiled predicate over a "morsel" (chunk) of Datoms concurrently.
pub fn execute_morsels(
  datoms: List(fact.Datom),
  contexts: List(Dict(String, fact.Value)),
  e_p: types.Part,
  v_p: types.Part,
  chunk_size: Int,
) -> List(Dict(String, fact.Value)) {
  case list.length(datoms) <= chunk_size {
    True -> evaluate_chunk(datoms, contexts, e_p, v_p)
    False -> {
      let chunks = list.sized_chunk(datoms, chunk_size)
      let subject = process.new_subject()

      // Spawn a worker process for each chunk
      list.each(chunks, fn(chunk) {
        spawn_worker(fn() {
          let res = evaluate_chunk(chunk, contexts, e_p, v_p)
          process.send(subject, WorkerResult(res))
        })
      })

      // Await all results
      let num_chunks = list.length(chunks)
      receive_all(subject, num_chunks, [])
    }
  }
}

fn receive_all(
  subject: process.Subject(WorkerResult),
  remaining: Int,
  acc: List(Dict(String, fact.Value)),
) -> List(Dict(String, fact.Value)) {
  case remaining {
    0 -> acc
    n -> {
      // Wait up to 5 seconds per chunk
      case process.receive(subject, 5000) {
        Ok(WorkerResult(res)) ->
          receive_all(subject, n - 1, list.append(acc, res))
        // Worker timed out: drop its partial result and continue.
        Error(_) -> receive_all(subject, n - 1, acc)
      }
    }
  }
}

fn evaluate_chunk(
  datoms: List(fact.Datom),
  contexts: List(Dict(String, fact.Value)),
  e_p: types.Part,
  v_p: types.Part,
) -> List(Dict(String, fact.Value)) {
  list.flat_map(datoms, fn(d: fact.Datom) {
    list.map(contexts, fn(ctx) {
      let b = ctx
      let b = case e_p {
        types.Var(n) -> dict.insert(b, n, fact.Ref(d.entity))
        _ -> b
      }
      let b = case v_p {
        types.Var(n) -> dict.insert(b, n, d.value)
        _ -> b
      }
      b
    })
  })
}

@external(erlang, "erlang", "spawn")
fn spawn_worker(f: fn() -> Nil) -> process.Pid
