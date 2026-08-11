# Distributed Harness

`aarondb/distributed_harness` is the deterministic safety oracle for the
library-level distributed modules. The process/network adapter owns delivery;
the oracle owns replayable schedules and invariant checks.

## Replay contract

The fixed seeds are public regression inputs:

| Seed | Fault schedule |
| --- | --- |
| `11` | partition, duplicate append RPC, heal |
| `23` | crash/restart, reordered append RPC |
| `37` | slow follower, membership churn, negative clock skew |
| `41` | disk fault, crash/restart, reordered snapshot RPC |

The oracle rejects histories containing multiple leaders for a term, more than
one application of a committed index, acceptance of a stale fencing token, or
unsafe recovery without an alarm. The suite contains deliberate known-bad
mutants for each invariant.

## Failure artifacts

Run `AARONDB_HARNESS_ARTIFACT_DIR=artifacts/distributed-harness sh
scripts/verify_distributed_harness.sh`. The wrapper records each command and
preserves `run.log`; adapters should serialize `distributed_harness.artifact`
with the seed, schedule, observations, and violations beside that log whenever
a run fails. A seed plus artifact is sufficient to reproduce the oracle result
without relying on scheduler timing.

CI invokes the same wrapper. It runs format, type-check, the full test suite,
and the authenticated three-VM TLS proof when the required OTP/OpenSSL tools
are present; failures stop the gate rather than being silently downgraded.
