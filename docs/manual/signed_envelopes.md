# Canonical Signed Envelopes

`aarondb/envelope` is an independent primitive for signed facts and events. It
is not an authentication upgrade for `aarondb/auth`; capability tokens retain
their documented local authorization-only contract.

## Version 1 bytes

The canonical byte frame begins with `AARON-ENVELOPE`, then uses fixed-width
integers and length-delimited byte strings in this exact order:

1. version (`u32`)
2. domain
3. payload
4. SHA-256 payload digest
5. Ed25519 author public key
6. parent count followed by parents in supplied order
7. logical clock (`u64`)
8. key epoch (`u32`)
9. signature

The signature is Ed25519 over SHA-256 of a different, domain-separated
unsigned frame (`AARON-ENVELOPE-V1-SIGNATURE`) containing domain, payload,
author, ordered parents, clock, and key epoch. The signature and payload hash
are never inputs to their own signed digest.

This is intentionally not JSON, map serialization, or an Erlang term. Field
order and byte framing are public compatibility commitments. A change requires
a new version and new vectors.

## Verification policy

A verifier provides the required domain and a `Keyring`. Verification rejects:

- unsupported versions and wrong domains;
- altered payloads, hashes, clocks, parents, authors, epochs, or signatures;
- unknown, rotated/inactive, and revoked keys;
- envelopes exceeding explicit parent or frame limits.

Keys have `Active(epoch)`, `Rotated(epoch)`, or `Revoked` state. Replacing a
key in the keyring is the explicit rotation transition; revocation wins over
any historical signature. Distribution of root keys and revocations remains an
application trust concern—the keyring does not pretend local memory is a
network PKI.

## Delivery caveat

Envelope verification establishes integrity and a key-policy outcome. It does
not provide consensus, ordering, authorization, replay protection, or exactly
once delivery. Those remain the job of the durable log, command state machine,
and future authenticated consensus runtime.
