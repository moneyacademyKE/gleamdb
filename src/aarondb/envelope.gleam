//// # envelope — canonical Ed25519-signed generic facts and events
////
//// `EnvelopeV1` has deliberately boring bytes: a fixed tag/version followed by
//// length-delimited fields in this exact order. The unsigned frame is hashed
//// with its domain and then signed. It is unrelated to local capability auth.

import gleam/bit_array
import gleam/list
import gleam/string

pub type Envelope {
  Envelope(
    version: Int,
    domain: String,
    payload: BitArray,
    payload_hash: BitArray,
    author: BitArray,
    parents: List(BitArray),
    logical_clock: Int,
    key_epoch: Int,
    signature: BitArray,
  )
}

pub type KeyState {
  Active(epoch: Int)
  Rotated(epoch: Int)
  Revoked
}

pub type Key {
  Key(public_key: BitArray, state: KeyState)
}

pub type Keyring {
  Keyring(keys: List(Key), maximum_frame_bytes: Int, maximum_parents: Int)
}

pub type EnvelopeError {
  UnsupportedVersion(Int)
  WrongDomain(expected: String, actual: String)
  InvalidPayloadHash
  InvalidSignature
  UnknownAuthor
  InactiveKey
  RevokedKey
  WrongKeyEpoch(expected: Int, actual: Int)
  FrameTooLarge(actual: Int, maximum: Int)
  TooManyParents(actual: Int, maximum: Int)
  NegativeLogicalClock
}

pub const version_v1 = 1

pub fn new_keyring(maximum_frame_bytes: Int, maximum_parents: Int) -> Keyring {
  Keyring([], maximum_frame_bytes, maximum_parents)
}

/// Adding the same public key replaces its lifecycle state; no map ordering is
/// involved in either key lookup or canonical envelope bytes.
pub fn put_key(keyring: Keyring, key: Key) -> Keyring {
  Keyring(..keyring, keys: [
    key,
    ..list.filter(keyring.keys, fn(existing) {
      existing.public_key != key.public_key
    })
  ])
}

pub fn revoke(keyring: Keyring, public_key: BitArray) -> Keyring {
  put_key(keyring, Key(public_key, Revoked))
}

pub fn payload_digest(payload: BitArray) -> BitArray {
  sha256(payload)
}

pub fn public_key(private_key: BitArray) -> BitArray {
  ed25519_public_key(private_key)
}

pub fn sign(
  domain: String,
  payload: BitArray,
  author_private_key: BitArray,
  parents: List(BitArray),
  logical_clock: Int,
  key_epoch: Int,
) -> Envelope {
  let author = public_key(author_private_key)
  let unsigned =
    unsigned_frame(domain, payload, author, parents, logical_clock, key_epoch)
  let digest = sha256(unsigned)
  Envelope(
    version_v1,
    domain,
    payload,
    payload_digest(payload),
    author,
    parents,
    logical_clock,
    key_epoch,
    ed25519_sign(digest, author_private_key),
  )
}

/// Verification binds the requested application domain as well as the exact
/// unsigned frame. A valid signature for another domain is not reusable here.
pub fn verify(
  envelope: Envelope,
  domain: String,
  keyring: Keyring,
) -> Result(Nil, EnvelopeError) {
  case envelope.version != version_v1 {
    True -> Error(UnsupportedVersion(envelope.version))
    False ->
      case envelope.domain != domain {
        True -> Error(WrongDomain(domain, envelope.domain))
        False -> verify_shape(envelope, keyring)
      }
  }
}

pub fn canonical_bytes(envelope: Envelope) -> BitArray {
  <<
    "AARON-ENVELOPE":utf8,
    envelope.version:32,
    { frame_string(envelope.domain) }:bits,
    { frame(envelope.payload) }:bits,
    { frame(envelope.payload_hash) }:bits,
    { frame(envelope.author) }:bits,
    { frame_parents(envelope.parents) }:bits,
    envelope.logical_clock:64,
    envelope.key_epoch:32,
    { frame(envelope.signature) }:bits,
  >>
}

