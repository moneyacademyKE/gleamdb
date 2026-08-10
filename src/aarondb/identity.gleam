//// # identity — durable node trust, mTLS policy, and safe recovery reference surface
////
//// This is a policy model, not a socket implementation. A real transport presents
//// peer certificate facts here *before* it delivers a Raft RPC. Durable adapters
//// persist `TrustStore` and `RecoveryState` atomically with their authority files.

import gleam/list
import gleam/option.{type Option, None, Some}

pub type CertificateState {
  Active(epoch: Int)
  Rotated(epoch: Int)
  Revoked
}

pub type Certificate {
  Certificate(
    node: String,
    fingerprint: String,
    issuer: String,
    state: CertificateState,
  )
}

pub type TrustStore {
  TrustStore(
    cluster: String,
    trusted_issuers: List(String),
    certificates: List(Certificate),
    members: List(String),
  )
}

pub type RpcLimits {
  RpcLimits(maximum_bytes: Int, maximum_attempts: Int)
}

pub type PeerError {
  UnknownCertificate
  WrongCertificate(expected_node: String, certificate_node: String)
  UntrustedIssuer(String)
  InactiveCertificate
  RevokedCertificate
  UnauthorizedMember(String)
  InvalidRpcSize(actual: Int, maximum: Int)
  InvalidReconnectLimit
  ReconnectExhausted(attempts: Int)
  BootstrapDenied
}

pub type RecoveryAlarm {
  UnsafeRecoveryAcknowledged(reason: String)
  TrustMaterialMissing
  MembershipMismatch(expected: List(String), actual: List(String))
}

pub type RecoveryState {
  RecoveryState(alarms: List(RecoveryAlarm), force_recovery_used: Bool)
}

pub fn new(
  cluster: String,
  trusted_issuers: List(String),
  members: List(String),
) -> TrustStore {
  TrustStore(cluster, trusted_issuers, [], members)
}

/// Replacing a fingerprint is an explicit rotation. Existing certificates are
/// retained only as `Rotated` evidence, never as valid transport credentials.
pub fn put_certificate(
  store: TrustStore,
  certificate: Certificate,
) -> TrustStore {
  TrustStore(..store, certificates: [
    certificate,
    ..list.map(store.certificates, fn(existing) {
      let Certificate(node, fingerprint, issuer, state) = existing
      case node == certificate.node && fingerprint != certificate.fingerprint {
        True -> Certificate(node, fingerprint, issuer, rotate(state))
        False -> existing
      }
    })
  ])
}

pub fn revoke(store: TrustStore, fingerprint: String) -> TrustStore {
  TrustStore(
    ..store,
    certificates: list.map(store.certificates, fn(certificate) {
      let Certificate(node, saved, issuer, state) = certificate
      case saved == fingerprint {
        True -> Certificate(node, saved, issuer, Revoked)
        False -> Certificate(node, saved, issuer, state)
      }
    }),
  )
}

/// Mutual TLS admission: issuer, presented identity, active certificate, and
/// committed membership must all agree. Nothing reaches Raft before this passes.
pub fn admit_peer(
  store: TrustStore,
  expected_node: String,
  fingerprint: String,
  limits: RpcLimits,
  rpc_bytes: Int,
) -> Result(Nil, PeerError) {
  case limits.maximum_bytes < 1 || limits.maximum_attempts < 1 {
    True -> Error(InvalidReconnectLimit)
    False ->
      case rpc_bytes > limits.maximum_bytes || rpc_bytes < 0 {
        True -> Error(InvalidRpcSize(rpc_bytes, limits.maximum_bytes))
        False -> validate_certificate(store, expected_node, fingerprint)
      }
  }
}

