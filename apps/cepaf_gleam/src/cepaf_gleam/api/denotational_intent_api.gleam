//// =============================================================================
//// [C3I-SIL6-INTENT-API] DENOTATIONAL INTENT API & CONSTITUTIONAL GATEKEEPER
//// =============================================================================
//// Exposes typed JSON/REST endpoints for:
//// 1. Submitting and evaluating Declarative Denotational Intents
//// 2. 13D TCM Coordinate Verification & Delta Conservation Check
//// 3. Full System Test Inventory & Efficacy Serialization
//// =============================================================================

import cepaf_gleam/verification/dmc_tcm_algebraic_atlas.{
  type ConstitutionalGateCheck, type IntentSpec, type MasterTestCategory,
  type Tcm13D, all_master_test_categories, check_intent_constitutional_gates,
  compute_master_system_effectiveness, compute_master_system_efficacy,
  evaluate_denotational_intent, total_itemized_tests_count,
}
import gleam/json
import gleam/list

pub fn format_gate_check_json(gate: ConstitutionalGateCheck) -> json.Json {
  json.object([
    #("gate_name", json.string(gate.gate_name)),
    #("passed", json.bool(gate.passed)),
    #("violation_code", json.int(gate.violation_code)),
    #("message", json.string(gate.message)),
  ])
}

pub fn format_tcm_coordinates_json(coords: Tcm13D) -> json.Json {
  json.object([
    #("layer", json.int(coords.layer)),
    #("fractal", json.string(coords.fractal)),
    #("domain", json.string(coords.domain)),
    #("origin", json.string(coords.origin)),
    #("target", json.string(coords.target)),
    #("epoch", json.int(coords.epoch)),
    #("authority", json.string(coords.authority)),
    #("status", json.string(coords.status)),
    #("sha256_digest", json.string(coords.sha256_digest)),
    #("trust_indicator", json.int(coords.trust_indicator)),
    #("drift_ms", json.float(coords.drift_ms)),
    #("entropy_bits", json.float(coords.entropy_bits)),
    #("parity_state", json.string(coords.parity_state)),
  ])
}

pub fn format_test_category_json(cat: MasterTestCategory) -> json.Json {
  json.object([
    #("category_id", json.string(cat.category_id)),
    #("category_name", json.string(cat.category_name)),
    #("suite_count", json.int(cat.suite_count)),
    #("itemized_test_count", json.int(cat.itemized_test_count)),
    #("efficacy_score", json.float(cat.efficacy_score)),
    #("effectiveness_score", json.float(cat.effectiveness_score)),
    #("all_passing", json.bool(cat.all_passing)),
  ])
}

/// Evaluates an intent specification and formats the typed JSON API response
pub fn handle_intent_submission_json(
  intent: IntentSpec,
  coords: Tcm13D,
) -> String {
  let denotation = evaluate_denotational_intent(intent)
  let gates = check_intent_constitutional_gates(intent)

  let status = case denotation.is_authorized {
    True -> "admitted"
    False -> "rejected_fail_closed"
  }

  json.object([
    #("status", json.string(status)),
    #("contract", json.string("DMC-TCM-MANDATE")),
    #("intent_id", json.string(intent.id)),
    #("actor_id", json.string(intent.actor_id)),
    #("action", json.string(intent.action)),
    #("target_resource", json.string(intent.target_resource)),
    #("is_authorized", json.bool(denotation.is_authorized)),
    #(
      "semantic_transformation",
      json.string(denotation.semantic_transformation),
    ),
    #("rejection_reason", json.string(denotation.rejection_reason)),
    #("constitutional_gates", json.array(gates, format_gate_check_json)),
    #("tcm_coordinates", format_tcm_coordinates_json(coords)),
    #("tailscale_fqdn", json.string("http://nas-1.tail55d152.ts.net:4100")),
    #("timestamp_utc", json.string("2026-09-05T20:31:09.000000Z")),
  ])
  |> json.to_string
}

/// Formats the complete master test inventory as typed JSON API response
pub fn handle_test_inventory_json() -> String {
  let categories = all_master_test_categories()
  let total_tests = total_itemized_tests_count()
  let mean_efficacy = compute_master_system_efficacy()
  let mean_effectiveness = compute_master_system_effectiveness()

  json.object([
    #("status", json.string("ok")),
    #("contract", json.string("UOS-CANONICAL-TEST-INVENTORY")),
    #("total_itemized_tests", json.int(total_tests)),
    #("total_categories", json.int(list.length(categories))),
    #("mean_efficacy_score", json.float(mean_efficacy)),
    #("mean_effectiveness_score", json.float(mean_effectiveness)),
    #("categories", json.array(categories, format_test_category_json)),
    #("tailscale_fqdn", json.string("http://nas-1.tail55d152.ts.net:4100")),
    #("timestamp_utc", json.string("2026-09-05T20:31:09.000000Z")),
  ])
  |> json.to_string
}
