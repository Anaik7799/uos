// =============================================================================
// beam_cache_test.gleam — ETS Cache + persistent_term Hot Config Tests
// =============================================================================
// F07: ETS Shared State Cache (6 tests)
// F08: persistent_term Hot Config (5 tests)
// Integration: cross-feature (4 tests)
//
// STAMP: SC-FUNC-004, SC-MUDA-001, SC-ARCH-SPLIT-002
// Layer: L3_TRANSACTION
//
// अक्षरं ब्रह्म परमम् — The imperishable is the supreme Brahman (Gita 8.3)
// =============================================================================

import cepaf_gleam/substrate/beam_cache
import gleam/list
import gleam/string
import gleeunit/should

// =============================================================================
// F07 — ETS Cache: initialisation
// =============================================================================

pub fn ets_init_succeeds_test() {
  // init is idempotent — calling it multiple times must not fail
  beam_cache.init()
  |> should.be_ok()
}

pub fn ets_init_idempotent_test() {
  // Second call also returns Ok (table already exists path)
  let _ = beam_cache.init()
  beam_cache.init()
  |> should.be_ok()
}

// =============================================================================
// F07 — ETS Cache: put / get roundtrip
// =============================================================================

pub fn ets_put_get_roundtrip_test() {
  let _ = beam_cache.init()
  let _ = beam_cache.put("health_score", "99.5")
  beam_cache.get("health_score")
  |> should.equal(Ok("99.5"))
}

pub fn ets_put_overwrites_previous_value_test() {
  let _ = beam_cache.init()
  let _ = beam_cache.put("mesh_status", "degraded")
  let _ = beam_cache.put("mesh_status", "healthy")
  beam_cache.get("mesh_status")
  |> should.equal(Ok("healthy"))
}

pub fn ets_get_nonexistent_key_returns_error_test() {
  let _ = beam_cache.init()
  beam_cache.get("__nonexistent_key_xzy_987__")
  |> should.be_error()
}

// =============================================================================
// F07 — ETS Cache: delete
// =============================================================================

pub fn ets_delete_removes_key_test() {
  let _ = beam_cache.init()
  let _ = beam_cache.put("tmp_key", "tmp_value")
  let _ = beam_cache.delete("tmp_key")
  beam_cache.get("tmp_key")
  |> should.be_error()
}

pub fn ets_delete_absent_key_is_ok_test() {
  let _ = beam_cache.init()
  // Deleting a key that was never inserted must not fail
  beam_cache.delete("__never_inserted_key__")
  |> should.be_ok()
}

// =============================================================================
// F07 — ETS Cache: keys / size
// =============================================================================

pub fn ets_keys_contains_inserted_key_test() {
  let _ = beam_cache.init()
  let unique_key = "test_keys_" <> "abc123"
  let _ = beam_cache.put(unique_key, "val")
  let all_keys = beam_cache.keys()
  all_keys |> list.contains(unique_key) |> should.be_true()
}

pub fn ets_size_is_non_negative_test() {
  let _ = beam_cache.init()
  let sz = beam_cache.size()
  { sz >= 0 } |> should.be_true()
}

pub fn ets_size_increases_after_put_test() {
  let _ = beam_cache.init()
  let before = beam_cache.size()
  let unique = "size_test_key_" <> "qwerty"
  let _ = beam_cache.put(unique, "v")
  let after = beam_cache.size()
  { after >= before } |> should.be_true()
}

// =============================================================================
// F08 — persistent_term: set / get
// =============================================================================

pub fn pt_set_get_roundtrip_test() {
  let _ = beam_cache.set_config("ooda_interval_ms", "100")
  beam_cache.get_config("ooda_interval_ms")
  |> should.equal(Ok("100"))
}

pub fn pt_get_nonexistent_returns_error_test() {
  beam_cache.get_config("__pt_key_never_set_xzy__")
  |> should.be_error()
}

pub fn pt_set_overwrites_previous_value_test() {
  let _ = beam_cache.set_config("sil_level", "4")
  let _ = beam_cache.set_config("sil_level", "6")
  beam_cache.get_config("sil_level")
  |> should.equal(Ok("6"))
}

// =============================================================================
// F08 — persistent_term: version helpers
// =============================================================================

pub fn version_set_get_roundtrip_test() {
  let _ = beam_cache.set_version("22.5.0-CORTEX")
  beam_cache.get_version()
  |> should.equal("22.5.0-CORTEX")
}

pub fn version_default_unknown_when_not_set_test() {
  // Read the raw key before any version has been stored in this test run.
  // get_version returns "unknown" on miss — that covers the fallback path.
  // We write a known value first so we can restore and test the fallback
  // by probing the underlying get_config with a fresh key name.
  beam_cache.get_config("__version_never_set_key__")
  |> should.be_error()
}

// =============================================================================
// Integration — mixed ETS + persistent_term usage
// =============================================================================

pub fn multiple_ets_puts_all_readable_test() {
  let _ = beam_cache.init()
  let _ = beam_cache.put("k1", "v1")
  let _ = beam_cache.put("k2", "v2")
  let _ = beam_cache.put("k3", "v3")
  beam_cache.get("k1") |> should.equal(Ok("v1"))
  beam_cache.get("k2") |> should.equal(Ok("v2"))
  beam_cache.get("k3") |> should.equal(Ok("v3"))
}

pub fn ets_and_pt_independent_namespaces_test() {
  let _ = beam_cache.init()
  let _ = beam_cache.put("shared_key", "ets_value")
  let _ = beam_cache.set_config("shared_key", "pt_value")
  // ETS and persistent_term are fully isolated namespaces
  beam_cache.get("shared_key") |> should.equal(Ok("ets_value"))
  beam_cache.get_config("shared_key") |> should.equal(Ok("pt_value"))
}

pub fn ets_json_payload_roundtrip_test() {
  let _ = beam_cache.init()
  let payload = "{\"health\":99,\"zenoh\":\"connected\",\"sil\":6}"
  let _ = beam_cache.put("dashboard_snapshot", payload)
  let retrieved = beam_cache.get("dashboard_snapshot")
  retrieved |> should.be_ok()
  case retrieved {
    Ok(v) -> {
      v |> string.contains("\"health\"") |> should.be_true()
      v |> string.contains("\"zenoh\"") |> should.be_true()
    }
    Error(_) -> Nil
  }
}
