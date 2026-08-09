# Local Reactive Subscriptions

AaronDB reactive queries are a **local BEAM-runtime** facility. They are not a durable event stream, a network protocol, or a backpressured queue.

## Contract

`aarondb.subscribe(db, query, subject)` registers a query with the database's reactive actor.

- The actor sends one `Initial(result)` before it sends any `Delta` for that subscription.
- The actor processes `Subscribe`, `Notify`, and `Unsubscribe` messages in its mailbox order.
- For each committed transaction that changes an attribute referenced by the query, an affected subscription receives at most one complete `Delta(added, removed)`.
- Deltas contain set differences between the subscription's prior and current query result. A transaction that does not change the result emits no delta.
- `aarondb.unsubscribe(db, subject)` prevents deltas from later actor notifications. Messages already sent remain in the subscriber mailbox.
- A subscriber whose owning process has stopped is removed when the next notification reaches the reactive actor.

## Delivery and backpressure

Delivery is ordinary asynchronous BEAM mailbox delivery.

- A database writer never blocks waiting for a reactive subscriber.
- AaronDB does not impose a mailbox size, drop policy, replay buffer, acknowledgement, or flow-control protocol.
- A slow subscriber accumulates mailbox messages and is responsible for draining them or unsubscribing.
- If bounded delivery, replay, or consumer acknowledgements are required, put an application-owned bounded actor or queue between the subscription subject and the slow consumer.

## Failure boundary

The reactive actor is local to the database instance. It does not supervise or restart subscriber processes, and subscribers do not receive a terminal error when another subscriber fails. A stopped subscriber is eventually pruned on notification; an idle stopped subscriber is harmless but remains registered until then.

## Compatibility

This contract applies to reactive query subscriptions. WAL-style hooks remain a separate compatibility surface and currently have no explicit unsubscribe or bounded-delivery API.
