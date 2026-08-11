# Lifecycle and Incident Drill Evidence

`scripts/verify_lifecycle_drills.sh` exercises the public `aarondb-clusterctl.sh` contract against a disposable cluster state. It is a safety-contract test, not a substitute for a real multi-host rolling upgrade.

The drill covers:

- verified backup and restore into an empty replacement;
- refusal of in-place/non-empty and unconfirmed restore;
- certificate rotation and revocation with alarm persistence;
- projection rebuild request and non-authoritative semantics;
- redacted incident collection;
- checksum-tamper refusal.

A production lifecycle promotion still requires the external three-host runner to execute rolling mixed-version compatibility and rollback. This local drill deliberately fails closed if the public safety contract regresses.