fn verify_shape(
  envelope: Envelope,
  keyring: Keyring,
) -> Result(Nil, EnvelopeError) {
  case envelope.logical_clock < 0 {
    True -> Error(NegativeLogicalClock)
    False ->
      case list.length(envelope.parents) > keyring.maximum_parents {
        True ->
          Error(TooManyParents(
            list.length(envelope.parents),
            keyring.maximum_parents,
          ))
        False ->
          case
            bit_array.byte_size(canonical_bytes(envelope))
            > keyring.maximum_frame_bytes
          {
            True ->
              Error(FrameTooLarge(
                bit_array.byte_size(canonical_bytes(envelope)),
                keyring.maximum_frame_bytes,
              ))
            False -> verify_hash_and_key(envelope, keyring)
          }
      }
  }
}

fn verify_hash_and_key(
  envelope: Envelope,
  keyring: Keyring,
) -> Result(Nil, EnvelopeError) {
  case envelope.payload_hash != payload_digest(envelope.payload) {
    True -> Error(InvalidPayloadHash)
    False ->
      case
        list.find(keyring.keys, fn(key) { key.public_key == envelope.author })
      {
        Error(Nil) -> Error(UnknownAuthor)
        Ok(Key(_, Revoked)) -> Error(RevokedKey)
        Ok(Key(_, Rotated(_epoch))) -> Error(InactiveKey)
        Ok(Key(_, Active(epoch))) ->
          case epoch != envelope.key_epoch {
            True -> Error(WrongKeyEpoch(epoch, envelope.key_epoch))
            False -> verify_signature(envelope)
          }
      }
  }
}

fn verify_signature(envelope: Envelope) -> Result(Nil, EnvelopeError) {
  let digest =
    sha256(unsigned_frame(
      envelope.domain,
      envelope.payload,
      envelope.author,
      envelope.parents,
      envelope.logical_clock,
      envelope.key_epoch,
    ))
  case ed25519_verify(digest, envelope.signature, envelope.author) {
    True -> Ok(Nil)
    False -> Error(InvalidSignature)
  }
}

fn unsigned_frame(
  domain: String,
  payload: BitArray,
  author: BitArray,
  parents: List(BitArray),
  logical_clock: Int,
  key_epoch: Int,
) -> BitArray {
  <<
    "AARON-ENVELOPE-V1-SIGNATURE":utf8,
    { frame_string(domain) }:bits,
    { frame(payload) }:bits,
    { frame(author) }:bits,
    { frame_parents(parents) }:bits,
    logical_clock:64,
    key_epoch:32,
  >>
}

fn frame_string(value: String) -> BitArray {
  <<string.length(value):32, value:utf8>>
}

fn frame(value: BitArray) -> BitArray {
  <<bit_array.byte_size(value):32, value:bits>>
}

fn frame_parents(parents: List(BitArray)) -> BitArray {
  <<list.length(parents):32, { parents_frame(parents) }:bits>>
}

fn parents_frame(parents: List(BitArray)) -> BitArray {
  case parents {
    [] -> <<>>
    [parent, ..rest] -> <<{ frame(parent) }:bits, { parents_frame(rest) }:bits>>
  }
}

@external(erlang, "aarondb_envelope_ffi", "sha256")
fn sha256(data: BitArray) -> BitArray

@external(erlang, "aarondb_envelope_ffi", "ed25519_sign")
fn ed25519_sign(data: BitArray, private_key: BitArray) -> BitArray

@external(erlang, "aarondb_envelope_ffi", "ed25519_verify")
fn ed25519_verify(
  data: BitArray,
  signature: BitArray,
  public_key: BitArray,
) -> Bool

@external(erlang, "aarondb_envelope_ffi", "ed25519_public_key")
fn ed25519_public_key(private_key: BitArray) -> BitArray
