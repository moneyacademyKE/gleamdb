import aarondb/identity
import gleeunit/should

fn limits() -> identity.RpcLimits {
  identity.RpcLimits(1024, 3)
}

fn trusted() -> identity.TrustStore {
  identity.new("cluster-a", ["root-a"], ["node-a"])
  |> identity.put_certificate(identity.Certificate(
    "node-a",
    "fp-a",
    "root-a",
    identity.Active(1),
  ))
}

pub fn trusted_member_with_bounded_rpc_is_admitted_test() {
  should.equal(
    identity.admit_peer(trusted(), "node-a", "fp-a", limits(), 512),
    Ok(Nil),
  )
}

pub fn wrong_unknown_and_untrusted_certificates_are_rejected_test() {
  should.equal(
    identity.admit_peer(trusted(), "node-b", "fp-a", limits(), 1),
    Error(identity.WrongCertificate("node-b", "node-a")),
  )
  should.equal(
    identity.admit_peer(trusted(), "node-a", "missing", limits(), 1),
    Error(identity.UnknownCertificate),
  )
  let untrusted =
    identity.new("cluster-a", ["root-a"], ["node-a"])
    |> identity.put_certificate(identity.Certificate(
      "node-a",
      "fp-a",
      "evil",
      identity.Active(1),
    ))
  should.equal(
    identity.admit_peer(untrusted, "node-a", "fp-a", limits(), 1),
    Error(identity.UntrustedIssuer("evil")),
  )
}

pub fn rotation_and_revocation_fail_closed_test() {
  let rotated =
    trusted()
    |> identity.put_certificate(identity.Certificate(
      "node-a",
      "fp-b",
      "root-a",
      identity.Active(2),
    ))
  should.equal(
    identity.admit_peer(rotated, "node-a", "fp-a", limits(), 1),
    Error(identity.InactiveCertificate),
  )
  let revoked = identity.revoke(rotated, "fp-b")
  should.equal(
    identity.admit_peer(revoked, "node-a", "fp-b", limits(), 1),
    Error(identity.RevokedCertificate),
  )
}

pub fn unauthorized_member_and_malicious_rpc_are_rejected_test() {
  let non_member =
    identity.new("cluster-a", ["root-a"], ["node-a"])
    |> identity.put_certificate(identity.Certificate(
      "node-b",
      "fp-b",
      "root-a",
      identity.Active(1),
    ))
  should.equal(
    identity.admit_peer(non_member, "node-b", "fp-b", limits(), 1),
    Error(identity.UnauthorizedMember("node-b")),
  )
  should.equal(
    identity.admit_peer(trusted(), "node-a", "fp-a", limits(), 1025),
    Error(identity.InvalidRpcSize(1025, 1024)),
  )
}

pub fn reconnects_are_explicitly_bounded_test() {
  should.equal(identity.reconnect(limits(), 0), Ok(Nil))
  should.equal(identity.reconnect(limits(), 2), Ok(Nil))
  should.equal(
    identity.reconnect(limits(), 3),
    Error(identity.ReconnectExhausted(3)),
  )
}

pub fn bootstrap_requires_empty_trust_and_membership_test() {
  should.equal(
    identity.authorize_bootstrap(identity.new("fresh", [], []), ["node-a"]),
    Ok(Nil),
  )
  should.equal(
    identity.authorize_bootstrap(trusted(), ["node-a"]),
    Error(identity.BootstrapDenied),
  )
}

pub fn forced_recovery_and_inspection_persist_alarms_test() {
  let recovery =
    identity.clean_recovery()
    |> identity.force_recovery("lost-quorum")
    |> identity.inspect_recovery(["node-a"], ["node-b"], False)
  should.equal(recovery.force_recovery_used, True)
  should.equal(recovery.alarms, [
    identity.MembershipMismatch(["node-a"], ["node-b"]),
    identity.TrustMaterialMissing,
    identity.UnsafeRecoveryAcknowledged("lost-quorum"),
  ])
}
