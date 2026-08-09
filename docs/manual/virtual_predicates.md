# Virtual predicates: bounded local adapters

A virtual predicate is a caller-owned adapter invoked synchronously by the
local AaronDB query actor. It is an extension hook for local data already
available to the BEAM process; it is not federation, a network connector, or a
remote execution protocol.

## Lifecycle

Create an adapter with `state.virtual_adapter(execute, max_rows)`. A positive
`max_rows` is required. Register the adapter in `DbState.virtual_predicates`
before executing a query containing `q.virtual(...)`.

The `execute` function receives fully resolved query arguments and returns:

- `Ok(rows)`: a complete ordered list of rows. AaronDB preserves adapter row
  order before later query clauses apply their own filtering.
- `Error(VirtualAdapterFailed(message))`: the adapter reported a local failure.
- `Error(VirtualAdapterTimedOut)`: the adapter's own timeout policy expired.

An adapter must finish within the query actor's normal execution budget. AaronDB
cannot interrupt a synchronous function already running. Applications needing
hard cancellation must place it inside the adapter implementation, or terminate
the local query process.

## Failure and bounds

A missing adapter, unresolved argument, adapter error, output-shape mismatch, or
row count above `max_rows` fails closed: that virtual clause produces no rows.
AaronDB does not return a partial adapter result. `VirtualRowLimitExceeded` is
the adapter-boundary error used by adapters that can detect their own overflow;
AaronDB also enforces the configured `max_rows` after a successful return.

Adapters are application-owned and must validate their inputs and output values.
There is no retry, provenance, schema negotiation, authentication, transport,
remote timeout, global snapshot, coordinated write, replication, or distributed
consistency contract.

## Recommended shape

```gleam
let execute = fn(args) {
  case read_local_cache(args) {
    Ok(rows) -> Ok(rows)
    Error(reason) -> Error(state.VirtualAdapterFailed(reason))
  }
}
let assert Ok(adapter) = state.virtual_adapter(execute, 1_000)
```
