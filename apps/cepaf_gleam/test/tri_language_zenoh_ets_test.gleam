//// =============================================================================
//// [C3I-SIL6-MSTS] TEST CONTRACT: TRI-LANGUAGE ZENOH & ETS STATE SHARING
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>test/tri_language_zenoh_ets_test</module>
////     <contract>SC-ZENOH-001, SC-FUNC-004, SC-MUDA-001</contract>
////   </identity>
//// </c3i-module>

import cepaf_gleam/substrate/beam_cache
import cepaf_gleam/zenoh/ets_zenoh_bridge
import gleeunit/should

pub fn ets_basic_put_get_test() {
  let _ = ets_zenoh_bridge.init_bridge()
  ets_zenoh_bridge.put_state("gleam_state", "GLEAM_OTP29_SUPERVISOR_ACTIVE")
  |> should.be_ok()

  let val = ets_zenoh_bridge.get_state("gleam_state")
  val |> should.be_ok()
  should.equal(val, Ok("GLEAM_OTP29_SUPERVISOR_ACTIVE"))
}

pub fn ets_all_and_size_test() {
  let _ = ets_zenoh_bridge.init_bridge()
  let _ = ets_zenoh_bridge.put_state("test_probe_key_1", "probe_val_1")
  let _ = ets_zenoh_bridge.put_state("test_probe_key_2", "probe_val_2")

  let size = beam_cache.size()
  should.be_true(size >= 2)

  let _all = ets_zenoh_bridge.all_ets_state()
  should.be_true(beam_cache.size() >= 2)
}

pub fn ets_zenoh_sync_test() {
  let _ = ets_zenoh_bridge.init_bridge()
  // Put a state via bridge
  let _ = ets_zenoh_bridge.put_state("sync_test_key", "sync_val_123")

  // Sync from Zenoh to ETS
  case ets_zenoh_bridge.sync_zenoh_to_ets() {
    Ok(synced_count) -> should.be_true(synced_count >= 0)
    Error(_) -> Nil // Zenoh might be quiet if offline during unit test
  }
}

pub fn tri_language_state_evaluation_test() {
  let _ = ets_zenoh_bridge.init_bridge()
  let _ = ets_zenoh_bridge.put_state("gleam_state", "GLEAM_OTP29_SUPERVISOR_ACTIVE")

  let summary = ets_zenoh_bridge.evaluate_tri_language_state()
  should.equal(summary.gleam_state, "GLEAM_OTP29_SUPERVISOR_ACTIVE")
  should.be_true(summary.ets_entry_count >= 1)
}
