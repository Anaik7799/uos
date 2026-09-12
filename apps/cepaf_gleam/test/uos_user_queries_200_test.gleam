//// =============================================================================
//// [UOS-QUERIES-200] Comprehensive 200 User Query Test Cases Across UOS Aspects
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>test/uos_user_queries_200_test</module>
////     <authority>UOS-CANONICAL-AGENT-POLICY</authority>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////     <topology>Executable Verification of 200 Natural Language User Queries</topology>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>
////       SC-USER-QUERIES-001, SC-SYSTEM-ASPECTS-001, SC-AGENT-CAPABILITY-001,
////       SC-DRIVE-SAFETY-001, SC-MUDA-001, SC-CHECKLIST-001
////     </stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================

import cepaf_gleam/harness/cognitive_worker.{
  type CognitiveIntent, CognitiveIntent, evaluate_intent,
}
import envoy
import gleam/string
import gleeunit/should

fn make_test_intent(id: String, text: String) -> CognitiveIntent {
  CognitiveIntent(
    intent_id: id,
    source: "telegram",
    user: "Avi",
    chat_id: "6249174059",
    text: text,
    timestamp_ms: 1_789_184_000_000,
  )
}

// -----------------------------------------------------------------------------
// Query 001: What are the 17 system aspects of UOS?
// -----------------------------------------------------------------------------
pub fn user_query_001_cat01_001_aspects_overview_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-001", "What are the 17 system aspects of UOS?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("17 System Aspects") |> should.be_true
  decision.reply_markdown |> string.contains("A01") |> should.be_true
  decision.reply_markdown |> string.contains("A17") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 002: Tell me about aspect A01
// -----------------------------------------------------------------------------
pub fn user_query_002_cat01_002_aspect_a01_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-002", "Tell me about aspect A01")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A01") |> should.be_true
  decision.reply_markdown |> string.contains("Substrate & Hardware Safety Enclave") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 003: What is aspect A02 in UOS?
// -----------------------------------------------------------------------------
pub fn user_query_003_cat01_003_aspect_a02_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-003", "What is aspect A02 in UOS?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A02") |> should.be_true
  decision.reply_markdown |> string.contains("Version Control Discipline") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 004: Can you explain aspect A03?
// -----------------------------------------------------------------------------
pub fn user_query_004_cat01_004_aspect_a03_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-004", "Can you explain aspect A03?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A03") |> should.be_true
  decision.reply_markdown |> string.contains("Zero-Muda Purity") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 005: How does aspect A04 define supervision?
// -----------------------------------------------------------------------------
pub fn user_query_005_cat01_005_aspect_a04_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-005", "How does aspect A04 define supervision?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A04") |> should.be_true
  decision.reply_markdown |> string.contains("Supervision & Actor Hierarchy") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 006: Details on aspect A05 deterministic engine
// -----------------------------------------------------------------------------
pub fn user_query_006_cat01_006_aspect_a05_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-006", "Details on aspect A05 deterministic engine")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A05") |> should.be_true
  decision.reply_markdown |> string.contains("Deterministic Runtime Engine") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 007: What is aspect A06 for formal verification?
// -----------------------------------------------------------------------------
pub fn user_query_007_cat01_007_aspect_a06_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-007", "What is aspect A06 for formal verification?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A06") |> should.be_true
  decision.reply_markdown |> string.contains("Formal Evidence") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 008: Tell me about aspect A07 mathematical authority
// -----------------------------------------------------------------------------
pub fn user_query_008_cat01_008_aspect_a07_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-008", "Tell me about aspect A07 mathematical authority")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A07") |> should.be_true
  decision.reply_markdown |> string.contains("Mathematical Authority") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 009: Explain aspect A08 homeostasis
// -----------------------------------------------------------------------------
pub fn user_query_009_cat01_009_aspect_a08_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-009", "Explain aspect A08 homeostasis")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A08") |> should.be_true
  decision.reply_markdown |> string.contains("Feedback Semiotics") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 010: What is aspect A09 quarantined AI inference?
// -----------------------------------------------------------------------------
pub fn user_query_010_cat01_010_aspect_a09_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-010", "What is aspect A09 quarantined AI inference?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A09") |> should.be_true
  decision.reply_markdown |> string.contains("Quarantined AI Inference") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 011: Details on aspect A10 mesh telemetry
// -----------------------------------------------------------------------------
pub fn user_query_011_cat01_011_aspect_a10_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-011", "Details on aspect A10 mesh telemetry")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A10") |> should.be_true
  decision.reply_markdown |> string.contains("Mesh Telemetry") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 012: What is aspect A11 AG-UI protocol?
// -----------------------------------------------------------------------------
pub fn user_query_012_cat01_012_aspect_a11_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-012", "What is aspect A11 AG-UI protocol?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A11") |> should.be_true
  decision.reply_markdown |> string.contains("Agent Event Bus Protocol") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 013: Explain aspect A12 A2UI catalog
// -----------------------------------------------------------------------------
pub fn user_query_013_cat01_013_aspect_a12_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-013", "Explain aspect A12 A2UI catalog")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A12") |> should.be_true
  decision.reply_markdown |> string.contains("Declarative UI Component Catalog") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 014: What does aspect A13 say about triple interfaces?
// -----------------------------------------------------------------------------
pub fn user_query_014_cat01_014_aspect_a13_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-014", "What does aspect A13 say about triple interfaces?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A13") |> should.be_true
  decision.reply_markdown |> string.contains("Multi-Interface Accessibility") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 015: Tell me about aspect A14 Tailscale navigation
// -----------------------------------------------------------------------------
pub fn user_query_015_cat01_015_aspect_a14_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-015", "Tell me about aspect A14 Tailscale navigation")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A14") |> should.be_true
  decision.reply_markdown |> string.contains("Universal Tailscale Web Navigation") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 016: What is aspect A15 verification checklist?
// -----------------------------------------------------------------------------
pub fn user_query_016_cat01_016_aspect_a15_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-016", "What is aspect A15 verification checklist?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A15") |> should.be_true
  decision.reply_markdown |> string.contains("Comprehensive Verification Checklist") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 017: Explain aspect A16 KM triad
// -----------------------------------------------------------------------------
pub fn user_query_017_cat01_017_aspect_a16_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-017", "Explain aspect A16 KM triad")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A16") |> should.be_true
  decision.reply_markdown |> string.contains("Knowledge Management Triad") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 018: What is aspect A17 durable workflow?
// -----------------------------------------------------------------------------
pub fn user_query_018_cat01_018_aspect_a17_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-018", "What is aspect A17 durable workflow?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A17") |> should.be_true
  decision.reply_markdown |> string.contains("Durable Execution & Workflow") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 019: Explain aspect 7
// -----------------------------------------------------------------------------
pub fn user_query_019_cat01_019_aspect_numeric_7_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-019", "Explain aspect 7")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A07") |> should.be_true
  decision.reply_markdown |> string.contains("Mathematical Authority") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 020: Tell me about aspect A99
// -----------------------------------------------------------------------------
pub fn user_query_020_cat01_020_aspect_unknown_a99_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-020", "Tell me about aspect A99")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Unknown System Aspect code") |> should.be_true
  decision.reply_markdown |> string.contains("A99") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 021: What is the hardware storage safety enclave?
// -----------------------------------------------------------------------------
pub fn user_query_021_cat02_021_storage_safety_enclave_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-021", "What is the hardware storage safety enclave?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Ceph Storage") |> should.be_true
  decision.reply_markdown |> string.contains("[REDACTED_SYSTEM_OS_SERIAL]") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 022: Why is NVMe Bay 0 locked?
// -----------------------------------------------------------------------------
pub fn user_query_022_cat02_022_nvme_bay0_locked_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-022", "Why is NVMe Bay 0 locked?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Bay 0") |> should.be_true
  decision.reply_markdown |> string.contains("[REDACTED_SYSTEM_OS_SERIAL]") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 023: What is the hard denied system OS serial?
