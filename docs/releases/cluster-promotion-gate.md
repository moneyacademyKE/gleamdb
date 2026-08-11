# Cluster Promotion Gate and Release Witness

The cluster stream remains an **experimental reference** unless this command
produces a `GO` witness from a reviewed, immutable release commit:

`sh scripts/verify_cluster_promotion.sh`

The command writes both `artifacts/cluster-promotion/release-witness.json` and
`artifacts/cluster-promotion/release-witness.md`, even when it fails. The JSON
is the promotion record; the Markdown file is an operator-readable rendering.

## Required predicates

The gate evaluates every predicate and returns non-zero unless all pass:

| Predicate | Required evidence |
|---|---|
| Profile | Valid versioned SLO profile and content hash |
| Performance | Fresh evidence passes `validate_slo_evidence.sh` against that profile |
| Chaos | Four public seeds (11, 23, 37, 41) each prove committed work, recovery timing, and safety assertions; known-bad mutant gate passes |
| Operator lifecycle | `test_cluster_operator.sh` completes its public success, rejected-path, and redaction contract |
| Source verification | Gleam format, check, test, and diff hygiene pass |
| Release identity | Git worktree is clean, preventing a mutable developer checkout from being called a promoted release |

Input locations may be overridden only explicitly:

`AARONDB_SLO_PROFILE=... AARONDB_PERFORMANCE_EVIDENCE=... AARONDB_CHAOS_ARTIFACT_DIR=... AARONDB_PROMOTION_ARTIFACT_DIR=... AARONDB_RELEASE_ID=... sh scripts/verify_cluster_promotion.sh`

A `NO-GO` is the correct outcome for stale/missing evidence, incomplete chaos
artifacts, failed checks, or a dirty worktree. Do not hand-edit a witness or
copy a prior green result onto a different commit: the witness captures the
release identity and SHA-256 hashes of the profile, performance artifact, and
chaos artifacts it accepted.
