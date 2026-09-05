import cepaf_gleam/kms/catalog.{Checkpoint}
import gleam/dict
import gleam/erlang/process
import gleam/option.{None}

pub fn kms_catalog_lifecycle_test() {
  // Start the catalog actor with no Zenoh session
  let assert Ok(catalog_hub) = catalog.start("test-actor-1", "memory::", None)

  // 1. Commit a key
  let cp1 =
    Checkpoint(
      id: "key-1",
      hash: "initial-hash-abc",
      timestamp: "2026-04-01T12:00:00Z",
      metadata: dict.new(),
    )

  let assert Ok("key-1") =
    process.call(catalog_hub, 1000, catalog.Commit(cp1, _))

  // Verify it exists
  let assert True = process.call(catalog_hub, 1000, catalog.Verify("key-1", _))

  // 2. Rotate the key
  let assert Ok("key-1") =
    process.call(catalog_hub, 1000, catalog.RotateKey(
      "key-1",
      "new-hash-xyz",
      _,
    ))

  // Verify it still exists after rotation
  let assert True = process.call(catalog_hub, 1000, catalog.Verify("key-1", _))

  // 3. Revoke the key
  let assert Ok(Nil) =
    process.call(catalog_hub, 1000, catalog.RevokeKey("key-1", _))

  // Verify it no longer exists
  let assert False = process.call(catalog_hub, 1000, catalog.Verify("key-1", _))

  // Clean up
  let _ = process.send(catalog_hub, catalog.Shutdown)
  Nil
}
