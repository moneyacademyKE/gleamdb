import aarondb/raft_durability as durability
import aarondb/raft_runtime as raft
import gleam/option.{Some}
import gleeunit/should

const store_path = "/Users/moe/Desktop/gleamdb/build/raft-durability-test.store"

const backup_path = "/Users/moe/Desktop/gleamdb/build/raft-durability-test.backup"

fn persisted() -> raft.Persisted {
  raft.Persisted(
    raft.HardState(4, Some("a"), 1),
    [raft.LogEntry(3, "set:a:1"), raft.LogEntry(4, "set:b:2")],
    Some(raft.Snapshot(0, 3, "state-through-0")),
    1,
  )
}

fn clear() {
  let _ = durability.remove_for_test(store_path)
  let _ = durability.remove_for_test(backup_path)
  Nil
}

pub fn fsynced_image_recovers_exact_acknowledged_state_after_restart_test() {
  clear()
  let store = durability.open(store_path)
  let expected = persisted()
  let assert Ok(Nil) = durability.save(store, expected, "app=state@1")
  let assert Ok(#(restored, image)) = durability.load(store)
  should.equal(restored, expected)
  should.equal(image, "app=state@1")
  clear()
}

pub fn torn_or_corrupt_store_returns_alarm_instead_of_repairing_test() {
  clear()
  let store = durability.open(store_path)
  let assert Ok(Nil) = durability.save(store, persisted(), "state")
  let assert Ok(Nil) = durability.overwrite_for_test(store_path, "half-written")
  case durability.load(store) {
    Error(durability.Corrupt(_)) -> Nil
    _ -> should.fail()
  }
  clear()
}

pub fn checksum_mismatch_returns_alarm_instead_of_decoding_payload_test() {
  clear()
  let store = durability.open(store_path)
  let assert Ok(Nil) = durability.save(store, persisted(), "state")
  // Valid-looking envelope prefix with an intentionally wrong digest.
  let assert Ok(Nil) =
    durability.overwrite_for_test(
      store_path,
      "AARONDB_RAFT_DURABILITY_V1\n00000000000000000000000000000000payload",
    )
  case durability.load(store) {
    Error(durability.Corrupt(_)) -> Nil
    _ -> should.fail()
  }
  clear()
}

pub fn snapshot_compaction_round_trips_equivalent_recovery_state_test() {
  clear()
  let leader = raft.bootstrap_leader(raft.new("a", [raft.Voter("a")]))
  let #(logged, _) =
    raft.handle(
      leader,
      raft.AppendEntries(
        0,
        "a",
        -1,
        0,
        [raft.LogEntry(0, "set:a:1"), raft.LogEntry(0, "set:b:2")],
        -1,
      ),
    )
  let committed = raft.commit_quorum(logged, 1, 1)
  let assert Ok(compacted) = raft.compact(committed, 1, "a=1,b=2")
  let store = durability.open(store_path)
  let assert Ok(Nil) =
    durability.save(store, raft.persist(compacted), "a=1,b=2")
  let assert Ok(#(saved, image)) = durability.load(store)
  let recovered = raft.recover("a", [raft.Voter("a")], saved)
  should.equal(image, "a=1,b=2")
  should.equal(recovered.hard.commit_index, compacted.hard.commit_index)
  should.equal(recovered.snapshot, compacted.snapshot)
  should.equal(recovered.last_applied, compacted.last_applied)
  clear()
}

pub fn verified_backup_exports_exact_recoverable_image_test() {
  clear()
  let store = durability.open(store_path)
  let assert Ok(Nil) = durability.save(store, persisted(), "exported")
  let assert Ok(Nil) = durability.backup(store, backup_path)
  let assert Ok(#(restored, image)) =
    durability.load(durability.open(backup_path))
  should.equal(restored, persisted())
  should.equal(image, "exported")
  clear()
}

pub fn interrupted_pre_rename_write_preserves_last_acknowledged_image_test() {
  clear()
  let store = durability.open(store_path)
  let expected = persisted()
  let assert Ok(Nil) = durability.save(store, expected, "acknowledged")
  let assert Ok(Nil) =
    durability.interrupt_before_rename_for_test(store_path, "torn-new-image")
  let assert Ok(#(restored, image)) = durability.load(store)
  should.equal(restored, expected)
  should.equal(image, "acknowledged")
  clear()
}

pub fn corrupt_primary_requires_verified_backup_and_explicit_operator_recovery_test() {
  clear()
  let store = durability.open(store_path)
  let expected = persisted()
  let assert Ok(Nil) = durability.save(store, expected, "recoverable")
  let assert Ok(Nil) = durability.backup(store, backup_path)
  let assert Ok(Nil) =
    durability.overwrite_for_test(store_path, "corrupt-primary")
  case durability.load(store) {
    Error(durability.Corrupt(_)) -> Nil
    _ -> should.fail()
  }
  let assert Ok(#(restored, image)) =
    durability.load(durability.open(backup_path))
  should.equal(restored, expected)
  should.equal(image, "recoverable")
  clear()
}
