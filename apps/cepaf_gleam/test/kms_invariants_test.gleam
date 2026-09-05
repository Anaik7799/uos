import cepaf_gleam/kms/catalog.{Checkpoint}
import gleam/dict
import gleam/erlang/process
import gleam/option.{None}

// SC-SEC-001 Verification: Zero-Trust Key Management
// This test simulates the invariants that must hold for the KMS Catalog.

pub fn sc_sec_001_unauthorized_rotation_test() {
  let assert Ok(hub) = catalog.start("verifier-1", "memory::", None)

  // Invariant 1: Cannot rotate a non-existent key
  let res1 = process.call(hub, 1000, catalog.RotateKey("ghost-key", "hash", _))
  let assert Error("Checkpoint not found for rotation") = res1

  // Set up a valid key
  let cp = Checkpoint("valid-key", "hash1", "time", dict.new())
  let assert Ok(_) = process.call(hub, 1000, catalog.Commit(cp, _))

  // Invariant 2: Cannot revoke a non-existent key
  let res2 = process.call(hub, 1000, catalog.RevokeKey("ghost-key", _))
  let assert Error("Checkpoint not found for revocation") = res2

  // Invariant 3: Rollback must fail if key doesn't exist
  let res3 = process.call(hub, 1000, catalog.Rollback("ghost-key", _))
  let assert Error("Checkpoint not found for rollback") = res3

  // Clean up
  let _ = process.send(hub, catalog.Shutdown)
  Nil
}