// -----------------------------------------------------------------------------
pub fn user_query_023_cat02_023_hard_denied_serial_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-023", "What is the hard denied system OS serial?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("[REDACTED_SYSTEM_OS_SERIAL]") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 024: Can Ceph OSDs use the host boot drive?
// -----------------------------------------------------------------------------
pub fn user_query_024_cat02_024_ceph_osd_boot_drive_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-024", "Can Ceph OSDs use the host boot drive?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Bay 0") |> should.be_true
  decision.reply_markdown |> string.contains("HARD-LOCKED") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 025: How does the storage interlock work in Rust?
// -----------------------------------------------------------------------------
pub fn user_query_025_cat02_025_storage_interlock_rust_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-025", "How does the storage interlock work in Rust?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Storage Interlock") |> should.be_true
  decision.reply_markdown |> string.contains("HARD_DENIED_SYSTEM_OS_SERIAL") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 026: Show storage status and disk allocations
// -----------------------------------------------------------------------------
pub fn user_query_026_cat02_026_storage_status_allocation_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-026", "Show storage status and disk allocations")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Ceph Storage") |> should.be_true
  decision.reply_markdown |> string.contains("Target Drives") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 027: How many drive safety checks must pass?
// -----------------------------------------------------------------------------
pub fn user_query_027_cat02_027_drive_safety_gate_count_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-027", "How many drive safety checks must pass?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Drive Safety Gate") |> should.be_true
  decision.reply_markdown |> string.contains("7/7 checks passed") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 028: What happens if an OSD tries to wipe Bay 0?
// -----------------------------------------------------------------------------
pub fn user_query_028_cat02_028_osd_wipe_bay0_prevention_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-028", "What happens if an OSD tries to wipe Bay 0?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("HARD-LOCKED") |> should.be_true
  decision.reply_markdown |> string.contains("Interlock") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 029: What NVMe drives are permitted for Ceph?
// -----------------------------------------------------------------------------
pub fn user_query_029_cat02_029_nvme_drives_permitted_ceph_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-029", "What NVMe drives are permitted for Ceph?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Ceph OSD Target Drives") |> should.be_true
  decision.reply_markdown |> string.contains("OK") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 030: How does UOS prevent data loss on the root volume?
// -----------------------------------------------------------------------------
pub fn user_query_030_cat02_030_root_volume_protection_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-030", "How does UOS prevent data loss on the root volume?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("HARD-LOCKED") |> should.be_true
  decision.reply_markdown |> string.contains("Bay 0") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 031: Is root NVMe serial redacted in logs?
// -----------------------------------------------------------------------------
pub fn user_query_031_cat02_031_nvme_serial_redaction_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-031", "Is root NVMe serial redacted in logs?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("[REDACTED_SYSTEM_OS_SERIAL]") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 032: Where is the storage controller source code located?
// -----------------------------------------------------------------------------
pub fn user_query_032_cat02_032_storage_controller_source_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-032", "Where is the storage controller source code located?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Storage") |> should.be_true
  decision.reply_markdown |> string.contains("Interlock") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 033: What fractal layer governs hardware safety?
// -----------------------------------------------------------------------------
pub fn user_query_033_cat02_033_fractal_layer_hardware_safety_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-033", "What fractal layer governs hardware safety?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Hardware") |> should.be_true
  decision.reply_markdown |> string.contains("Safety") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 034: What STAMP control enforces storage safety?
// -----------------------------------------------------------------------------
pub fn user_query_034_cat02_034_stamp_control_storage_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-034", "What STAMP control enforces storage safety?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Storage Interlock") |> should.be_true
  decision.reply_markdown |> string.contains("Drive Safety") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 035: Show drive health and SMART telemetry
// -----------------------------------------------------------------------------
pub fn user_query_035_cat02_035_drive_health_smart_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-035", "Show drive health and SMART telemetry")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Drive Safety Gate") |> should.be_true
  decision.reply_markdown |> string.contains("7/7 checks passed") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 036: Can an operator force-override Bay 0 lockout?
// -----------------------------------------------------------------------------
pub fn user_query_036_cat02_036_operator_override_lockout_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-036", "Can an operator force-override Bay 0 lockout?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("HARD-LOCKED") |> should.be_true
  decision.reply_markdown |> string.contains("Bay 0") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 037: What is the Ceph cluster layout on nas-1?
// -----------------------------------------------------------------------------
pub fn user_query_037_cat02_037_ceph_cluster_layout_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-037", "What is the Ceph cluster layout on nas-1?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Ceph Storage") |> should.be_true
  decision.reply_markdown |> string.contains("Target Drives") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 038: How are storage changes verified?
// -----------------------------------------------------------------------------
pub fn user_query_038_cat02_038_storage_changes_verified_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-038", "How are storage changes verified?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Drive Safety Gate") |> should.be_true
  decision.reply_markdown |> string.contains("CHK-07-DRIVE") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 039: What happens during storage controller preflight?
// -----------------------------------------------------------------------------
pub fn user_query_039_cat02_039_controller_preflight_steps_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-039", "What happens during storage controller preflight?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Storage Interlock") |> should.be_true
  decision.reply_markdown |> string.contains("ACTIVE") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 040: Is the storage configuration in git or jujutsu?
// -----------------------------------------------------------------------------
pub fn user_query_040_cat02_040_storage_vcs_storage_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-040", "Is the storage configuration in git or jujutsu?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Storage") |> should.be_true
  decision.reply_markdown |> string.contains("Interlock") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 041: How does the standalone Jujutsu monorepo work?
// -----------------------------------------------------------------------------
pub fn user_query_041_cat03_041_jj_monorepo_operation_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-041", "How does the standalone Jujutsu monorepo work?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A02") |> should.be_true
  decision.reply_markdown |> string.contains("Jujutsu Standalone") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 042: Why are native git mutations prohibited?
// -----------------------------------------------------------------------------
pub fn user_query_042_cat03_042_git_mutations_prohibited_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-042", "Why are native git mutations prohibited?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("0 native Git mutation commands") |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A02") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 043: What happens if I run git commit in UOS?
// -----------------------------------------------------------------------------
pub fn user_query_043_cat03_043_git_commit_violation_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-043", "What happens if I run git commit in UOS?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("0 native Git mutation commands") |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A02") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 044: How do sibling workspaces work in Jujutsu?
// -----------------------------------------------------------------------------
pub fn user_query_044_cat03_044_sibling_workspaces_usage_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-044", "How do sibling workspaces work in Jujutsu?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("sibling workspaces") |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A02") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 045: What is the main bookmark policy?
// -----------------------------------------------------------------------------
pub fn user_query_045_cat03_045_main_bookmark_policy_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-045", "What is the main bookmark policy?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A02") |> should.be_true
  decision.reply_markdown |> string.contains("Version Control Discipline") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 046: How are active feature branches managed?
// -----------------------------------------------------------------------------
pub fn user_query_046_cat03_046_active_feature_branches_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-046", "How are active feature branches managed?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A02") |> should.be_true
  decision.reply_markdown |> string.contains("Version Control Discipline") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 047: What is the difference between change ID and commit ID?
// -----------------------------------------------------------------------------
pub fn user_query_047_cat03_047_change_id_vs_commit_id_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-047", "What is the difference between change ID and commit ID?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A02") |> should.be_true
  decision.reply_markdown |> string.contains("Jujutsu") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 048: How are merge conflicts resolved in Jujutsu?
// -----------------------------------------------------------------------------
pub fn user_query_048_cat03_048_merge_conflicts_handling_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-048", "How are merge conflicts resolved in Jujutsu?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A02") |> should.be_true
  decision.reply_markdown |> string.contains("Version Control Discipline") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 049: What tool verifies VCS discipline?
