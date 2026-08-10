# ADR 0006: Canonical Signed Envelopes and Key Policy

## Status

Proposed

## Decision

`EnvelopeV1` is a standalone generic fact/event primitive. Its signed bytes are a versioned, length-delimited binary frame with a fixed field order: version, domain, payload bytes/hash, author-key reference, ordered parents, logical clock, key epoch, and signature. The signature covers a domain-separated hash of every consensus-relevant field.

Canonical encoding is never JSON, map iteration, or BEAM term serialization. Decoders have fixed maximum frame, payload, parent, key, and nesting limits. Hashing and Ed25519 signing/verification are narrow, audited FFI boundaries with published test vectors.

A keyring contains trust roots and active, rotated, and revoked states. Validation reports contextual outcomes: unknown root, inactive key, wrong epoch, revoked key, invalid signature, wrong domain, unsupported version, or limits exceeded. Key rotation and revocation are represented as verifiable policy data with an explicit distribution path; local capability auth is unrelated.

## Consequences

Envelope bytes are a public compatibility boundary. Any encoding change requires a new version and vectors; no best-effort decoder compatibility is permitted.
