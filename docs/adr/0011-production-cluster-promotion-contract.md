# ADR 0011: Production Cluster Promotion Contract

## Status

Proposed

## Context

The durable/distributed modules (`raft_runtime`, `consensus`, `durable_log`,
`changefeed`, `projection`, `projection_index`, `identity`, and `operations`)
are an experimental, deterministic reference library. Their tests establish
library contracts. They do **not** establish an integrated cluster runtime,
crash-safe storage behavior, or multi-node operational evidence.

This decision defines the conditions under which a separate AaronDB cluster
product may be labelled production-ready. It does not change the supported
embedded product described by ADR 0002: `aarondb.new()` stays in-process and
local.

## Decision

### Product surfaces and compatibility

AaronDB has two distinct supported surfaces:

| Surface | Constructor / deployment | Claim |
| --- | --- | --- |
| Embedded | `aarondb.new()` in one BEAM runtime | Local, in-process temporal Datalog library |
| Cluster | Explicit versioned cluster configuration and node runtime | Authenticated Raft-backed replicated state machine, only after every gate in this ADR passes |

Cluster clients must use a separate public API and wire protocol version. No
existing embedded constructor, storage adapter, local reactive subscription,
or Mnesia recovery behavior acquires a distributed durability or availability
meaning by implication.

A cluster release supports only an odd-sized, statically provisioned voter set
of one, three, or five nodes. A one-voter cluster has no fault tolerance.
Three-voter and five-voter configurations tolerate respectively one and two
unavailable voters while a quorum remains. Read-only observers, automatic
membership discovery, automatic voter replacement, geo-replication, and
cross-cluster transactions are not supported until separately specified.

### Bootstrap, identity, and transport

A cluster is initialized by an explicit bootstrap ceremony that creates the
first committed membership record and durable cluster identifier. A joining
node must present a durable node identity and a currently trusted mTLS
certificate bound to both its node ID and cluster ID. A member is admitted
only through a committed membership change authorized by the current voter
set. Empty storage may bootstrap exactly one configured initial cluster;
non-empty storage, mismatched cluster IDs, revoked certificates, expired or
untrusted trust roots, and unauthorized identities fail closed.

All node-to-node RPC uses mutually authenticated TLS, protocol framing with a
negotiated major version, bounded payloads, deadlines, bounded retry/backoff,
and bounded connection/queue counts. An unauthenticated, unrecognized,
revoked, malformed, oversize, incompatible, or deadline-expired RPC has no
state-machine effect and is observable in metrics/logs.

Certificate and trust-root rotation use overlapping committed trust epochs.
Revocation takes precedence immediately after the new trust epoch commits.
A node must not claim quorum, leadership, or linearizable-read eligibility
when its membership or identity state is uncertain.

### Durability and recovery semantics

The production persistence adapter owns hard state, log entries, snapshots,
membership, idempotency records, leases, projection checkpoints, and alarm
records. It specifies per-record checksums, atomic replace/write strategy,
fsync boundaries, directory-sync requirements, snapshot/log compaction, and
backup/export format.

An acknowledged command is durable only after its log record and required hard
state have crossed the documented fsync boundary and a quorum has committed it.
A command may be retried after timeout; the idempotency key returns the original
committed outcome or rejects a key/payload mismatch. Unacknowledged commands
may be absent after restart. No entry is visible to clients, feeds, or
projections before commit.

Startup validates checksums, record ordering, membership epoch, snapshot/log
continuity, and cluster identity before serving. Torn, corrupt, divergent, or
unverifiable state refuses service and raises a persistent unsafe-recovery
alarm. The runtime never silently truncates, rewrites membership, invents a
new cluster ID, or repairs data by discarding evidence. Force recovery requires
an explicit acknowledgement, leaves an auditable alarm, and blocks production
promotion until the resulting cluster has been rebuilt or independently
reviewed.

Backup/export is a verified point-in-time snapshot plus the documented log
position. Restore and compaction must preserve deterministic state-machine
results at the same committed index.

### Consistency, commands, leases, and projections

Writes route to the current leader or return a typed leader hint; they succeed
only after current-term quorum commit and deterministic application. Compare-
and-set, idempotency, lease transitions, membership changes, and fencing-token
issuance are commands in that log.

`Linearizable` reads require a successful ReadIndex quorum confirmation and
an applied index at least that confirmation. `Stale` reads must report their
applied index/term and cannot be presented as linearizable. During loss of
quorum, leadership uncertainty, persistence uncertainty, or an unsafe-recovery
alarm, the runtime refuses linearizable reads and writes rather than lying.

