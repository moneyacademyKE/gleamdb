import aarondb/envelope
import gleam/bit_array
import gleeunit/should

const private_key = <<"01234567890123456789012345678901":utf8>>

pub fn signed_envelope_has_stable_canonical_bytes_and_verifies_test() {
  let signed =
    sample("fact", <<"payload":utf8>>, [
      <<"parent-a":utf8>>,
      <<"parent-b":utf8>>,
    ])
  let ring = trusted_ring(signed)
  should.equal(envelope.verify(signed, "fact", ring), Ok(Nil))
  should.equal(
    envelope.canonical_bytes(signed),
    envelope.canonical_bytes(signed),
  )
}

pub fn payload_signature_and_parent_mutations_are_rejected_test() {
  let signed = sample("fact", <<"payload":utf8>>, [<<"parent-a":utf8>>])
  let ring = trusted_ring(signed)
  should.equal(
    envelope.verify(
      envelope.Envelope(..signed, payload: <<"altered":utf8>>),
      "fact",
      ring,
    ),
    Error(envelope.InvalidPayloadHash),
  )
  should.equal(
    envelope.verify(
      envelope.Envelope(..signed, parents: [<<"other":utf8>>]),
      "fact",
      ring,
    ),
    Error(envelope.InvalidSignature),
  )
  should.equal(
    envelope.verify(
      envelope.Envelope(..signed, signature: <<0, signed.signature:bits>>),
      "fact",
      ring,
    ),
    Error(envelope.InvalidSignature),
  )
}

pub fn domains_versions_and_decode_limits_are_explicit_test() {
  let signed = sample("fact", <<"payload":utf8>>, [<<"parent":utf8>>])
  let ring = trusted_ring(signed)
  should.equal(
    envelope.verify(signed, "other", ring),
    Error(envelope.WrongDomain("other", "fact")),
  )
  should.equal(
    envelope.verify(envelope.Envelope(..signed, version: 2), "fact", ring),
    Error(envelope.UnsupportedVersion(2)),
  )
  should.equal(
    envelope.verify(signed, "fact", envelope.new_keyring(10, 0)),
    Error(envelope.TooManyParents(1, 0)),
  )
  should.equal(
    envelope.verify(
      envelope.Envelope(..signed, parents: []),
      "fact",
      envelope.new_keyring(10, 8),
    ),
    Error(envelope.FrameTooLarge(
      bit_array.byte_size(envelope.canonical_bytes(
        envelope.Envelope(..signed, parents: []),
      )),
      10,
    )),
  )
}

pub fn rotation_revocation_and_epoch_are_policy_outcomes_test() {
  let signed = sample("fact", <<"payload":utf8>>, [])
  let base = trusted_ring(signed)
  let rotated =
    envelope.put_key(base, envelope.Key(signed.author, envelope.Rotated(1)))
  let revoked = envelope.revoke(base, signed.author)
  let wrong_epoch =
    envelope.put_key(base, envelope.Key(signed.author, envelope.Active(2)))
  should.equal(
    envelope.verify(signed, "fact", rotated),
    Error(envelope.InactiveKey),
  )
  should.equal(
    envelope.verify(signed, "fact", revoked),
    Error(envelope.RevokedKey),
  )
  should.equal(
    envelope.verify(signed, "fact", wrong_epoch),
    Error(envelope.WrongKeyEpoch(2, 1)),
  )
}

fn sample(
  domain: String,
  payload: BitArray,
  parents: List(BitArray),
) -> envelope.Envelope {
  envelope.sign(domain, payload, private_key, parents, 42, 1)
}

fn trusted_ring(signed: envelope.Envelope) -> envelope.Keyring {
  envelope.new_keyring(4096, 8)
  |> envelope.put_key(envelope.Key(signed.author, envelope.Active(1)))
}