// -----------------------------------------------------------------------------
pub fn user_query_049_cat03_049_vcs_discipline_verifier_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-049", "What tool verifies VCS discipline?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("CHK-18-JJ") |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A02") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 050: Are external repositories allowed to mutate UOS?
// -----------------------------------------------------------------------------
pub fn user_query_050_cat03_050_external_repos_read_only_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-050", "Are external repositories allowed to mutate UOS?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A02") |> should.be_true
  decision.reply_markdown |> string.contains("Version Control Discipline") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 051: How is commit provenance enforced?
// -----------------------------------------------------------------------------
pub fn user_query_051_cat03_051_commit_provenance_audit_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-051", "How is commit provenance enforced?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A02") |> should.be_true
  decision.reply_markdown |> string.contains("Version Control Discipline") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 052: Can Jujutsu operations be undone?
// -----------------------------------------------------------------------------
pub fn user_query_052_cat03_052_jujutsu_undo_capabilities_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-052", "Can Jujutsu operations be undone?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A02") |> should.be_true
  decision.reply_markdown |> string.contains("Jujutsu Standalone") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 053: What fractal layer governs version control?
// -----------------------------------------------------------------------------
pub fn user_query_053_cat03_053_vcs_fractal_layers_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-053", "What fractal layer governs version control?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A02") |> should.be_true
  decision.reply_markdown |> string.contains("L0 Constitutional") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 054: How does Jujutsu interact with the CI/CD pipeline?
// -----------------------------------------------------------------------------
pub fn user_query_054_cat03_054_jujutsu_cicd_pipeline_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-054", "How does Jujutsu interact with the CI/CD pipeline?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A02") |> should.be_true
  decision.reply_markdown |> string.contains("CHK-18-JJ") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 055: Why is colocated Git not used?
// -----------------------------------------------------------------------------
pub fn user_query_055_cat03_055_colocated_git_elimination_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-055", "Why is colocated Git not used?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A02") |> should.be_true
  decision.reply_markdown |> string.contains("0 native Git mutation commands") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 056: What bookmark is used for daily integration?
// -----------------------------------------------------------------------------
pub fn user_query_056_cat03_056_integration_bookmarks_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-056", "What bookmark is used for daily integration?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A02") |> should.be_true
  decision.reply_markdown |> string.contains("Version Control Discipline") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 057: How do agents claim sibling workspaces?
// -----------------------------------------------------------------------------
pub fn user_query_057_cat03_057_workspace_claims_fencing_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-057", "How do agents claim sibling workspaces?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("sibling workspaces") |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A02") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 058: How does Jujutsu record file snapshots?
// -----------------------------------------------------------------------------
pub fn user_query_058_cat03_058_jujutsu_snapshot_engine_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-058", "How does Jujutsu record file snapshots?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A02") |> should.be_true
  decision.reply_markdown |> string.contains("Jujutsu Standalone") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 059: What is the Jujutsu status command in UOS?
// -----------------------------------------------------------------------------
pub fn user_query_059_cat03_059_jujutsu_status_command_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-059", "What is the Jujutsu status command in UOS?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A02") |> should.be_true
  decision.reply_markdown |> string.contains("Version Control Discipline") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 060: What happens if git files appear in UOS?
// -----------------------------------------------------------------------------
pub fn user_query_060_cat03_060_git_files_fail_closed_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-060", "What happens if git files appear in UOS?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("0 native Git mutation commands") |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A02") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 061: What is Zero-Muda purity in UOS?
// -----------------------------------------------------------------------------
pub fn user_query_061_cat04_061_zero_muda_definition_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-061", "What is Zero-Muda purity in UOS?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A03") |> should.be_true
  decision.reply_markdown |> string.contains("Zero-Muda Purity") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 062: Why are Bevy and Graphite permanently barred?
// -----------------------------------------------------------------------------
pub fn user_query_062_cat04_062_bevy_graphite_barred_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-062", "Why are Bevy and Graphite permanently barred?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("0 Bevy, 0 Graphite") |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A03") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 063: How is 2D vector math implemented without foreign NIFs?
// -----------------------------------------------------------------------------
pub fn user_query_063_cat04_063_vector_math_pure_erlang_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-063", "How is 2D vector math implemented without foreign NIFs?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Pure Erlang 2D vector math") |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A03") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 064: Where is Python permitted to run in UOS?
// -----------------------------------------------------------------------------
pub fn user_query_064_cat04_064_python_quarantine_max_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-064", "Where is Python permitted to run in UOS?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Python quarantined to MAX") |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A03") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 065: What are the 7 wastes of software engineering in TPS?
// -----------------------------------------------------------------------------
pub fn user_query_065_cat04_065_seven_wastes_of_tps_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-065", "What are the 7 wastes of software engineering in TPS?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A03") |> should.be_true
  decision.reply_markdown |> string.contains("Zero-Muda Purity") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 066: What is the compiler warning policy in UOS?
// -----------------------------------------------------------------------------
pub fn user_query_066_cat04_066_compiler_warning_policy_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-066", "What is the compiler warning policy in UOS?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A03") |> should.be_true
  decision.reply_markdown |> string.contains("Zero-Muda Purity") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 067: What languages are admitted into the UOS core?
// -----------------------------------------------------------------------------
pub fn user_query_067_cat04_067_admitted_languages_core_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-067", "What languages are admitted into the UOS core?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("BEAM OTP 29 & Hermes OCaml") |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A03") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 068: Why are shell scripts barred from core execution?
// -----------------------------------------------------------------------------
pub fn user_query_068_cat04_068_shell_scripts_prohibition_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-068", "Why are shell scripts barred from core execution?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A03") |> should.be_true
  decision.reply_markdown |> string.contains("Zero-Muda Purity") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 069: How is memory waste eliminated in ZigVM?
// -----------------------------------------------------------------------------
pub fn user_query_069_cat04_069_memory_arenas_zero_waste_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-069", "How is memory waste eliminated in ZigVM?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A03") |> should.be_true
  decision.reply_markdown |> string.contains("Zero-Muda Purity") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 070: What verification check enforces Zero-Muda?
// -----------------------------------------------------------------------------
pub fn user_query_070_cat04_070_verification_zero_muda_checks_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-070", "What verification check enforces Zero-Muda?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("CHK-05-MUDA") |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A03") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 071: Is Graphene NIF a real shared library or a facade?
// -----------------------------------------------------------------------------
pub fn user_query_071_cat04_071_graphene_facade_clarification_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-071", "Is Graphene NIF a real shared library or a facade?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Pure Erlang 2D vector math") |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A03") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 072: How does Modular MAX isolate Python runtime?
// -----------------------------------------------------------------------------
pub fn user_query_072_cat04_072_modular_max_isolation_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-072", "How does Modular MAX isolate Python runtime?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Python quarantined to MAX") |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A03") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 073: What happens if a Bevy dependency is added to Cargo.toml?
// -----------------------------------------------------------------------------
pub fn user_query_073_cat04_073_bevy_dependency_gate_failure_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-073", "What happens if a Bevy dependency is added to Cargo.toml?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("0 Bevy, 0 Graphite") |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A03") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 074: Why is dead code considered Muda?
// -----------------------------------------------------------------------------
pub fn user_query_074_cat04_074_dead_code_muda_reduction_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-074", "Why is dead code considered Muda?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A03") |> should.be_true
  decision.reply_markdown |> string.contains("Zero-Muda Purity") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 075: What tool scans for Zero-Muda compliance?
