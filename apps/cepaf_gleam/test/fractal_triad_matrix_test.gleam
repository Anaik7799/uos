//// [C3I-SIL6-MSTS] MODULE CONTRACT
//// Fractal Triad Matrix Unit & Invariant Test Suite (Layers x Components x Processes)
//// STAMP: SC-GLM-UI-001, SC-ZMOF-001, SC-CHECKLIST-001, SC-MUDA-001

import cepaf_gleam/verification/fractal_triad_matrix_engine.{
  L0Constitutional, L5CognitiveOoda, L9BiosemioticTransKnowledge,
  canonical_layers, encode_claude_verification_json, encode_triad_matrix_json,
  evaluate_fractal_triad_matrix, generate_canonical_tensor_nodes, layer_to_code,
  layer_to_name, verify_with_claude,
}
import gleam/list
import gleam/string
import gleeunit/should

pub fn all_10_layers_represented_test() {
  let layers = canonical_layers()
  list.length(layers) |> should.equal(10)

  let codes = list.map(layers, layer_to_code)
  list.length(codes) |> should.equal(10)
  list.contains(codes, "L0") |> should.be_true()
  list.contains(codes, "L1") |> should.be_true()
  list.contains(codes, "L2") |> should.be_true()
  list.contains(codes, "L3") |> should.be_true()
  list.contains(codes, "L4") |> should.be_true()
  list.contains(codes, "L5") |> should.be_true()
  list.contains(codes, "L6") |> should.be_true()
  list.contains(codes, "L7") |> should.be_true()
  list.contains(codes, "L8") |> should.be_true()
  list.contains(codes, "L9") |> should.be_true()
}

pub fn layer_naming_convention_test() {
  layer_to_name(L0Constitutional) |> should.equal("L0_Constitutional")
  layer_to_name(L5CognitiveOoda) |> should.equal("L5_Cognitive_OODA")
  layer_to_name(L9BiosemioticTransKnowledge)
  |> should.equal("L9_Biosemiotic_TransKnowledge")
}

pub fn all_canonical_nodes_verified_test() {
  let nodes = generate_canonical_tensor_nodes()
  let has_nodes = list.length(nodes) >= 20
  has_nodes |> should.be_true()

  let all_verified =
    list.all(nodes, fn(node) { node.verified && node.status == "OPERATIONAL" })
  all_verified |> should.be_true()
}

pub fn every_layer_has_tensor_projections_test() {
  let nodes = generate_canonical_tensor_nodes()
  let layers = canonical_layers()

  let all_layers_projected =
    list.all(layers, fn(l) {
      let code = layer_to_code(l)
      list.any(nodes, fn(n) { n.layer_code == code })
    })
  all_layers_projected |> should.be_true()
}

pub fn triad_evaluation_predicate_passes_test() {
  let eval = evaluate_fractal_triad_matrix()
  eval.all_nodes_verified |> should.be_true()
  eval.layers_count |> should.equal(10)
  eval.components_count |> should.equal(6)
  eval.processes_count |> should.equal(10)
  eval.zero_muda_enforced |> should.be_true()
  eval.storage_interlock_enforced |> should.be_true()
}

pub fn math_gates_in_triad_evaluation_test() {
  let eval = evaluate_fractal_triad_matrix()
  { eval.shannon_entropy >=. 2.5 } |> should.be_true()
  { eval.ccm_ratio >=. 0.90 } |> should.be_true()
  { eval.divergence_ratio <=. 0.10 } |> should.be_true()
  { eval.itqs_score >=. 0.85 } |> should.be_true()
}

pub fn latency_bounds_strictly_enforced_test() {
  let nodes = generate_canonical_tensor_nodes()
  let all_latency_bounded = list.all(nodes, fn(n) { n.latency_bound_ms <= 100 })
  all_latency_bounded |> should.be_true()

  // Critical interlock paths must be <= 10ms
  let l0_nodes = list.filter(nodes, fn(n) { n.layer_code == "L0" })
  let l0_fast = list.all(l0_nodes, fn(n) { n.latency_bound_ms <= 10 })
  l0_fast |> should.be_true()
}

pub fn telemetry_topics_non_empty_test() {
  let nodes = generate_canonical_tensor_nodes()
  let all_telemetry_valid =
    list.all(nodes, fn(n) {
      string.length(n.telemetry_topic) > 0
      && {
        string.starts_with(n.telemetry_topic, "indrajaal/")
        || string.starts_with(n.telemetry_topic, "c3i/")
      }
    })
  all_telemetry_valid |> should.be_true()
}

pub fn formal_invariants_specified_test() {
  let nodes = generate_canonical_tensor_nodes()
  let all_invariants_specified =
    list.all(nodes, fn(n) { string.length(n.formal_invariant) > 5 })
  all_invariants_specified |> should.be_true()
}

pub fn json_serialization_valid_and_comprehensive_test() {
  let json_str = encode_triad_matrix_json()
  string.contains(json_str, "\"status\":\"ok\"") |> should.be_true()
  string.contains(json_str, "\"contract\":\"SC-FRACTAL-TRIAD-001\"")
  |> should.be_true()
  string.contains(json_str, "\"all_nodes_verified\":true") |> should.be_true()
  string.contains(json_str, "\"layers_count\":10") |> should.be_true()
  string.contains(json_str, "L0_Constitutional") |> should.be_true()
  string.contains(json_str, "L9_Biosemiotic_TransKnowledge") |> should.be_true()
  string.contains(json_str, "nas-1.tail55d152.ts.net:4100") |> should.be_true()
}

pub fn claude_verification_receipt_ratified_test() {
  let cert = verify_with_claude()
  cert.verdict |> should.equal("RATIFIED")
  cert.checkpoints_passed |> should.equal(18)
  cert.checkpoints_total |> should.equal(18)
  cert.gaps_identified |> should.equal(0)
  cert.gaps_closed |> should.equal(4)
  cert.federated_tools_count |> should.equal(93)
  cert.events_mapped_count |> should.equal(32)
  cert.lean4_theorems_verified |> should.equal(10)
}

pub fn claude_verification_json_valid_test() {
  let json_str = encode_claude_verification_json()
  string.contains(json_str, "\"status\":\"ok\"") |> should.be_true()
  string.contains(json_str, "\"verdict\":\"RATIFIED\"") |> should.be_true()
  string.contains(json_str, "\"checkpoints_passed\":18") |> should.be_true()
  string.contains(json_str, "\"federated_tools_count\":93") |> should.be_true()
  string.contains(json_str, "GAP-01-BRIDGE") |> should.be_true()
  string.contains(json_str, "GAP-02-METRICS") |> should.be_true()
  string.contains(json_str, "GAP-03-FORMAL") |> should.be_true()
  string.contains(json_str, "GAP-04-REST") |> should.be_true()
}