Leases use the committed logical/monotonic time contract, never wall-clock
rollback. Renew, revoke, expire, and re-acquire are log commands. Every
successful acquisition has a strictly increasing fencing token; downstream
writers must reject stale tokens.

Changefeeds provide ordered at-least-once delivery with a resumable cursor,
snapshot-then-tail bootstrap, bounded consumer credits, and duplicate-safe
redelivery. Projection application is idempotent and a projection store must
atomically persist derived state with source offset, schema version, and
generation. Indexes remain derived/non-authoritative; rebuilding or degraded
indexes refuse queries until a complete verified generation is swapped in.

### Production SLOs and capacity declaration

A release candidate must publish a versioned supported-topology and hardware
profile, workload/data shape, configuration, and measurement command. It must
meet these initial gates on every supported runtime/OS combination:

| Property | Gate |
| --- | --- |
| Availability | A three-voter cluster keeps accepting acknowledged writes after one voter failure and recovers the voter without invariant breach |
| Recovery | Forced process restart restores exactly the last quorum-committed state; corruption/torn-write scenarios fail closed with an alarm |
| Correctness | Seeded history checker finds no linearizability, duplicate-application, stale-fence, split-brain, or pre-commit-visibility violation |
| Latency/throughput | Release-specific p50/p95/p99 and sustained acknowledged-write throughput thresholds are published and enforced; no generic numbers are implied by this ADR |
| Lag | Follower, feed, projection, and index lag stay within release-specific declared bounds under steady load and return below them after one-voter failover |
| Resources | Sustained soak shows bounded memory, disk, connection, and queue growth; snapshot/rebuild/compaction and recovery duration stay within published bounds |

Numeric thresholds are intentionally release-specific: invented universal
numbers would be bullshit. They become contractual only when recorded with the
release candidate's hardware, topology, corpus, and command line.

### Evidence and promotion checklist

A release candidate may be promoted only if all evidence is reproducible from
versioned commands and attached to the release review:

1. Three separate BEAM nodes join, elect, replicate, redirect writes, reject
   unauthorized peers, and support graceful public shutdown.
2. Crash/restart, kill -9 equivalent, disk-full, torn-write, checksum
   corruption, snapshot interruption, backup/restore, and compaction tests
   prove acknowledged-state recovery or fail-closed alarming.
3. Black-box clients cover commit visibility, idempotency, CAS, ReadIndex,
   failover, lease/fence races, cursor/resume, projection checkpoints,
   rebuild/swap, degraded index refusal, and truthful status.
4. Seeded multi-node chaos covers partition/heal, delayed/duplicated/reordered
   RPC, slow followers, churn, restart, storage faults, and bounded
   clock-skew discipline. Known-bad mutants for split brain, duplicate apply,
   stale fencing, and unalarmed unsafe recovery are killed. Failures preserve
   the seed, topology, logs, and history artifact.
5. A sustained soak includes load, leader failover, follower recovery,
   snapshot/compaction, and projection/index rebuild without an invariant
   breach or unbounded resource growth.
6. A clean operator follows only documented configuration and commands to
   bootstrap, join/scale, rotate identity, observe status/metrics, back up,
   restore, acknowledge unsafe recovery, and diagnose an incident.
7. Security/dependency review has no unresolved release-blocking finding; the
   support boundary, upgrade/rollback compatibility, SLO evidence, and known
   limitations are published without contradicting ADR 0002.
8. The release decision is independently reviewed. A green label is not a
   substitute for the evidence matrix.

## Explicit non-goals

- Relabelling reference-model tests as production HA evidence.
- Transparent promotion of embedded `aarondb.new()` or Mnesia into a cluster.
- Exactly-once external effects, automatic repair, unauthenticated discovery,
  or silent recovery.
- Automatic membership replacement, arbitrary dynamic topology, multi-region
  replication, or cross-cluster transactions.
- Universal performance, availability, or latency claims absent a versioned
  evidence profile.

## Consequences

The cluster stream must remain separately versioned and reviewable from
pre-existing local-stability work. A failed gate blocks promotion and the
product remains experimental. The workload is intentionally larger than the
reference library: production readiness requires real process/network/storage
behavior and evidence, not an optimistic maturity label.

## References

- [ADR 0002](0002-embedded-local-mcp-boundary.md)
- [ADR 0003](0003-durable-distributed-library-evolution.md)
- [ADR 0007](0007-authenticated-durable-raft.md)
- [ADR 0010](0010-identity-recovery-fault-gates.md)
- [Experimental release manifest](../releases/durable_distributed_experimental.md)
