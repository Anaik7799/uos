//// =============================================================================
//// [C3I-SIL6-MSTS] Saṁvid Vajravyūha Unit Test Suite
//// =============================================================================

import cepaf_gleam/ha/samvid_vajravyuha.{
  LocalGemma4Mojo, canonical_holons, gleam_and_max_ratio, init_vajravyuha,
  local_processing_ratio, render_ansi_summary, reroute_intercepted_workload,
  state_to_json, target_to_string,
}
import gleam/json
import gleam/list
import gleam/string
import gleeunit/should

pub fn canonical_holons_count_test() {
  let holons = canonical_holons()
  should.equal(list.length(holons), 7)
}

pub fn local_processing_ratio_test() {
  let state = init_vajravyuha(False)
  let ratio = local_processing_ratio(state)
  should.be_true(ratio >. 0.928)
  should.be_true(ratio <. 0.929)

  let combined = gleam_and_max_ratio(state)
  should.be_true(combined >. 0.761)
  should.be_true(combined <. 0.762)
}

pub fn ansi_summary_test() {
  let state_nominal = init_vajravyuha(False)
  let summary_nom = render_ansi_summary(state_nominal)
  should.be_true(string.contains(summary_nom, "संविद् वज्रव्यूह"))
  should.be_true(string.contains(summary_nom, "NOMINAL PEERING"))

  let state_deg = init_vajravyuha(True)
  let summary_deg = render_ansi_summary(state_deg)
  should.be_true(string.contains(summary_deg, "AUTONOMOUS DEGRADATION ACTIVE"))
}

pub fn json_serialization_test() {
  let state = init_vajravyuha(False)
  let json_str = json.to_string(state_to_json(state))
  should.be_true(string.contains(json_str, "\"sanskrit_title\":\"संविद् वज्रव्यूह\""))
  should.be_true(string.contains(json_str, "\"total_workloads\":42"))
  should.be_true(string.contains(json_str, "\"local_workloads\":39"))
  should.be_true(string.contains(json_str, "\"gemma4_status\":\"BARE_METAL_ONLINE\""))
}

pub fn gemma4_reroute_test() {
  let #(target, explanation) =
    reroute_intercepted_workload("Claude", "EW Blackout / Network Severed")
  should.equal(target, LocalGemma4Mojo)
  should.equal(target_to_string(target), "LOCAL_GEMMA4_MOJO")
  should.be_true(string.contains(explanation, "H1_RASA_DHATU"))
  should.be_true(string.contains(explanation, "Bare-Metal Gemma 4 Mojo Kernel"))
}