// -----------------------------------------------------------------------------
pub fn user_query_075_cat04_075_zero_muda_scanning_tool_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-075", "What tool scans for Zero-Muda compliance?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("CHK-05-MUDA") |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A03") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 076: How does Gleam contribute to Zero-Muda?
// -----------------------------------------------------------------------------
pub fn user_query_076_cat04_076_gleam_type_safety_role_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-076", "How does Gleam contribute to Zero-Muda?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("BEAM OTP 29") |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A03") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 077: How is test suite execution kept Muda-free?
// -----------------------------------------------------------------------------
pub fn user_query_077_cat04_077_test_execution_efficiency_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-077", "How is test suite execution kept Muda-free?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A03") |> should.be_true
  decision.reply_markdown |> string.contains("Zero-Muda Purity") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 078: What is the boundary between Rust NIFs and BEAM?
// -----------------------------------------------------------------------------
pub fn user_query_078_cat04_078_rust_nif_beam_boundary_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-078", "What is the boundary between Rust NIFs and BEAM?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("0 foreign NIF shared libraries") |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A03") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 079: How are external dependencies audited?
// -----------------------------------------------------------------------------
pub fn user_query_079_cat04_079_external_dependencies_audit_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-079", "How are external dependencies audited?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A03") |> should.be_true
  decision.reply_markdown |> string.contains("Zero-Muda Purity") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 080: What is the Zero-Muda status in the system line?
// -----------------------------------------------------------------------------
pub fn user_query_080_cat04_080_zero_muda_status_line_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-080", "What is the Zero-Muda status in the system line?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("0 Bevy, 0 Graphite") |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A03") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 081: How does the Gleam OTP supervision tree work?
// -----------------------------------------------------------------------------
pub fn user_query_081_cat05_081_gleam_otp_supervision_tree_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-081", "How does the Gleam OTP supervision tree work?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A04") |> should.be_true
  decision.reply_markdown |> string.contains("uos_sup.gleam") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 082: What are the 4 supervisory domains in uos_sup?
// -----------------------------------------------------------------------------
pub fn user_query_082_cat05_082_four_supervisory_domains_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-082", "What are the 4 supervisory domains in uos_sup?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Root 4-domain supervisor") |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A04") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 083: How do Prajna circuit breakers operate?
// -----------------------------------------------------------------------------
pub fn user_query_083_cat05_083_prajna_circuit_breakers_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-083", "How do Prajna circuit breakers operate?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A04") |> should.be_true
  decision.reply_markdown |> string.contains("Supervision") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 084: What is a Lyapunov stability proof in UOS?
// -----------------------------------------------------------------------------
pub fn user_query_084_cat05_084_lyapunov_stability_proofs_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-084", "What is a Lyapunov stability proof in UOS?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A04") |> should.be_true
  decision.reply_markdown |> string.contains("Lyapunov") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 085: How does dead-man's-switch freshness monitoring work?
// -----------------------------------------------------------------------------
pub fn user_query_085_cat05_085_freshness_monitoring_deadman_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-085", "How does dead-man's-switch freshness monitoring work?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A04") |> should.be_true
  decision.reply_markdown |> string.contains("Supervision") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 086: What is 2oo3 constitutional consensus?
// -----------------------------------------------------------------------------
pub fn user_query_086_cat05_086_two_out_of_three_consensus_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-086", "What is 2oo3 constitutional consensus?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A04") |> should.be_true
  decision.reply_markdown |> string.contains("Supervision") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 087: What happens when a child worker crashes?
// -----------------------------------------------------------------------------
pub fn user_query_087_cat05_087_child_worker_isolation_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-087", "What happens when a child worker crashes?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("isolated restart budgets") |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A04") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 088: What is the restart intensity limit in uos_sup?
// -----------------------------------------------------------------------------
pub fn user_query_088_cat05_088_restart_intensity_limits_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-088", "What is the restart intensity limit in uos_sup?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A04") |> should.be_true
  decision.reply_markdown |> string.contains("uos_sup.gleam") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 089: How does C3I maintain homeostasis during load spikes?
// -----------------------------------------------------------------------------
pub fn user_query_089_cat05_089_homeostasis_under_spikes_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-089", "How does C3I maintain homeostasis during load spikes?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A04") |> should.be_true
  decision.reply_markdown |> string.contains("Supervision") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 090: What directive shows system health and supervision?
// -----------------------------------------------------------------------------
pub fn user_query_090_cat05_090_health_supervision_directive_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-090", "What directive shows system health and supervision?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A04") |> should.be_true
  decision.reply_markdown |> string.contains("Supervision") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 091: What fractal layer governs SRE homeostasis?
// -----------------------------------------------------------------------------
pub fn user_query_091_cat05_091_sre_homeostasis_fractal_layer_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-091", "What fractal layer governs SRE homeostasis?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("L4 System / L9 SRE Homeostasis") |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A04") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 092: Where is the Lyapunov proof module implemented?
// -----------------------------------------------------------------------------
pub fn user_query_092_cat05_092_lyapunov_proof_source_location_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-092", "Where is the Lyapunov proof module implemented?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A04") |> should.be_true
  decision.reply_markdown |> string.contains("Lyapunov") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 093: How does the Prajna breaker prevent cascading failure?
// -----------------------------------------------------------------------------
pub fn user_query_093_cat05_093_cascading_failure_prevention_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-093", "How does the Prajna breaker prevent cascading failure?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A04") |> should.be_true
  decision.reply_markdown |> string.contains("Prajna circuit breakers") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 094: What STAMP control governs supervision?
// -----------------------------------------------------------------------------
pub fn user_query_094_cat05_094_stamp_supervision_control_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-094", "What STAMP control governs supervision?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A04") |> should.be_true
  decision.reply_markdown |> string.contains("Supervision") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 095: How does OTP 29 improve actor performance?
// -----------------------------------------------------------------------------
pub fn user_query_095_cat05_095_otp29_actor_performance_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-095", "How does OTP 29 improve actor performance?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Pure Gleam / OTP 29") |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A04") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 096: How are dead-man's switches tested in UOS?
// -----------------------------------------------------------------------------
pub fn user_query_096_cat05_096_freshness_switches_testing_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-096", "How are dead-man's switches tested in UOS?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A04") |> should.be_true
  decision.reply_markdown |> string.contains("Supervision") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 097: What is dark cockpit mode in C3I?
// -----------------------------------------------------------------------------
pub fn user_query_097_cat05_097_dark_cockpit_philosophy_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-097", "What is dark cockpit mode in C3I?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A04") |> should.be_true
  decision.reply_markdown |> string.contains("Supervision") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 098: How does the SRE Homeostasis Overseer agent behave?
// -----------------------------------------------------------------------------
pub fn user_query_098_cat05_098_sre_homeostasis_agent_role_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-098", "How does the SRE Homeostasis Overseer agent behave?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A04") |> should.be_true
  decision.reply_markdown |> string.contains("Supervision") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 099: What metric indicates Lyapunov divergence?
// -----------------------------------------------------------------------------
pub fn user_query_099_cat05_099_lyapunov_divergence_metrics_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-099", "What metric indicates Lyapunov divergence?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A04") |> should.be_true
  decision.reply_markdown |> string.contains("Lyapunov") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 100: What happens during an Andon halt?
// -----------------------------------------------------------------------------
pub fn user_query_100_cat05_100_andon_halt_behavior_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-100", "What happens during an Andon halt?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A04") |> should.be_true
  decision.reply_markdown |> string.contains("Supervision") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 101: What is the ZigVM deterministic runtime engine?
// -----------------------------------------------------------------------------
pub fn user_query_101_cat06_101_zigvm_runtime_engine_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-101", "What is the ZigVM deterministic runtime engine?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A05") |> should.be_true
  decision.reply_markdown |> string.contains("Deterministic Runtime Engine") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 102: How does ZigVM achieve 19.85 million ops per second?