/// `attempt` is zero based. Callers must stop after this returns exhaustion;
/// this deliberately refuses an unbounded retry loop disguised as resilience.
pub fn reconnect(limits: RpcLimits, attempt: Int) -> Result(Nil, PeerError) {
  case limits.maximum_attempts < 1 || attempt < 0 {
    True -> Error(InvalidReconnectLimit)
    False ->
      case attempt < limits.maximum_attempts {
        True -> Ok(Nil)
        False -> Error(ReconnectExhausted(attempt))
      }
  }
}

/// New-cluster bootstrap may install the initial member set only when the trust
/// store is empty. Existing clusters require committed membership changes.
pub fn authorize_bootstrap(
  store: TrustStore,
  requested_members: List(String),
) -> Result(Nil, PeerError) {
  case
    store.members == [] && store.certificates == [] && requested_members != []
  {
    True -> Ok(Nil)
    False -> Error(BootstrapDenied)
  }
}

pub fn clean_recovery() -> RecoveryState {
  RecoveryState([], False)
}

/// A forced repair is an operator action, not an automatic healing path. Its
/// durable alarm remains until an operator explicitly records the incident.
pub fn force_recovery(state: RecoveryState, reason: String) -> RecoveryState {
  RecoveryState([UnsafeRecoveryAcknowledged(reason), ..state.alarms], True)
}

pub fn inspect_recovery(
  state: RecoveryState,
  expected_members: List(String),
  actual_members: List(String),
  trust_material_present: Bool,
) -> RecoveryState {
  let with_trust = case trust_material_present {
    True -> state.alarms
    False -> [TrustMaterialMissing, ..state.alarms]
  }
  let alarms = case expected_members == actual_members {
    True -> with_trust
    False -> [
      MembershipMismatch(expected_members, actual_members),
      ..with_trust
    ]
  }
  RecoveryState(alarms, state.force_recovery_used)
}

pub fn fingerprint_for(store: TrustStore, node: String) -> Option(String) {
  list.find(store.certificates, fn(certificate) {
    certificate.node == node && is_active(certificate.state)
  })
  |> certificate_fingerprint
}

fn certificate_fingerprint(result: Result(Certificate, Nil)) -> Option(String) {
  case result {
    Ok(Certificate(_, fingerprint, _, _)) -> Some(fingerprint)
    Error(Nil) -> None
  }
}

fn is_active(state: CertificateState) -> Bool {
  case state {
    Active(_) -> True
    _ -> False
  }
}

fn validate_certificate(
  store: TrustStore,
  expected_node: String,
  fingerprint: String,
) -> Result(Nil, PeerError) {
  case find_certificate(store.certificates, fingerprint) {
    None -> Error(UnknownCertificate)
    Some(Certificate(node, _, _issuer, _)) if node != expected_node ->
      Error(WrongCertificate(expected_node, node))
    Some(Certificate(_, _, issuer, state)) ->
      case list.contains(store.trusted_issuers, issuer) {
        False -> Error(UntrustedIssuer(issuer))
        True -> validate_certificate_state(store.members, expected_node, state)
      }
  }
}

fn validate_certificate_state(
  members: List(String),
  node: String,
  state: CertificateState,
) -> Result(Nil, PeerError) {
  case state {
    Revoked -> Error(RevokedCertificate)
    Rotated(_) -> Error(InactiveCertificate)
    Active(_) ->
      case list.contains(members, node) {
        True -> Ok(Nil)
        False -> Error(UnauthorizedMember(node))
      }
  }
}

fn find_certificate(
  certificates: List(Certificate),
  fingerprint: String,
) -> Option(Certificate) {
  list.find(certificates, fn(certificate) {
    certificate.fingerprint == fingerprint
  })
  |> result_to_option
}

fn result_to_option(result: Result(Certificate, Nil)) -> Option(Certificate) {
  case result {
    Ok(certificate) -> Some(certificate)
    Error(Nil) -> None
  }
}

fn rotate(state: CertificateState) -> CertificateState {
  case state {
    Active(epoch) -> Rotated(epoch)
    other -> other
  }
}
