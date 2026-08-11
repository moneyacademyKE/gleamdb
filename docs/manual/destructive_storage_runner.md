# Destructive Storage Evidence Runner

`scripts/verify_destructive_storage.sh` is the fail-closed gate for the
`destructive-storage-v1` profile. It runs the durable recovery regressions and
the public operator lifecycle contract, then stores a machine-readable evidence
record at `artifacts/broader-stability/destructive-storage-v1/<utc-run>/`.

## Covered fault classes

- malformed, torn, and checksum-mismatched primary recovery images;
- a synced temporary image interrupted before its atomic rename;
- snapshot-compaction recovery equivalence;
- verified backup export/reload and explicit operator restore/recovery paths.

A corrupt primary image is never auto-repaired. It must return a corruption
alarm; recovery is only demonstrated from an independently verified backup via
the public operator contract.

## Explicit limit

This runner does **not** cut physical power and cannot attest power-loss
semantics for a storage controller cache, device firmware, kernel/filesystem, or
named hardware. Supplying `AARONDB_PHYSICAL_POWER_CUT_ATTESTATION` makes the
gate fail rather than laundering that untested condition into the evidence.

Run locally:

`sh scripts/verify_destructive_storage.sh`

The resulting evidence supports only the recorded injected process/storage fault
classes in `destructive-storage-v1`; it does not widen the project to arbitrary
physical-failure claims.