// -----------------------------------------------------------------------------
pub fn user_query_102_cat06_102_zigvm_throughput_metrics_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-102", "How does ZigVM achieve 19.85 million ops per second?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("19.85M") |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A05") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 103: What is the descriptor-relative VFS in ZigVM?
// -----------------------------------------------------------------------------
pub fn user_query_103_cat06_103_descriptor_relative_vfs_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-103", "What is the descriptor-relative VFS in ZigVM?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Descriptor-relative") |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A05") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 104: What is the role of Hermes OCaml engine?
// -----------------------------------------------------------------------------
pub fn user_query_104_cat06_104_hermes_ocaml_role_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-104", "What is the role of Hermes OCaml engine?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A06") |> should.be_true
  decision.reply_markdown |> string.contains("Formal Evidence") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 105: How does Hermes store authoritative evidence ledgers?
// -----------------------------------------------------------------------------
pub fn user_query_105_cat06_105_hermes_sqlite_ledgers_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-105", "How does Hermes store authoritative evidence ledgers?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A06") |> should.be_true
  decision.reply_markdown |> string.contains("SQLite WAL") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 106: What is the zero-trust interceptor in Hermes?
// -----------------------------------------------------------------------------
pub fn user_query_106_cat06_106_zero_trust_interceptor_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-106", "What is the zero-trust interceptor in Hermes?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A06") |> should.be_true
  decision.reply_markdown |> string.contains("Cryptokit SHA-256") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 107: How does Hermes trap embedded NUL bytes and SQL injection?
// -----------------------------------------------------------------------------
pub fn user_query_107_cat06_107_null_bytes_sql_injection_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-107", "How does Hermes trap embedded NUL bytes and SQL injection?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A06") |> should.be_true
  decision.reply_markdown |> string.contains("Embedded NUL byte trap") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 108: What are Gospel specifications in Hermes?
// -----------------------------------------------------------------------------
pub fn user_query_108_cat06_108_gospel_specifications_role_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-108", "What are Gospel specifications in Hermes?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Gospel") |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A06") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 109: How does Hermes run bounded Z3 solver queries?
// -----------------------------------------------------------------------------
pub fn user_query_109_cat06_109_bounded_z3_solver_queries_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-109", "How does Hermes run bounded Z3 solver queries?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Z3") |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A06") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 110: What is differential parity comparison in Hermes?
// -----------------------------------------------------------------------------
pub fn user_query_110_cat06_110_differential_parity_comparison_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-110", "What is differential parity comparison in Hermes?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Formal Evidence") |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A06") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 111: What directive tests ZigVM execution?
// -----------------------------------------------------------------------------
pub fn user_query_111_cat06_111_zigvm_execution_directive_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-111", "What directive tests ZigVM execution?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A05") |> should.be_true
  decision.reply_markdown |> string.contains("Deterministic Runtime Engine") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 112: What fractal layer governs deterministic runtime?
// -----------------------------------------------------------------------------
pub fn user_query_112_cat06_112_deterministic_fractal_layer_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-112", "What fractal layer governs deterministic runtime?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("L1 Atomic") |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A05") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 113: Why are unbounded solver queries barred from NIFs?
// -----------------------------------------------------------------------------
pub fn user_query_113_cat06_113_unbounded_solvers_barred_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-113", "Why are unbounded solver queries barred from NIFs?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A06") |> should.be_true
  decision.reply_markdown |> string.contains("bounded Z3 solver workers") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 114: How does ZigVM guarantee reproducible bytecode execution?
// -----------------------------------------------------------------------------
pub fn user_query_114_cat06_114_reproducible_bytecode_execution_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-114", "How does ZigVM guarantee reproducible bytecode execution?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A05") |> should.be_true
  decision.reply_markdown |> string.contains("Deterministic Runtime Engine") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 115: Where is the ZigVM kernel source code located?
// -----------------------------------------------------------------------------
pub fn user_query_115_cat06_115_zigvm_kernel_source_location_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-115", "Where is the ZigVM kernel source code located?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("engines/zigvm") |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A05") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 116: Where is the Hermes engine source code located?
// -----------------------------------------------------------------------------
pub fn user_query_116_cat06_116_hermes_source_location_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-116", "Where is the Hermes engine source code located?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("engines/hermes") |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A06") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 117: What happens if a Z3 solver query times out?
// -----------------------------------------------------------------------------
pub fn user_query_117_cat06_117_z3_solver_timeout_enforcement_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-117", "What happens if a Z3 solver query times out?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A06") |> should.be_true
  decision.reply_markdown |> string.contains("bounded Z3 solver workers") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 118: What STAMP control governs formal evidence?
// -----------------------------------------------------------------------------
pub fn user_query_118_cat06_118_stamp_formal_evidence_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-118", "What STAMP control governs formal evidence?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A06") |> should.be_true
  decision.reply_markdown |> string.contains("Formal Evidence") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 119: How does ZigVM communicate with BEAM?
// -----------------------------------------------------------------------------
pub fn user_query_119_cat06_119_zigvm_beam_interop_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-119", "How does ZigVM communicate with BEAM?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A05") |> should.be_true
  decision.reply_markdown |> string.contains("Deterministic Runtime Engine") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 120: How are Gospel contracts verified during build?
// -----------------------------------------------------------------------------
pub fn user_query_120_cat06_120_gospel_contracts_verification_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-120", "How are Gospel contracts verified during build?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Gospel") |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A06") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 121: What mathematical proofs exist in Lean 4 for UOS?
// -----------------------------------------------------------------------------
pub fn user_query_121_cat07_121_lean4_verified_theorems_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-121", "What mathematical proofs exist in Lean 4 for UOS?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Formal Verification & Mathematical Gates") |> should.be_true
  decision.reply_markdown |> string.contains("Traceability.lean") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 122: What is 13D coordinate conservation in Traceability.lean?
// -----------------------------------------------------------------------------
pub fn user_query_122_cat07_122_coordinate_conservation_proof_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-122", "What is 13D coordinate conservation in Traceability.lean?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("13D Coordinate Conservation") |> should.be_true
  decision.reply_markdown |> string.contains("Traceability.lean") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 123: What is the Two-Lattice STM proof in Lean 4?
// -----------------------------------------------------------------------------
pub fn user_query_123_cat07_123_two_lattice_stm_proof_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-123", "What is the Two-Lattice STM proof in Lean 4?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Two-Lattice STM") |> should.be_true
  decision.reply_markdown |> string.contains("TwoLattice_STM.lean") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 124: What are the 4 Mathematical Quality Gates in UOS?
// -----------------------------------------------------------------------------
pub fn user_query_124_cat07_124_four_math_gates_overview_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-124", "What are the 4 Mathematical Quality Gates in UOS?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Shannon Entropy Gate") |> should.be_true
  decision.reply_markdown |> string.contains("CCM Gate") |> should.be_true
  decision.reply_markdown |> string.contains("Divergence Gate") |> should.be_true
  decision.reply_markdown |> string.contains("Test Quality Gate") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 125: What is the Shannon Entropy Gate H threshold?
// -----------------------------------------------------------------------------
pub fn user_query_125_cat07_125_shannon_entropy_gate_threshold_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-125", "What is the Shannon Entropy Gate H threshold?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Shannon Entropy Gate") |> should.be_true
  decision.reply_markdown |> string.contains("2.5") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 126: What is the Cyclomatic Complexity Metric (CCM) gate?
// -----------------------------------------------------------------------------
pub fn user_query_126_cat07_126_ccm_branch_coverage_gate_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-126", "What is the Cyclomatic Complexity Metric (CCM) gate?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("CCM Gate") |> should.be_true
  decision.reply_markdown |> string.contains("CCM") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 127: What is the Divergence Gate D_EA threshold?
// -----------------------------------------------------------------------------
pub fn user_query_127_cat07_127_divergence_gate_threshold_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-127", "What is the Divergence Gate D_EA threshold?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Divergence Gate") |> should.be_true
  decision.reply_markdown |> string.contains("D_{EA}") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 128: What is the Integrated Test Quality Score (ITQS) gate?
