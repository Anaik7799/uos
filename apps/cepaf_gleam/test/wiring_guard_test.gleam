/// WIRING GUARD TEST — Must pass before ANY other test.
/// If a Model type changes without updating wiring_guard.gleam,
/// this test FAILS TO COMPILE — catching the break immediately.
///
/// SC-WIRE-001: This test is the canary in the coal mine.
/// RULE: After ANY Model/Msg type change, update wiring_guard.gleam FIRST.
import cepaf_gleam/testing/wiring_guard
import gleeunit/should

pub fn all_page_inits_compile_test() {
  wiring_guard.verify_all_inits()
  |> should.equal(37)
}

pub fn cortex_state_wired_test() {
  wiring_guard.verify_cortex_wiring()
  |> should.be_true()
}

pub fn federation_ha_wired_test() {
  wiring_guard.verify_federation_wiring()
  |> should.be_true()
}

pub fn bridge_gateway_wired_test() {
  wiring_guard.verify_bridge_wiring()
  |> should.be_true()
}

pub fn config_pii_model_wired_test() {
  wiring_guard.verify_config_wiring()
  |> should.be_true()
}

pub fn smriti_cache_wired_test() {
  wiring_guard.verify_smriti_wiring()
  |> should.be_true()
}

pub fn telemetry_ratelimit_wired_test() {
  wiring_guard.verify_telemetry_wiring()
  |> should.be_true()
}

pub fn agui_events_all_constructors_test() {
  wiring_guard.verify_agui_events()
  |> should.equal(32)
}

pub fn update_roundtrips_all_pass_test() {
  wiring_guard.verify_update_roundtrips()
  |> should.equal(21)
}

pub fn cortex_hitl_strict_test() {
  wiring_guard.verify_cortex_hitl_strict()
  |> should.be_true()
}

pub fn a2ui_coverage_test() {
  wiring_guard.verify_a2ui_coverage()
  |> should.be_true()
}

pub fn inference_tier_invariants_test() {
  wiring_guard.verify_inference_tier_invariants()
  |> should.be_true()
}

pub fn full_wiring_verification_test() {
  // 37 pages + 32 events + 6 models + 21 roundtrips + 3 strict + 9 ultra
  // + 1 auth + 6 pi + 32 page-specs = 147 (SC-PAGE-SPEC-005, SC-VAULT-009)
  wiring_guard.verify_all()
  |> should.equal(147)
}
