# Virtual predicates and local federation

AaronDB has two different extension surfaces. They are deliberately not the
same thing.

## Virtual predicates: experimental adapters

A virtual predicate is a caller-registered in-process adapter. The query engine
calls it when it reaches a `Virtual` clause.

```gleam
pub type VirtualAdapter =
  fn(List(fact.Value)) -> List(List(fact.Value))
```

Virtual adapters are **Experimental**. AaronDB does not define external source
transport, authentication, retries, timeout policy, source provenance, schema
negotiation, consistency, or failure isolation for them. Treat every adapter as
application-owned code and validate its inputs and output shape at its boundary.

## Local federation: Beta composition

`aarondb/federation` composes named local AaronDB actors in one BEAM runtime.
It has source admission checks, schema attribute-set compatibility, stable
source ordering, and provenance per returned row. Its detailed contract is in
[Local federation](../manual/local_federation.md).

It is not a virtual-predicate adapter layer, remote federation, sharding,
replication, coordinated writes, quorum, or high availability. Federation stays
Beta until its execution API returns typed fail-fast source failures and has
source lifecycle/soak evidence.
