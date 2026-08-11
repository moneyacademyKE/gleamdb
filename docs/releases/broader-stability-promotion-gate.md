# Broader Stability Promotion Gate

`scripts/verify_broader_stability.sh` is the profile-aware, fail-closed witness for broader stability. It accepts only versioned evidence that validates against the named profile, then records source identity, profile list, check details, and verdict in an immutable-style artifact directory.

By default it evaluates `long-soak-v1` from `artifacts/broader-stability/long-soak-v1/evidence.json`; use `AARONDB_BROAD_PROFILES='profile-a profile-b'` to require multiple profiles. Missing, stale, malformed, threshold-violating, or absent independent-host evidence produces `BROAD_PROMOTION_NO_GO`. A dirty worktree is always NO-GO.

This gate does not claim universal stability. A GO is scoped to the exact profile names, evidence hashes, source identity, hardware/workload assumptions, and fault budget recorded in the witness. It does not convert same-host smoke artifacts into independent-host or long-soak proof.
