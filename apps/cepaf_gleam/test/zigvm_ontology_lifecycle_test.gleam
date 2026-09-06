// ==============================================================================
// Unified Operational System (UOS) - ZigVM Ontology Lifecycle Test Suite
//
// Verifies all 6 stages of the ZigVM lifecycle, denotational intent gatekeeper,
// TCM conservation, Lyapunov SRE stability, and hardware storage interlock.
// ==============================================================================

import cepaf_gleam/lifecycle/zigvm_ontology_lifecycle.{
  DenotationalIntent, IntentAdmitted, IntentDenied, SreHealthVector,
  Stage1Ontology, Stage2Design, Stage3Code, Stage4Verification, Stage5Sre,
  Stage6KnowledgeManagement, encode_lifecycle_report_json,
  evaluate_denotational_intent, evaluate_full_lifecycle, stage_to_string,
  verify_sre_health_vector,
}
import gleam/string

pub fn lifecycle_stages_enum_test() {
  let assert True =
    stage_to_string(Stage1Ontology) == "Stage 1: Ontology & Semantics"
  let assert True =
    stage_to_string(Stage2Design) == "Stage 2: Mathematical Design & Atlas"
  let assert True =
    stage_to_string(Stage3Code) == "Stage 3: BEAM Code & FPP Transmutation"
  let assert True =
    stage_to_string(Stage4Verification) == "Stage 4: Verification & Oracles"
  let assert True =
    stage_to_string(Stage5Sre) == "Stage 5: SRE & Cybernetic Resilience"
  let assert True =
    stage_to_string(Stage6KnowledgeManagement)
    == "Stage 6: Knowledge Management & ZK-KM"
}

pub fn denotational_intent_hardware_interlock_test() {
  // 1. Attempt to mutate locked root OS NVMe serial "25503L801736"
  let denied_intent =
    DenotationalIntent(
      intent_id: "int-001",
      actor: "unvetted-agent",
      action: "format_osd",
      target: "/dev/nvme0n1",
      device_serial: "25503L801736",
      tcm_coordinates: [0, 0, 0, 0],
    )

  case evaluate_denotational_intent(denied_intent) {
    IntentDenied(reason) -> {
      let assert True = string.contains(reason, "25503L801736")
    }
    IntentAdmitted(_) ->
      panic as "Hardware interlock failed to block root OS NVMe!"
  }

  // 2. Allowed intent on normal Ceph disk
  let allowed_intent =
    DenotationalIntent(
      intent_id: "int-002",
      actor: "storage-custodian",
      action: "mount_data_pool",
      target: "/dev/nvme1n1",
      device_serial: "SERIAL-VALID-999",
      tcm_coordinates: [1, -1, 0, 0],
    )

  case evaluate_denotational_intent(allowed_intent) {
    IntentAdmitted(trace_id) -> {
      let assert True = string.contains(trace_id, "int-002")
    }
    IntentDenied(_) -> panic as "Valid intent was unexpectedly denied!"
  }
}

pub fn sre_cybernetic_health_vector_test() {
  let healthy_vec =
    SreHealthVector(
      lyapunov_exponent: -3.75,
      entropy_shannon: 2.68,
      freshness_seconds: 5,
      cpu_budget_ratio: 0.42,
      storage_interlock_safe: True,
    )
  let assert True = verify_sre_health_vector(healthy_vec)

  let unstable_vec =
    SreHealthVector(
      lyapunov_exponent: 1.2,
      // Positive Lyapunov = chaotic/unstable
      entropy_shannon: 2.68,
      freshness_seconds: 5,
      cpu_budget_ratio: 0.42,
      storage_interlock_safe: True,
    )
  let assert False = verify_sre_health_vector(unstable_vec)
}

pub fn full_lifecycle_evaluation_report_test() {
  let report = evaluate_full_lifecycle("uos-canonical-lifecycle-v1")
  let assert True = report.active_stages_count == 6
  let assert True = report.all_stages_ratified == True
  let assert True = report.algebraic_layers == 12
  let assert True = report.test_modalities == 9
  let assert True = report.zero_muda_pure == True
  let assert True = report.root_os_nvme_locked == True

  let json_str = encode_lifecycle_report_json(report)
  let assert True = string.contains(json_str, "uos-canonical-lifecycle-v1")
  let assert True = string.contains(json_str, "zero_muda_pure")
}