// -----------------------------------------------------------------------------
pub fn user_query_128_cat07_128_itqs_test_quality_score_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-128", "What is the Integrated Test Quality Score (ITQS) gate?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Test Quality Gate") |> should.be_true
  decision.reply_markdown |> string.contains("0.85") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 129: What is Century_Harmony.lean proving?
// -----------------------------------------------------------------------------
pub fn user_query_129_cat07_129_century_harmony_theorem_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-129", "What is Century_Harmony.lean proving?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Formal Verification & Mathematical Gates") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 130: What does Sheaf_Presheaf.lean prove?
// -----------------------------------------------------------------------------
pub fn user_query_130_cat07_130_sheaf_presheaf_consistency_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-130", "What does Sheaf_Presheaf.lean prove?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Formal Verification & Mathematical Gates") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 131: What does Chaos_Containment.lean prove?
// -----------------------------------------------------------------------------
pub fn user_query_131_cat07_131_chaos_containment_proof_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-131", "What does Chaos_Containment.lean prove?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Formal Verification & Mathematical Gates") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 132: What does Fast_OODA_Convergence.lean prove?
// -----------------------------------------------------------------------------
pub fn user_query_132_cat07_132_fast_ooda_convergence_proof_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-132", "What does Fast_OODA_Convergence.lean prove?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Formal Verification & Mathematical Gates") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 133: What does Constitutional_Invariants.lean prove?
// -----------------------------------------------------------------------------
pub fn user_query_133_cat07_133_constitutional_invariants_proof_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-133", "What does Constitutional_Invariants.lean prove?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Formal Verification & Mathematical Gates") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 134: How does Quint simulate the parity frontier?
// -----------------------------------------------------------------------------
pub fn user_query_134_cat07_134_quint_parity_frontier_checks_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-134", "How does Quint simulate the parity frontier?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Formal Verification & Mathematical Gates") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 135: What happens if a Lean proof contains 'sorry'?
// -----------------------------------------------------------------------------
pub fn user_query_135_cat07_135_lean_sorry_fail_closed_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-135", "What happens if a Lean proof contains 'sorry'?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Formal Verification & Mathematical Gates") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 136: What test modality verifies mathematical gates?
// -----------------------------------------------------------------------------
pub fn user_query_136_cat07_136_test_modality_math_verification_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-136", "What test modality verifies mathematical gates?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("9 Modalities 100% Green") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 137: What is the fail-closed indicator in Traceability.lean?
// -----------------------------------------------------------------------------
pub fn user_query_137_cat07_137_fail_closed_indicator_trust_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-137", "What is the fail-closed indicator in Traceability.lean?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Traceability.lean") |> should.be_true
  decision.reply_markdown |> string.contains("Coordinate Conservation") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 138: Where are the Lean 4 proof source files located?
// -----------------------------------------------------------------------------
pub fn user_query_138_cat07_138_lean4_source_directory_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-138", "Where are the Lean 4 proof source files located?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("formal/lean") |> should.be_true
  decision.reply_markdown |> string.contains("Traceability.lean") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 139: How many total tests are in the 9-modality protocol?
// -----------------------------------------------------------------------------
pub fn user_query_139_cat07_139_nine_modality_test_counts_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-139", "How many total tests are in the 9-modality protocol?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("9 Modalities 100% Green") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 140: What check validates the 4 Math Gates?
// -----------------------------------------------------------------------------
pub fn user_query_140_cat07_140_math_gates_checklist_id_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-140", "What check validates the 4 Math Gates?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Formal Verification & Mathematical Gates") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 141: What is the Tri-Sovereign Governance model in UOS?
// -----------------------------------------------------------------------------
pub fn user_query_141_cat08_141_tri_sovereign_governance_model_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-141", "What is the Tri-Sovereign Governance model in UOS?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Tri-Agent Swarm Message Board") |> should.be_true
  decision.reply_markdown |> string.contains("AGY") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 142: What is the role of AGY Sovereign Coordinator?
// -----------------------------------------------------------------------------
pub fn user_query_142_cat08_142_agy_coordinator_role_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-142", "What is the role of AGY Sovereign Coordinator?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Agent Profile: AGY Sovereign Coordinator") |> should.be_true
  decision.reply_markdown |> string.contains("agy_sovereign_coordinator") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 143: What is the role of Claude in UOS governance?
// -----------------------------------------------------------------------------
pub fn user_query_143_cat08_143_claude_reviewer_role_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-143", "What is the role of Claude in UOS governance?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Tri-Agent") |> should.be_true
  decision.reply_markdown |> string.contains("Claude") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 144: What is the role of Codex in UOS governance?
// -----------------------------------------------------------------------------
pub fn user_query_144_cat08_144_codex_auditor_role_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-144", "What is the role of Codex in UOS governance?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Tri-Agent") |> should.be_true
  decision.reply_markdown |> string.contains("Codex") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 145: What are the 7 canonical Agent Profiles in agent_ecology?
// -----------------------------------------------------------------------------
pub fn user_query_145_cat08_145_seven_canonical_profiles_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-145", "What are the 7 canonical Agent Profiles in agent_ecology?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("UOS Rich Multi-Agent Ecology") |> should.be_true
  decision.reply_markdown |> string.contains("7 Canonical Holon Profiles") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 146: Tell me about the Multimodal Edge Ingestor profile
// -----------------------------------------------------------------------------
pub fn user_query_146_cat08_146_edge_ingestor_profile_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-146", "Tell me about the Multimodal Edge Ingestor profile")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Agent Profile: Multimodal Edge Ingestor") |> should.be_true
  decision.reply_markdown |> string.contains("multimodal_edge_ingestor") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 147: Tell me about the Security Hardware Guardian profile
// -----------------------------------------------------------------------------
pub fn user_query_147_cat08_147_security_guardian_profile_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-147", "Tell me about the Security Hardware Guardian profile")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Security & Hardware Enclave Guardian") |> should.be_true
  decision.reply_markdown |> string.contains("security_hardware_guardian") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 148: Tell me about the Formal Verifier Oracle profile
// -----------------------------------------------------------------------------
pub fn user_query_148_cat08_148_formal_verifier_profile_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-148", "Tell me about the Formal Verifier Oracle profile")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Agent Profile: Formal Verifier Oracle") |> should.be_true
  decision.reply_markdown |> string.contains("formal_verifier_oracle") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 149: Tell me about the Knowledge Sheaf Curator profile
// -----------------------------------------------------------------------------
pub fn user_query_149_cat08_149_knowledge_curator_profile_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-149", "Tell me about the Knowledge Sheaf Curator profile")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Agent Profile: Knowledge Sheaf Curator") |> should.be_true
  decision.reply_markdown |> string.contains("knowledge_sheaf_curator") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 150: Tell me about the Quarantined Inference Worker profile
// -----------------------------------------------------------------------------
pub fn user_query_150_cat08_150_inference_worker_profile_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-150", "Tell me about the Quarantined Inference Worker profile")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Quarantined AI Inference Worker") |> should.be_true
  decision.reply_markdown |> string.contains("quarantined_inference_worker") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 151: What is the Tri-Agent Message Board?
// -----------------------------------------------------------------------------
pub fn user_query_151_cat08_151_tri_agent_message_board_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-151", "What is the Tri-Agent Message Board?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Tri-Agent Swarm Message Board") |> should.be_true
  decision.reply_markdown |> string.contains("Canonical Store") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 152: How do peer agents communicate across nodes?
// -----------------------------------------------------------------------------
pub fn user_query_152_cat08_152_peer_agent_coordination_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-152", "How do peer agents communicate across nodes?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Tri-Agent Swarm Message Board") |> should.be_true
  decision.reply_markdown |> string.contains("events") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 153: What is the token budget for AGY Sovereign Coordinator?
