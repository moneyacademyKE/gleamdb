# Virtual predicates and local federation

AaronDB has two different extension surfaces. They are deliberately not the
same thing.

## Virtual predicates: bounded local adapters

A virtual predicate is a caller-registered, synchronous adapter invoked by the
local query actor when it reaches a `Virtual` clause. The adapter returns a
complete ordered row list or a typed local error and is bounded by a positive
caller-chosen row limit. Its complete contract is in
[Virtual predicates](../manual/virtual_predicates.md).

AaronDB enforces the row limit and fails closed for missing adapters, unresolved
arguments, adapter failures/timeouts, and invalid output shapes: the clause
produces no partial rows. Adapters remain application-owned code; AaronDB cannot
interrupt an adapter already executing synchronously.

Virtual predicates are **Stable (bounded local adapters)**. They do not define
external transport, authentication, retries, provenance, schema negotiation,
remote timeout enforcement, global snapshots, coordinated writes, replication,
or distributed consistency.

## Local federation: stable local fail-fast composition

`aarondb/federation` composes named local AaronDB actors in one BEAM runtime.
It has source admission checks, schema attribute-set compatibility, stable
source ordering, and provenance per returned row. Its detailed contract is in
[Local federation](../manual/local_federation.md).

It is not a virtual-predicate adapter layer, remote federation, sharding,
replication, coordinated writes, quorum, or high availability. The local
fail-fast execution contract, source lifecycle checks, and soak evidence are in
[Local federation](../manual/local_federation.md).