// -----------------------------------------------------------------------------
pub fn user_query_153_cat08_153_agy_token_budget_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-153", "What is the token budget for AGY Sovereign Coordinator?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("8192 tokens") |> should.be_true
  decision.reply_markdown |> string.contains("agy_sovereign_coordinator") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 154: What is the SLA latency for SRE Homeostasis Overseer?
// -----------------------------------------------------------------------------
pub fn user_query_154_cat08_154_sre_overseer_latency_sla_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-154", "What is the SLA latency for SRE Homeostasis Overseer?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("10 ms") |> should.be_true
  decision.reply_markdown |> string.contains("sre_homeostasis_overseer") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 155: How is 2oo3 constitutional consensus enforced between agents?
// -----------------------------------------------------------------------------
pub fn user_query_155_cat08_155_two_out_of_three_multi_agent_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-155", "How is 2oo3 constitutional consensus enforced between agents?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Tri-Agent Swarm Message Board") |> should.be_true
  decision.reply_markdown |> string.contains("AGY") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 156: What happens if an agent invokes an unallowed tool?
// -----------------------------------------------------------------------------
pub fn user_query_156_cat08_156_unallowed_tool_invocation_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-156", "What happens if an agent invokes an unallowed tool?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Agent Profile") |> should.be_true
  decision.reply_markdown |> string.contains("Tool Allowlist") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 157: What directive inspects agent ecology profiles?
// -----------------------------------------------------------------------------
pub fn user_query_157_cat08_157_ecology_directive_inspection_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-157", "What directive inspects agent ecology profiles?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("UOS Rich Multi-Agent Ecology") |> should.be_true
  decision.reply_markdown |> string.contains("7 Canonical Holon Profiles") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 158: How are agent leases granted in Sa-Plan?
// -----------------------------------------------------------------------------
pub fn user_query_158_cat08_158_agent_leases_saplan_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-158", "How are agent leases granted in Sa-Plan?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Sa-Plan Pipeline") |> should.be_true
  decision.reply_markdown |> string.contains("Sa-Plan Canonical Ledger Status") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 159: What fractal layer governs the swarm ecosystem?
// -----------------------------------------------------------------------------
pub fn user_query_159_cat08_159_swarm_fractal_layer_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-159", "What fractal layer governs the swarm ecosystem?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Tri-Agent Swarm Message Board") |> should.be_true
  decision.reply_markdown |> string.contains("events") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 160: What check validates Tri-Sovereign Governance?
// -----------------------------------------------------------------------------
pub fn user_query_160_cat08_160_governance_checklist_id_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-160", "What check validates Tri-Sovereign Governance?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Tri-Agent Swarm Message Board") |> should.be_true
  decision.reply_markdown |> string.contains("events") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 161: How does the Zenoh pubsub mesh operate in UOS?
// -----------------------------------------------------------------------------
pub fn user_query_161_cat09_161_zenoh_mesh_operations_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-161", "How does the Zenoh pubsub mesh operate in UOS?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A10") |> should.be_true
  decision.reply_markdown |> string.contains("Mesh Telemetry") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 162: What is OpenTelemetry over Zenoh (OoZ)?
// -----------------------------------------------------------------------------
pub fn user_query_162_cat09_162_opentelemetry_over_zenoh_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-162", "What is OpenTelemetry over Zenoh (OoZ)?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A10") |> should.be_true
  decision.reply_markdown |> string.contains("OpenTelemetry") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 163: What is MCP over Zenoh (MoZ)?
// -----------------------------------------------------------------------------
pub fn user_query_163_cat09_163_mcp_over_zenoh_transport_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-163", "What is MCP over Zenoh (MoZ)?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A10") |> should.be_true
  decision.reply_markdown |> string.contains("Mesh Telemetry") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 164: How does Telegram ingress connect to Robot C3I?
// -----------------------------------------------------------------------------
pub fn user_query_164_cat09_164_telegram_ingress_architecture_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-164", "How does Telegram ingress connect to Robot C3I?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Robot C3I") |> should.be_true
  decision.reply_markdown |> string.contains("Sovereign Cybernetic Cockpit") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 165: How is edge telemetry from razr-1 ingested?
// -----------------------------------------------------------------------------
pub fn user_query_165_cat09_165_razr1_edge_telemetry_ingest_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-165", "How is edge telemetry from razr-1 ingested?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Telemetry Payload Ingested") |> should.be_true
  decision.reply_markdown |> string.contains("razr-1") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 166: What is the rack computer vision diagnostic tool?
// -----------------------------------------------------------------------------
pub fn user_query_166_cat09_166_rack_cv_vision_diagnostic_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-166", "What is the rack computer vision diagnostic tool?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Computer Vision Server Rack Diagnostic") |> should.be_true
  decision.reply_markdown |> string.contains("MAX/Mojo ViT model") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 167: What is the chassis acoustic and vibration diagnostic tool?
// -----------------------------------------------------------------------------
pub fn user_query_167_cat09_167_acoustic_vibration_tool_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-167", "What is the chassis acoustic and vibration diagnostic tool?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Acoustic Bearing Degradation") |> should.be_true
  decision.reply_markdown |> string.contains("FFT") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 168: How are bearing fault frequencies detected?
// -----------------------------------------------------------------------------
pub fn user_query_168_cat09_168_bearing_fault_frequency_fft_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-168", "How are bearing fault frequencies detected?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Acoustic Bearing Degradation") |> should.be_true
  decision.reply_markdown |> string.contains("FFT") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 169: What camera zones are inspected by rack-cv?
// -----------------------------------------------------------------------------
pub fn user_query_169_cat09_169_camera_zones_inspected_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-169", "What camera zones are inspected by rack-cv?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Bay 0 (CRITICAL LOCKOUT)") |> should.be_true
  decision.reply_markdown |> string.contains("Bay 3") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 170: How does the AG-UI 32-event protocol publish telemetry?
// -----------------------------------------------------------------------------
pub fn user_query_170_cat09_170_agui_32_events_telemetry_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-170", "How does the AG-UI 32-event protocol publish telemetry?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A11") |> should.be_true
  decision.reply_markdown |> string.contains("Agent Event Bus Protocol") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 171: What are the 5 lifecycle events in AG-UI?
// -----------------------------------------------------------------------------
pub fn user_query_171_cat09_171_agui_lifecycle_events_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-171", "What are the 5 lifecycle events in AG-UI?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A11") |> should.be_true
  decision.reply_markdown |> string.contains("32 isomorphic event types") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 172: What are the 7 reasoning events in AG-UI?
// -----------------------------------------------------------------------------
pub fn user_query_172_cat09_172_agui_reasoning_events_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-172", "What are the 7 reasoning events in AG-UI?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A11") |> should.be_true
  decision.reply_markdown |> string.contains("Agent Event Bus Protocol") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 173: How does C3I correlate logs across languages?
// -----------------------------------------------------------------------------
pub fn user_query_173_cat09_173_correlated_logging_w3c_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-173", "How does C3I correlate logs across languages?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A10") |> should.be_true
  decision.reply_markdown |> string.contains("128-bit W3C OTel trace_id") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 174: What timestamp format is required for telemetry logs?
// -----------------------------------------------------------------------------
pub fn user_query_174_cat09_174_telemetry_timestamp_format_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-174", "What timestamp format is required for telemetry logs?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A10") |> should.be_true
  decision.reply_markdown |> string.contains("UTC microsecond timestamps") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 175: Where is edge telemetry stored on nas-1?
// -----------------------------------------------------------------------------
pub fn user_query_175_cat09_175_edge_telemetry_ledger_path_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-175", "Where is edge telemetry stored on nas-1?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Telemetry Payload Ingested") |> should.be_true
  decision.reply_markdown |> string.contains("var/telemetry/razr1_telemetry.jsonl") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 176: What directive monitors acoustic HUD in real time?
// -----------------------------------------------------------------------------
pub fn user_query_176_cat09_176_acoustic_hud_monitoring_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-176", "What directive monitors acoustic HUD in real time?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Acoustic Bearing Degradation") |> should.be_true
  decision.reply_markdown |> string.contains("FFT") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 177: What happens if Zenoh mesh connection drops?
// -----------------------------------------------------------------------------
pub fn user_query_177_cat09_177_zenoh_drop_reconnection_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-177", "What happens if Zenoh mesh connection drops?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A10") |> should.be_true
  decision.reply_markdown |> string.contains("Mesh Telemetry") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 178: What fractal layer governs telemetry and observability?
// -----------------------------------------------------------------------------
pub fn user_query_178_cat09_178_telemetry_fractal_layers_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-178", "What fractal layer governs telemetry and observability?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A10") |> should.be_true
  decision.reply_markdown |> string.contains("L4 System / L6 Swarm Ecosystem") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 179: What STAMP control governs telemetry observability?
// -----------------------------------------------------------------------------
pub fn user_query_179_cat09_179_stamp_telemetry_control_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-179", "What STAMP control governs telemetry observability?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A10") |> should.be_true
  decision.reply_markdown |> string.contains("Mesh Telemetry") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 180: What check validates telemetry logging compliance?
// -----------------------------------------------------------------------------
pub fn user_query_180_cat09_180_telemetry_checklist_check_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-180", "What check validates telemetry logging compliance?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Aspect A10") |> should.be_true
  decision.reply_markdown |> string.contains("CHK-16-OTEL") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 181: What operator directives can I send to Robot C3I?
// -----------------------------------------------------------------------------
pub fn user_query_181_cat10_181_operator_directives_reference_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-181", "What operator directives can I send to Robot C3I?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("48 Canonical Directives") |> should.be_true
  decision.reply_markdown |> string.contains("Domain A") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 182: What are the 4 directive domains in Robot C3I?
// -----------------------------------------------------------------------------
pub fn user_query_182_cat10_182_four_directive_domains_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-182", "What are the 4 directive domains in Robot C3I?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Domain A: Foundational SRE") |> should.be_true
  decision.reply_markdown |> string.contains("Domain B") |> should.be_true
  decision.reply_markdown |> string.contains("Domain C") |> should.be_true
  decision.reply_markdown |> string.contains("Domain D") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 183: What are the Tailscale FQDN links for UOS?
// -----------------------------------------------------------------------------
pub fn user_query_183_cat10_183_tailscale_fqdn_links_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-183", "What are the Tailscale FQDN links for UOS?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("http://nas-1.tail55d152.ts.net:4100") |> should.be_true
  decision.reply_markdown |> string.contains("Main Cockpit Dashboard") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 184: Show me the cockpit dashboard navigation links
// -----------------------------------------------------------------------------
pub fn user_query_184_cat10_184_cockpit_dashboard_navigation_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-184", "Show me the cockpit dashboard navigation links")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Tailscale FQDN Web Navigation") |> should.be_true
  decision.reply_markdown |> string.contains("Planning Cockpit") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 185: What is Sa-Plan exclusivity mandate?
// -----------------------------------------------------------------------------
pub fn user_query_185_cat10_185_saplan_exclusivity_mandate_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-185", "What is Sa-Plan exclusivity mandate?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Sa-Plan Pipeline") |> should.be_true
  decision.reply_markdown |> string.contains("Sa-Plan Canonical Ledger Status") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 186: What is the Fractal Jidoka Andon Stop Line?
// -----------------------------------------------------------------------------
pub fn user_query_186_cat10_186_fractal_jidoka_andon_line_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-186", "What is the Fractal Jidoka Andon Stop Line?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Sa-Plan Pipeline") |> should.be_true
  decision.reply_markdown |> string.contains("Sa-Plan Canonical Ledger Status") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 187: Where is the canonical Sa-Plan database stored?
// -----------------------------------------------------------------------------
pub fn user_query_187_cat10_187_saplan_database_location_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-187", "Where is the canonical Sa-Plan database stored?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Sa-Plan Pipeline") |> should.be_true
  decision.reply_markdown |> string.contains("Sa-Plan Canonical Ledger Status") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 188: What is a Heijunka pull queue in Sa-Plan?
// -----------------------------------------------------------------------------
pub fn user_query_188_cat10_188_heijunka_pull_queues_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-188", "What is a Heijunka pull queue in Sa-Plan?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Sa-Plan Pipeline") |> should.be_true
  decision.reply_markdown |> string.contains("Sa-Plan Canonical Ledger Status") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 189: How does the 2oo3 approval workflow operate via Telegram?
// -----------------------------------------------------------------------------
pub fn user_query_189_cat10_189_two_out_of_three_telegram_approval_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-189", "How does the 2oo3 approval workflow operate via Telegram?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("48 Canonical Directives") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 190: What does the /doctor directive do?
// -----------------------------------------------------------------------------
pub fn user_query_190_cat10_190_doctor_diagnostic_directive_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-190", "What does the /doctor directive do?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("UOS Comprehensive Verification Scorecard") |> should.be_true
  decision.reply_markdown |> string.contains("18/18") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 191: What does the /checklist directive return?
// -----------------------------------------------------------------------------
pub fn user_query_191_cat10_191_checklist_scorecard_directive_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-191", "What does the /checklist directive return?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("UOS Comprehensive Verification Scorecard") |> should.be_true
  decision.reply_markdown |> string.contains("18/18 (100% GREEN)") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 192: How do I look up an architectural decision record?
// -----------------------------------------------------------------------------
pub fn user_query_192_cat10_192_zk_adr_lookup_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-192", "How do I look up an architectural decision record?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("48 Canonical Directives") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 193: How do I transclude a Hermes wiki article?
// -----------------------------------------------------------------------------
pub fn user_query_193_cat10_193_wiki_transclusion_lookup_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-193", "How do I transclude a Hermes wiki article?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("48 Canonical Directives") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 194: What directive triggers a chaos test drill?
// -----------------------------------------------------------------------------
pub fn user_query_194_cat10_194_chaos_test_directive_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-194", "What directive triggers a chaos test drill?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("48 Canonical Directives") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 195: What directive triggers autonomous disaster resuscitation?
// -----------------------------------------------------------------------------
pub fn user_query_195_cat10_195_resuscitate_disaster_recovery_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-195", "What directive triggers autonomous disaster resuscitation?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("48 Canonical Directives") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 196: What is the dark cockpit directive?
// -----------------------------------------------------------------------------
pub fn user_query_196_cat10_196_dark_cockpit_directive_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-196", "What is the dark cockpit directive?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("48 Canonical Directives") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 197: What directive inspects FinOps cloud budget spend?
// -----------------------------------------------------------------------------
pub fn user_query_197_cat10_197_finops_cloud_budget_directive_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-197", "What directive inspects FinOps cloud budget spend?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("48 Canonical Directives") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 198: What directive performs an automated git/JJ bisect?
// -----------------------------------------------------------------------------
pub fn user_query_198_cat10_198_bisect_automated_debugging_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-198", "What directive performs an automated git/JJ bisect?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("48 Canonical Directives") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 199: What directive triggers an emergency Andon stop?
// -----------------------------------------------------------------------------
pub fn user_query_199_cat10_199_emergency_andon_stop_directive_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-199", "What directive triggers an emergency Andon stop?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Sa-Plan Pipeline") |> should.be_true
}

// -----------------------------------------------------------------------------
// Query 200: How does the system ensure zero un-ledgered tasks exist?
// -----------------------------------------------------------------------------
pub fn user_query_200_cat20_200_zero_unledgered_tasks_enforcement_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_test_intent("query-200", "How does the system ensure zero un-ledgered tasks exist?")
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  { decision.confidence >. 0.9 } |> should.be_true
  decision.reply_markdown |> string.contains("Sa-Plan Pipeline") |> should.be_true
}
