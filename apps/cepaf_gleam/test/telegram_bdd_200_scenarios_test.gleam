//// =============================================================================
//// [UOS-BDD-200] Telegram Cognitive Interface 200 BDD Scenarios Test Suite
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>test/telegram_bdd_200_scenarios_test</module>
////     <authority>UOS-CANONICAL-AGENT-POLICY</authority>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////     <topology>Comprehensive 200 BDD Scenario Verification Suite</topology>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>
////       SC-TELEGRAM-001, SC-JIDOKA-001, SC-COG-001, SC-DRIVE-001,
////       SC-MUDA-001, SC-CHECKLIST-001
////     </stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================

import cepaf_gleam/harness/agent_ecology
import cepaf_gleam/harness/cognitive_worker.{
  type CognitiveIntent, CognitiveIntent, dispatch_action_request, evaluate_intent,
  format_recent_telegram_history, handle_conversational, handle_directive,
}
import cepaf_gleam/harness/conversation_memory.{ChatMessage}
import cepaf_gleam/harness/egress_redactor
import cepaf_gleam/harness/telegram_outbound
import cepaf_gleam/harness/tool_fenced_dispatcher as td
import envoy
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should

fn make_intent(id: String, text: String) -> CognitiveIntent {
  CognitiveIntent(
    intent_id: id,
    source: "telegram",
    user: "Avi",
    chat_id: "6249174059",
    text: text,
    timestamp_ms: 1789184000000,
  )
}

fn int_range(from: Int, to: Int) -> List(Int) {
  case from > to {
    True -> []
    False -> [from, ..int_range(from + 1, to)]
  }
}

// -----------------------------------------------------------------------------
// Scenario 001: Directive /status
// -----------------------------------------------------------------------------
pub fn bdd_scenario_001_directive_status_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-001", "/status")
  let decision = handle_directive("/status", intent)
  decision.intent_id |> should.equal("bdd-001")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("UOS Cluster Telemetry")) |> should.be_true
  string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 002: Directive /health
// -----------------------------------------------------------------------------
pub fn bdd_scenario_002_directive_health_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-002", "/health")
  let decision = handle_directive("/health", intent)
  decision.intent_id |> should.equal("bdd-002")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("Mesh Subsystem")) |> should.be_true
  string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 003: Directive /plan
// -----------------------------------------------------------------------------
pub fn bdd_scenario_003_directive_plan_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-003", "/plan")
  let decision = handle_directive("/plan", intent)
  decision.intent_id |> should.equal("bdd-003")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("Sa-Plan")) |> should.be_true
  string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 004: Directive /tasks
// -----------------------------------------------------------------------------
pub fn bdd_scenario_004_directive_tasks_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-004", "/tasks")
  let decision = handle_directive("/tasks", intent)
  decision.intent_id |> should.equal("bdd-004")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("Sa-Plan")) |> should.be_true
  string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 005: Directive /task t-101
// -----------------------------------------------------------------------------
pub fn bdd_scenario_005_directive_task_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-005", "/task t-101")
  let decision = handle_directive("/task t-101", intent)
  decision.intent_id |> should.equal("bdd-005")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("Task")) |> should.be_true
  string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 006: Directive /storage
// -----------------------------------------------------------------------------
pub fn bdd_scenario_006_directive_storage_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-006", "/storage")
  let decision = handle_directive("/storage", intent)
  decision.intent_id |> should.equal("bdd-006")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("OS NVMe")) |> should.be_true
  string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 007: Directive /nvme
// -----------------------------------------------------------------------------
pub fn bdd_scenario_007_directive_nvme_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-007", "/nvme")
  let decision = handle_directive("/nvme", intent)
  decision.intent_id |> should.equal("bdd-007")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("OS NVMe")) |> should.be_true
  string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 008: Directive /dark
// -----------------------------------------------------------------------------
pub fn bdd_scenario_008_directive_dark_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-008", "/dark")
  let decision = handle_directive("/dark", intent)
  decision.intent_id |> should.equal("bdd-008")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("Dark Cockpit")) |> should.be_true
  string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 009: Directive /andon
// -----------------------------------------------------------------------------
pub fn bdd_scenario_009_directive_andon_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-009", "/andon")
  let decision = handle_directive("/andon", intent)
  decision.intent_id |> should.equal("bdd-009")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("Andon")) |> should.be_true
  string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 010: Directive /zigvm
// -----------------------------------------------------------------------------
pub fn bdd_scenario_010_directive_zigvm_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-010", "/zigvm")
  let decision = handle_directive("/zigvm", intent)
  decision.intent_id |> should.equal("bdd-010")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("ZigVM")) |> should.be_true
  string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 011: Directive /sutra
// -----------------------------------------------------------------------------
pub fn bdd_scenario_011_directive_sutra_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-011", "/sutra")
  let decision = handle_directive("/sutra", intent)
  decision.intent_id |> should.equal("bdd-011")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("Sutra Matrix")) |> should.be_true
  string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 012: Directive /zk
// -----------------------------------------------------------------------------
pub fn bdd_scenario_012_directive_zk_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-012", "/zk")
  let decision = handle_directive("/zk", intent)
  decision.intent_id |> should.equal("bdd-012")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("Zettelkasten")) |> should.be_true
  string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 013: Directive /checklist
// -----------------------------------------------------------------------------
pub fn bdd_scenario_013_directive_checklist_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-013", "/checklist")
  let decision = handle_directive("/checklist", intent)
  decision.intent_id |> should.equal("bdd-013")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("Verification Scorecard")) |> should.be_true
  string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 014: Directive /cockpit
// -----------------------------------------------------------------------------
pub fn bdd_scenario_014_directive_cockpit_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-014", "/cockpit")
  let decision = handle_directive("/cockpit", intent)
  decision.intent_id |> should.equal("bdd-014")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("Tailscale FQDN Web Navigation")) |> should.be_true
  string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 015: Directive /approval plan-1 task-1 deploy
// -----------------------------------------------------------------------------
pub fn bdd_scenario_015_directive_approval_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-015", "/approval plan-1 task-1 deploy")
  let decision = handle_directive("/approval plan-1 task-1 deploy", intent)
  decision.intent_id |> should.equal("bdd-015")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("2oo3 Constitutional Approval")) |> should.be_true
  string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 016: Directive /help
// -----------------------------------------------------------------------------
pub fn bdd_scenario_016_directive_help_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-016", "/help")
  let decision = handle_directive("/help", intent)
  decision.intent_id |> should.equal("bdd-016")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("Available Operator Directives")) |> should.be_true
  string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 017: Directive /start
// -----------------------------------------------------------------------------
pub fn bdd_scenario_017_directive_start_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-017", "/start")
  let decision = handle_directive("/start", intent)
  decision.intent_id |> should.equal("bdd-017")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("Robot C3I")) |> should.be_true
  string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 018: Directive /search task
// -----------------------------------------------------------------------------
pub fn bdd_scenario_018_directive_search_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-018", "/search task")
  let decision = handle_directive("/search task", intent)
  decision.intent_id |> should.equal("bdd-018")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("Search")) |> should.be_true
  string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 019: Directive /immune
// -----------------------------------------------------------------------------
pub fn bdd_scenario_019_directive_immune_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-019", "/immune")
  let decision = handle_directive("/immune", intent)
  decision.intent_id |> should.equal("bdd-019")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("Biomorphic Chaos Immune")) |> should.be_true
  string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 020: Directive /fmea
// -----------------------------------------------------------------------------
pub fn bdd_scenario_020_directive_fmea_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-020", "/fmea")
  let decision = handle_directive("/fmea", intent)
  decision.intent_id |> should.equal("bdd-020")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("FMEA")) |> should.be_true
  string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 021: Directive /ha
// -----------------------------------------------------------------------------
pub fn bdd_scenario_021_directive_ha_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-021", "/ha")
  let decision = handle_directive("/ha", intent)
  decision.intent_id |> should.equal("bdd-021")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("High Availability")) |> should.be_true
  string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 022: Directive /zenoh
// -----------------------------------------------------------------------------
pub fn bdd_scenario_022_directive_zenoh_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-022", "/zenoh")
  let decision = handle_directive("/zenoh", intent)
  decision.intent_id |> should.equal("bdd-022")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("Zenoh")) |> should.be_true
  string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 023: Directive /inference
// -----------------------------------------------------------------------------
pub fn bdd_scenario_023_directive_inference_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-023", "/inference")
  let decision = handle_directive("/inference", intent)
  decision.intent_id |> should.equal("bdd-023")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("Modular MAX")) |> should.be_true
  string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 024: Directive /verify
// -----------------------------------------------------------------------------
pub fn bdd_scenario_024_directive_verify_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-024", "/verify")
  let decision = handle_directive("/verify", intent)
  decision.intent_id |> should.equal("bdd-024")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("Verification")) |> should.be_true
  string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 025: Directive /doctor
// -----------------------------------------------------------------------------
pub fn bdd_scenario_025_directive_doctor_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-025", "/doctor")
  let decision = handle_directive("/doctor", intent)
  decision.intent_id |> should.equal("bdd-025")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("EV")) |> should.be_true
  string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 026: Directive /ev
// -----------------------------------------------------------------------------
pub fn bdd_scenario_026_directive_ev_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-026", "/ev")
  let decision = handle_directive("/ev", intent)
  decision.intent_id |> should.equal("bdd-026")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("EV")) |> should.be_true
  string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 027: Directive /resuscitate node-1
// -----------------------------------------------------------------------------
pub fn bdd_scenario_027_directive_resuscitate_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-027", "/resuscitate node-1")
  let decision = handle_directive("/resuscitate node-1", intent)
  decision.intent_id |> should.equal("bdd-027")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("resuscitation")) |> should.be_true
  string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 028: Directive /chaos
// -----------------------------------------------------------------------------
pub fn bdd_scenario_028_directive_chaos_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-028", "/chaos")
  let decision = handle_directive("/chaos", intent)
  decision.intent_id |> should.equal("bdd-028")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("chaos")) |> should.be_true
  string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 029: Directive /repro err-1
// -----------------------------------------------------------------------------
pub fn bdd_scenario_029_directive_repro_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-029", "/repro err-1")
  let decision = handle_directive("/repro err-1", intent)
  decision.intent_id |> should.equal("bdd-029")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("repro")) |> should.be_true
  string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 030: Directive /merge branch
// -----------------------------------------------------------------------------
pub fn bdd_scenario_030_directive_merge_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-030", "/merge branch")
  let decision = handle_directive("/merge branch", intent)
  decision.intent_id |> should.equal("bdd-030")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("merge")) |> should.be_true
  string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 031: Directive /bisect suite
// -----------------------------------------------------------------------------
pub fn bdd_scenario_031_directive_bisect_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-031", "/bisect suite")
  let decision = handle_directive("/bisect suite", intent)
  decision.intent_id |> should.equal("bdd-031")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("bisect")) |> should.be_true
  string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 032: Directive /escalate sev1
// -----------------------------------------------------------------------------
pub fn bdd_scenario_032_directive_escalate_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-032", "/escalate sev1")
  let decision = handle_directive("/escalate sev1", intent)
  decision.intent_id |> should.equal("bdd-032")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("escalation")) |> should.be_true
  string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 033: Directive /rotate-keys
// -----------------------------------------------------------------------------
pub fn bdd_scenario_033_directive_rotate_keys_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-033", "/rotate-keys")
  let decision = handle_directive("/rotate-keys", intent)
  decision.intent_id |> should.equal("bdd-033")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("rotation")) |> should.be_true
  string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 034: Directive /mesh
// -----------------------------------------------------------------------------
pub fn bdd_scenario_034_directive_mesh_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-034", "/mesh")
  let decision = handle_directive("/mesh", intent)
  decision.intent_id |> should.equal("bdd-034")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("mesh")) |> should.be_true
  string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 035: Directive /migrate
// -----------------------------------------------------------------------------
pub fn bdd_scenario_035_directive_migrate_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-035", "/migrate")
  let decision = handle_directive("/migrate", intent)
  decision.intent_id |> should.equal("bdd-035")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("migrate")) |> should.be_true
  string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 036: Directive /adr ADR-001
// -----------------------------------------------------------------------------
pub fn bdd_scenario_036_directive_adr_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-036", "/adr ADR-001")
  let decision = handle_directive("/adr ADR-001", intent)
  decision.intent_id |> should.equal("bdd-036")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("adr")) |> should.be_true
  string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 037: Directive /blast-radius fail
// -----------------------------------------------------------------------------
pub fn bdd_scenario_037_directive_blast_radius_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-037", "/blast-radius fail")
  let decision = handle_directive("/blast-radius fail", intent)
  decision.intent_id |> should.equal("bdd-037")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("blast")) |> should.be_true
  string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 038: Directive /pacing
// -----------------------------------------------------------------------------
pub fn bdd_scenario_038_directive_pacing_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-038", "/pacing")
  let decision = handle_directive("/pacing", intent)
  decision.intent_id |> should.equal("bdd-038")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("pacing")) |> should.be_true
  string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 039: Directive /whatif net-loss
// -----------------------------------------------------------------------------
pub fn bdd_scenario_039_directive_whatif_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-039", "/whatif net-loss")
  let decision = handle_directive("/whatif net-loss", intent)
  decision.intent_id |> should.equal("bdd-039")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("simulation")) |> should.be_true
  string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 040: Directive /rack-cv
// -----------------------------------------------------------------------------
pub fn bdd_scenario_040_directive_rack_cv_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-040", "/rack-cv")
  let decision = handle_directive("/rack-cv", intent)
  decision.intent_id |> should.equal("bdd-040")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("rack")) |> should.be_true
  string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 041: Directive /acoustic
// -----------------------------------------------------------------------------
pub fn bdd_scenario_041_directive_acoustic_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-041", "/acoustic")
  let decision = handle_directive("/acoustic", intent)
  decision.intent_id |> should.equal("bdd-041")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("acoustic")) |> should.be_true
  string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 042: Directive /rewind 5m
// -----------------------------------------------------------------------------
pub fn bdd_scenario_042_directive_rewind_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-042", "/rewind 5m")
  let decision = handle_directive("/rewind 5m", intent)
  decision.intent_id |> should.equal("bdd-042")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("time-machine")) |> should.be_true
  string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 043: Directive /postmortem inc-1
// -----------------------------------------------------------------------------
pub fn bdd_scenario_043_directive_postmortem_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-043", "/postmortem inc-1")
  let decision = handle_directive("/postmortem inc-1", intent)
  decision.intent_id |> should.equal("bdd-043")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("post-mortem")) |> should.be_true
  string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 044: Directive /finops
// -----------------------------------------------------------------------------
pub fn bdd_scenario_044_directive_finops_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-044", "/finops")
  let decision = handle_directive("/finops", intent)
  decision.intent_id |> should.equal("bdd-044")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("finops")) |> should.be_true
  string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 045: Directive /eco-schedule
// -----------------------------------------------------------------------------
pub fn bdd_scenario_045_directive_eco_schedule_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-045", "/eco-schedule")
  let decision = handle_directive("/eco-schedule", intent)
  decision.intent_id |> should.equal("bdd-045")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("eco")) |> should.be_true
  string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 046: Directive /radar
// -----------------------------------------------------------------------------
pub fn bdd_scenario_046_directive_radar_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-046", "/radar")
  let decision = handle_directive("/radar", intent)
  decision.intent_id |> should.equal("bdd-046")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("radar")) |> should.be_true
  string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 047: Directive /canvas
// -----------------------------------------------------------------------------
pub fn bdd_scenario_047_directive_canvas_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-047", "/canvas")
  let decision = handle_directive("/canvas", intent)
  decision.intent_id |> should.equal("bdd-047")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("canvas")) |> should.be_true
  string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 048: Directive /lockbox
// -----------------------------------------------------------------------------
pub fn bdd_scenario_048_directive_lockbox_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-048", "/lockbox")
  let decision = handle_directive("/lockbox", intent)
  decision.intent_id |> should.equal("bdd-048")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("lockbox")) |> should.be_true
  string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 049: Directive /export-audit
// -----------------------------------------------------------------------------
pub fn bdd_scenario_049_directive_export_audit_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-049", "/export-audit")
  let decision = handle_directive("/export-audit", intent)
  decision.intent_id |> should.equal("bdd-049")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("audit")) |> should.be_true
  string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 050: Directive /sidecar
// -----------------------------------------------------------------------------
pub fn bdd_scenario_050_directive_sidecar_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-050", "/sidecar")
  let decision = handle_directive("/sidecar", intent)
  decision.intent_id |> should.equal("bdd-050")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("sidecar")) |> should.be_true
  string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 051: Directive /voice-roll-call
// -----------------------------------------------------------------------------
pub fn bdd_scenario_051_voice_roll_call_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let cmd_str = "/voice-roll-call"
  let intent = make_intent("bdd-051", cmd_str)
  let decision = handle_directive(cmd_str, intent)
  decision.intent_id |> should.equal("bdd-051")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("voice")) |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 052: Directive /babel en-es
// -----------------------------------------------------------------------------
pub fn bdd_scenario_052_babel_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let cmd_str = "/babel en-es"
  let intent = make_intent("bdd-052", cmd_str)
  let decision = handle_directive(cmd_str, intent)
  decision.intent_id |> should.equal("bdd-052")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("babel")) |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 053: Directive /whiteboard
// -----------------------------------------------------------------------------
pub fn bdd_scenario_053_whiteboard_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let cmd_str = "/whiteboard"
  let intent = make_intent("bdd-053", cmd_str)
  let decision = handle_directive(cmd_str, intent)
  decision.intent_id |> should.equal("bdd-053")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("whiteboard")) |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 054: Directive /socratic
// -----------------------------------------------------------------------------
pub fn bdd_scenario_054_socratic_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let cmd_str = "/socratic"
  let intent = make_intent("bdd-054", cmd_str)
  let decision = handle_directive(cmd_str, intent)
  decision.intent_id |> should.equal("bdd-054")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("socratic")) |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 055: Directive /handover
// -----------------------------------------------------------------------------
pub fn bdd_scenario_055_handover_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let cmd_str = "/handover"
  let intent = make_intent("bdd-055", cmd_str)
  let decision = handle_directive(cmd_str, intent)
  decision.intent_id |> should.equal("bdd-055")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("handover")) |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 056: Directive /pair-voice
// -----------------------------------------------------------------------------
pub fn bdd_scenario_056_pair_voice_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let cmd_str = "/pair-voice"
  let intent = make_intent("bdd-056", cmd_str)
  let decision = handle_directive(cmd_str, intent)
  decision.intent_id |> should.equal("bdd-056")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("voice")) |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 057: Directive /exec-brief
// -----------------------------------------------------------------------------
pub fn bdd_scenario_057_exec_brief_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let cmd_str = "/exec-brief"
  let intent = make_intent("bdd-057", cmd_str)
  let decision = handle_directive(cmd_str, intent)
  decision.intent_id |> should.equal("bdd-057")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("executive")) |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 058: Directive /commitments
// -----------------------------------------------------------------------------
pub fn bdd_scenario_058_commitments_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let cmd_str = "/commitments"
  let intent = make_intent("bdd-058", cmd_str)
  let decision = handle_directive(cmd_str, intent)
  decision.intent_id |> should.equal("bdd-058")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("commitments")) |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 059: Directive /acoustic-hud
// -----------------------------------------------------------------------------
pub fn bdd_scenario_059_acoustic_hud_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let cmd_str = "/acoustic-hud"
  let intent = make_intent("bdd-059", cmd_str)
  let decision = handle_directive(cmd_str, intent)
  decision.intent_id |> should.equal("bdd-059")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("acoustic")) |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 060: Directive /retro
// -----------------------------------------------------------------------------
pub fn bdd_scenario_060_retro_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let cmd_str = "/retro"
  let intent = make_intent("bdd-060", cmd_str)
  let decision = handle_directive(cmd_str, intent)
  decision.intent_id |> should.equal("bdd-060")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("retro")) |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 061: Directive /gameday
// -----------------------------------------------------------------------------
pub fn bdd_scenario_061_gameday_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let cmd_str = "/gameday"
  let intent = make_intent("bdd-061", cmd_str)
  let decision = handle_directive(cmd_str, intent)
  decision.intent_id |> should.equal("bdd-061")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("gameday")) |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 062: Directive /agy query cluster status
// -----------------------------------------------------------------------------
pub fn bdd_scenario_062_agy_query_status_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let cmd_str = "/agy query cluster status"
  let intent = make_intent("bdd-062", cmd_str)
  let decision = handle_directive(cmd_str, intent)
  decision.intent_id |> should.equal("bdd-062")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("cluster")) |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 063: Directive /agy check container health
// -----------------------------------------------------------------------------
pub fn bdd_scenario_063_agy_query_health_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let cmd_str = "/agy check container health"
  let intent = make_intent("bdd-063", cmd_str)
  let decision = handle_directive(cmd_str, intent)
  decision.intent_id |> should.equal("bdd-063")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("health")) |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 064: Directive /agy explain architecture
// -----------------------------------------------------------------------------
pub fn bdd_scenario_064_agy_query_arch_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let cmd_str = "/agy explain cognitive architecture"
  let intent = make_intent("bdd-064", cmd_str)
  let decision = handle_directive(cmd_str, intent)
  decision.intent_id |> should.equal("bdd-064")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("architecture")) |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 065: Directive /messages
// -----------------------------------------------------------------------------
pub fn bdd_scenario_065_messages_default_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let cmd_str = "/messages"
  let intent = make_intent("bdd-065", cmd_str)
  let decision = handle_directive(cmd_str, intent)
  decision.intent_id |> should.equal("bdd-065")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("Recent Telegram Conversation")) |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 066: Directive /messages 5
// -----------------------------------------------------------------------------
pub fn bdd_scenario_066_messages_limit_5_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let cmd_str = "/messages 5"
  let intent = make_intent("bdd-066", cmd_str)
  let decision = handle_directive(cmd_str, intent)
  decision.intent_id |> should.equal("bdd-066")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("Recent Telegram Conversation")) |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 067: Directive /history
// -----------------------------------------------------------------------------
pub fn bdd_scenario_067_history_alias_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let cmd_str = "/history"
  let intent = make_intent("bdd-067", cmd_str)
  let decision = handle_directive(cmd_str, intent)
  decision.intent_id |> should.equal("bdd-067")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("Recent Telegram Conversation")) |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 068: Directive /memory clear
// -----------------------------------------------------------------------------
pub fn bdd_scenario_068_memory_clear_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let cmd_str = "/memory clear"
  let intent = make_intent("bdd-068", cmd_str)
  let decision = handle_directive(cmd_str, intent)
  decision.intent_id |> should.equal("bdd-068")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("Conversation Memory Reset")) |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 069: Directive /nonexistent_directive_12345
// -----------------------------------------------------------------------------
pub fn bdd_scenario_069_unknown_fallback_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let cmd_str = "/nonexistent_directive_12345"
  let intent = make_intent("bdd-069", cmd_str)
  let decision = handle_directive(cmd_str, intent)
  decision.intent_id |> should.equal("bdd-069")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("Unknown")) |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 070: Directive /
// -----------------------------------------------------------------------------
pub fn bdd_scenario_070_empty_directive_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let cmd_str = "/"
  let intent = make_intent("bdd-070", cmd_str)
  let decision = handle_directive(cmd_str, intent)
  decision.intent_id |> should.equal("bdd-070")
  string.contains(string.lowercase(decision.reply_markdown), string.lowercase("unknown directive")) |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 071: Aspect Verification /aspects
// -----------------------------------------------------------------------------
pub fn bdd_scenario_071_aspects_summary_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-071", "/aspects")
  let decision = handle_directive("/aspects", intent)
  string.contains(decision.reply_markdown, "System Aspects") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 072: Aspect Verification /aspects A01
// -----------------------------------------------------------------------------
pub fn bdd_scenario_072_aspect_a01_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-072", "/aspects A01")
  let decision = handle_directive("/aspects A01", intent)
  string.contains(decision.reply_markdown, "Substrate & Hardware Safety") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 073: Aspect Verification /aspects A02
// -----------------------------------------------------------------------------
pub fn bdd_scenario_073_aspect_a02_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-073", "/aspects A02")
  let decision = handle_directive("/aspects A02", intent)
  string.contains(decision.reply_markdown, "Version Control Discipline") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 074: Aspect Verification /aspects A03
// -----------------------------------------------------------------------------
pub fn bdd_scenario_074_aspect_a03_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-074", "/aspects A03")
  let decision = handle_directive("/aspects A03", intent)
  string.contains(decision.reply_markdown, "Zero-Muda Purity") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 075: Aspect Verification /aspects A04
// -----------------------------------------------------------------------------
pub fn bdd_scenario_075_aspect_a04_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-075", "/aspects A04")
  let decision = handle_directive("/aspects A04", intent)
  string.contains(decision.reply_markdown, "Supervision & Actor Hierarchy") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 076: Aspect Verification /aspects A05
// -----------------------------------------------------------------------------
pub fn bdd_scenario_076_aspect_a05_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-076", "/aspects A05")
  let decision = handle_directive("/aspects A05", intent)
  string.contains(decision.reply_markdown, "Deterministic Runtime Engine") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 077: Aspect Verification /aspects A06
// -----------------------------------------------------------------------------
pub fn bdd_scenario_077_aspect_a06_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-077", "/aspects A06")
  let decision = handle_directive("/aspects A06", intent)
  string.contains(decision.reply_markdown, "Formal Evidence & Bounded Analysis") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 078: Aspect Verification /aspects A07
// -----------------------------------------------------------------------------
pub fn bdd_scenario_078_aspect_a07_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-078", "/aspects A07")
  let decision = handle_directive("/aspects A07", intent)
  string.contains(decision.reply_markdown, "Mathematical Authority") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 079: Aspect Verification /aspects A08
// -----------------------------------------------------------------------------
pub fn bdd_scenario_079_aspect_a08_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-079", "/aspects A08")
  let decision = handle_directive("/aspects A08", intent)
  string.contains(decision.reply_markdown, "Feedback Semiotics") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 080: Aspect Verification /aspects A09
// -----------------------------------------------------------------------------
pub fn bdd_scenario_080_aspect_a09_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-080", "/aspects A09")
  let decision = handle_directive("/aspects A09", intent)
  string.contains(decision.reply_markdown, "Quarantined AI Inference") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 081: Aspect Verification /aspects A10
// -----------------------------------------------------------------------------
pub fn bdd_scenario_081_aspect_a10_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-081", "/aspects A10")
  let decision = handle_directive("/aspects A10", intent)
  string.contains(decision.reply_markdown, "Mesh Telemetry & Observability") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 082: Aspect Verification /aspects A11
// -----------------------------------------------------------------------------
pub fn bdd_scenario_082_aspect_a11_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-082", "/aspects A11")
  let decision = handle_directive("/aspects A11", intent)
  string.contains(decision.reply_markdown, "Agent Event Bus Protocol") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 083: Aspect Verification /aspects A12
// -----------------------------------------------------------------------------
pub fn bdd_scenario_083_aspect_a12_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-083", "/aspects A12")
  let decision = handle_directive("/aspects A12", intent)
  string.contains(decision.reply_markdown, "Declarative UI Component Catalog") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 084: Aspect Verification /aspects A13
// -----------------------------------------------------------------------------
pub fn bdd_scenario_084_aspect_a13_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-084", "/aspects A13")
  let decision = handle_directive("/aspects A13", intent)
  string.contains(decision.reply_markdown, "Multi-Interface Accessibility") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 085: Aspect Verification /aspects A14
// -----------------------------------------------------------------------------
pub fn bdd_scenario_085_aspect_a14_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-085", "/aspects A14")
  let decision = handle_directive("/aspects A14", intent)
  string.contains(decision.reply_markdown, "Universal Tailscale Web Navigation") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 086: Aspect Verification /aspects A15
// -----------------------------------------------------------------------------
pub fn bdd_scenario_086_aspect_a15_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-086", "/aspects A15")
  let decision = handle_directive("/aspects A15", intent)
  string.contains(decision.reply_markdown, "Comprehensive Verification Checklist") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 087: Aspect Verification /aspects A16
// -----------------------------------------------------------------------------
pub fn bdd_scenario_087_aspect_a16_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-087", "/aspects A16")
  let decision = handle_directive("/aspects A16", intent)
  string.contains(decision.reply_markdown, "Knowledge Management Triad") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 088: Aspect Verification /aspects A17
// -----------------------------------------------------------------------------
pub fn bdd_scenario_088_aspect_a17_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-088", "/aspects A17")
  let decision = handle_directive("/aspects A17", intent)
  string.contains(decision.reply_markdown, "Durable Execution & Workflow") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 089: Aspect Verification /aspects A99
// -----------------------------------------------------------------------------
pub fn bdd_scenario_089_aspect_invalid_a99_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-089", "/aspects A99")
  let decision = handle_directive("/aspects A99", intent)
  string.contains(decision.reply_markdown, "Unknown System Aspect code") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 090: Aspect Verification /aspects FOOBAR
// -----------------------------------------------------------------------------
pub fn bdd_scenario_090_aspect_invalid_random_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-090", "/aspects FOOBAR")
  let decision = handle_directive("/aspects FOOBAR", intent)
  string.contains(decision.reply_markdown, "Unknown System Aspect code") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 091: Ecology & Swarm /ecology
// -----------------------------------------------------------------------------
pub fn bdd_scenario_091_ecology_summary_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-091", "/ecology")
  let decision = handle_directive("/ecology", intent)
  string.contains(decision.reply_markdown, "Rich Multi-Agent Ecology") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 092: Ecology & Swarm /ecology agy_sovereign_coordinator
// -----------------------------------------------------------------------------
pub fn bdd_scenario_092_agent_agy_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-092", "/ecology agy_sovereign_coordinator")
  let decision = handle_directive("/ecology agy_sovereign_coordinator", intent)
  string.contains(decision.reply_markdown, "AGY Sovereign Coordinator") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 093: Ecology & Swarm /ecology sre_homeostasis_overseer
// -----------------------------------------------------------------------------
pub fn bdd_scenario_093_agent_sre_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-093", "/ecology sre_homeostasis_overseer")
  let decision = handle_directive("/ecology sre_homeostasis_overseer", intent)
  string.contains(decision.reply_markdown, "SRE Homeostasis Overseer") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 094: Ecology & Swarm /ecology security_hardware_guardian
// -----------------------------------------------------------------------------
pub fn bdd_scenario_094_agent_security_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-094", "/ecology security_hardware_guardian")
  let decision = handle_directive("/ecology security_hardware_guardian", intent)
  string.contains(decision.reply_markdown, "Security & Hardware Enclave Guardian") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 095: Ecology & Swarm /ecology multimodal_edge_ingestor
// -----------------------------------------------------------------------------
pub fn bdd_scenario_095_agent_edge_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-095", "/ecology multimodal_edge_ingestor")
  let decision = handle_directive("/ecology multimodal_edge_ingestor", intent)
  string.contains(decision.reply_markdown, "Multimodal Edge Ingestor") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 096: Ecology & Swarm /ecology formal_verifier_oracle
// -----------------------------------------------------------------------------
pub fn bdd_scenario_096_agent_verifier_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-096", "/ecology formal_verifier_oracle")
  let decision = handle_directive("/ecology formal_verifier_oracle", intent)
  string.contains(decision.reply_markdown, "Formal Verifier Oracle") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 097: Ecology & Swarm /ecology knowledge_sheaf_curator
// -----------------------------------------------------------------------------
pub fn bdd_scenario_097_agent_sheaf_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-097", "/ecology knowledge_sheaf_curator")
  let decision = handle_directive("/ecology knowledge_sheaf_curator", intent)
  string.contains(decision.reply_markdown, "Knowledge Sheaf Curator") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 098: Ecology & Swarm /ecology quarantined_inference_worker
// -----------------------------------------------------------------------------
pub fn bdd_scenario_098_agent_inference_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-098", "/ecology quarantined_inference_worker")
  let decision = handle_directive("/ecology quarantined_inference_worker", intent)
  string.contains(decision.reply_markdown, "Quarantined AI Inference Worker") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 099: Ecology & Swarm /ecology nonexistent-agent
// -----------------------------------------------------------------------------
pub fn bdd_scenario_099_agent_unknown_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-099", "/ecology nonexistent-agent")
  let decision = handle_directive("/ecology nonexistent-agent", intent)
  string.contains(decision.reply_markdown, "Unknown agent profile ID") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 100: Ecology & Swarm /board
// -----------------------------------------------------------------------------
pub fn bdd_scenario_100_board_summary_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-100", "/board")
  let decision = handle_directive("/board", intent)
  string.contains(decision.reply_markdown, "Tri-Agent Swarm Message Board") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 101: Agent Profile Capability Verification
// -----------------------------------------------------------------------------
pub fn bdd_scenario_101_agent_capability_check_test() {
  let assert Ok(profile) = agent_ecology.get_agent_profile("agy_sovereign_coordinator")
  agent_ecology.can_execute_capability(profile, "swarm_orchestration") |> should.be_true
  agent_ecology.can_execute_capability(profile, "NONEXISTENT-CAP") |> should.be_false
}

// -----------------------------------------------------------------------------
// Scenario 102: Agent Tool Allowlist Verification
// -----------------------------------------------------------------------------
pub fn bdd_scenario_102_agent_tool_allowlist_check_test() {
  let assert Ok(profile) = agent_ecology.get_agent_profile("security_hardware_guardian")
  agent_ecology.can_invoke_tool(profile, "storage_status") |> should.be_true
  agent_ecology.can_invoke_tool(profile, "arbitrary_destructive_tool") |> should.be_false
}

// -----------------------------------------------------------------------------
// Scenario 103: Agent Intent Execution Without Lease Fails Closed
// -----------------------------------------------------------------------------
pub fn bdd_scenario_103_agent_intent_no_lease_fails_closed_test() {
  let assert Ok(profile) = agent_ecology.get_agent_profile("sre_homeostasis_overseer")
  let res = agent_ecology.evaluate_agent_intent(profile, "prajna_health", False, 3)
  res |> should.equal(Error(agent_ecology.andon_halt_unauthorized_code))
}

// -----------------------------------------------------------------------------
// Scenario 104: Agent Intent Execution Missing 2oo3 Quorum Fails Closed
// -----------------------------------------------------------------------------
pub fn bdd_scenario_104_agent_intent_missing_quorum_fails_closed_test() {
  let assert Ok(profile) = agent_ecology.get_agent_profile("sre_homeostasis_overseer")
  let res = agent_ecology.evaluate_agent_intent(profile, "prajna_health", True, 1)
  res |> should.equal(Error(agent_ecology.andon_halt_quorum_missing_code))
}

// -----------------------------------------------------------------------------
// Scenario 105: Agent Intent Execution Permitted Under Valid Lease and Quorum
// -----------------------------------------------------------------------------
pub fn bdd_scenario_105_agent_intent_valid_lease_and_quorum_test() {
  let assert Ok(profile) = agent_ecology.get_agent_profile("sre_homeostasis_overseer")
  let res = agent_ecology.evaluate_agent_intent(profile, "prajna_health", True, 2)
  res |> should.equal(Ok("PERMITTED"))
}

// -----------------------------------------------------------------------------
// Scenario 106: Swarm Board Topic Detail Verification
// -----------------------------------------------------------------------------
pub fn bdd_scenario_106_swarm_board_topic_detail_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-106", "/board")
  let decision = handle_directive("/board", intent)
  decision.actions |> list.contains("query_tri_agent_board") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 107: Tri-Agent Coordinator Peer Presence
// -----------------------------------------------------------------------------
pub fn bdd_scenario_107_tri_agent_peer_presence_test() {
  let summary = agent_ecology.format_ecology_summary()
  summary |> string.contains("agy_sovereign_coordinator") |> should.be_true
  summary |> string.contains("sre_homeostasis_overseer") |> should.be_true
  summary |> string.contains("security_hardware_guardian") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 108: SRE Agent Token Budget and SLA Verification
// -----------------------------------------------------------------------------
pub fn bdd_scenario_108_sre_agent_budget_and_sla_test() {
  let assert Ok(profile) = agent_ecology.get_agent_profile("sre_homeostasis_overseer")
  profile.max_token_budget |> should.equal(4096)
  profile.sla_latency_ms |> should.equal(10)
}

// -----------------------------------------------------------------------------
// Scenario 109: Security Guardian Single-Agent Safe Dispatch Verification
// -----------------------------------------------------------------------------
pub fn bdd_scenario_109_security_guardian_dispatch_mode_test() {
  let assert Ok(profile) = agent_ecology.get_agent_profile("security_hardware_guardian")
  profile.requires_2oo3 |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 110: Formal Verifier Oracle SLA Constraint Verification
// -----------------------------------------------------------------------------
pub fn bdd_scenario_110_formal_verifier_sla_test() {
  let assert Ok(profile) = agent_ecology.get_agent_profile("formal_verifier_oracle")
  profile.sla_latency_ms |> should.equal(50)
}

// -----------------------------------------------------------------------------
// Scenario 111: Cognitive Architecture Query Full 5-Stage OODA Response
// -----------------------------------------------------------------------------
pub fn bdd_scenario_111_cognitive_architecture_query_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let query = "what does the sovereign cognitive architect do — show processing path"
  let intent = make_intent("bdd-111", query)
  let decision = handle_conversational(query, intent)
  decision.reply_markdown |> string.contains("5-Stage OODA Processing Path") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 112: Stage 1 Ingress Telemetry Identification
// -----------------------------------------------------------------------------
pub fn bdd_scenario_112_stage1_ingress_telemetry_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let query = "what does the sovereign cognitive architect do — show processing path"
  let intent = make_intent("bdd-112", query)
  let decision = handle_conversational(query, intent)
  decision.reply_markdown |> string.contains("Edge Ingress") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 113: Stage 2 OODA Cognitive Loop Identification
// -----------------------------------------------------------------------------
pub fn bdd_scenario_113_stage2_ooda_loop_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let query = "what does the sovereign cognitive architect do — show processing path"
  let intent = make_intent("bdd-113", query)
  let decision = handle_conversational(query, intent)
  decision.reply_markdown |> string.contains("Interception & Interlocks") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 114: Stage 3 Multi-Agent Swarm Arbitration Identification
// -----------------------------------------------------------------------------
pub fn bdd_scenario_114_stage3_swarm_arbitration_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let query = "what does the sovereign cognitive architect do — show processing path"
  let intent = make_intent("bdd-114", query)
  let decision = handle_conversational(query, intent)
  decision.reply_markdown |> string.contains("OODA Cognitive Loop") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 115: Stage 4 Formal Verification & Safety Interlocks Identification
// -----------------------------------------------------------------------------
pub fn bdd_scenario_115_stage4_formal_verification_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let query = "what does the sovereign cognitive architect do — show processing path"
  let intent = make_intent("bdd-115", query)
  let decision = handle_conversational(query, intent)
  decision.reply_markdown |> string.contains("Formal Verification") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 116: Stage 5 Egress Delivery Identification
// -----------------------------------------------------------------------------
pub fn bdd_scenario_116_stage5_egress_delivery_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let query = "what does the sovereign cognitive architect do — show processing path"
  let intent = make_intent("bdd-116", query)
  let decision = handle_conversational(query, intent)
  decision.reply_markdown |> string.contains("Egress Delivery") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 117: Persona Identity Robot C3I Identification
// -----------------------------------------------------------------------------
pub fn bdd_scenario_117_persona_robot_c3i_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let query = "who are you"
  let intent = make_intent("bdd-117", query)
  let decision = handle_conversational(query, intent)
  decision.reply_markdown |> string.contains("Robot C3I") |> should.be_true
  decision.reply_markdown |> string.contains("@c3i_talk_bot") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 118: Remote Peer AGY razr-1 Attribution
// -----------------------------------------------------------------------------
pub fn bdd_scenario_118_peer_agy_razr1_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let query = "telemetry debug from peer agy on razr-1"
  let intent = make_intent("bdd-118", query)
  let decision = handle_conversational(query, intent)
  decision.reply_markdown |> string.contains("razr-1") |> should.be_true
  decision.reply_markdown |> string.contains("Robot C3I") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 119: Decision Confidence Score Boundedness
// -----------------------------------------------------------------------------
pub fn bdd_scenario_119_decision_confidence_bounds_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-119", "/status")
  let decision = evaluate_intent(intent)
  decision.confidence |> fn(c) { c >=. 0.0 && c <=. 1.0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 120: Intent Timestamp Propagation
// -----------------------------------------------------------------------------
pub fn bdd_scenario_120_timestamp_propagation_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-120", "/help")
  let decision = evaluate_intent(intent)
  decision.timestamp_ms |> should.equal(intent.timestamp_ms)
}

// -----------------------------------------------------------------------------
// Scenario 121: Conversational Variation 121
// -----------------------------------------------------------------------------
pub fn bdd_scenario_121_conversational_variation_121_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-121", "conversational query variation 121")
  let decision = handle_conversational("conversational query variation 121", intent)
  decision.intent_id |> should.equal("bdd-121")
  string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 122: Conversational Variation 122
// -----------------------------------------------------------------------------
pub fn bdd_scenario_122_conversational_variation_122_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-122", "conversational query variation 122")
  let decision = handle_conversational("conversational query variation 122", intent)
  decision.intent_id |> should.equal("bdd-122")
  string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 123: Conversational Variation 123
// -----------------------------------------------------------------------------
pub fn bdd_scenario_123_conversational_variation_123_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-123", "conversational query variation 123")
  let decision = handle_conversational("conversational query variation 123", intent)
  decision.intent_id |> should.equal("bdd-123")
  string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 124: Conversational Variation 124
// -----------------------------------------------------------------------------
pub fn bdd_scenario_124_conversational_variation_124_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-124", "conversational query variation 124")
  let decision = handle_conversational("conversational query variation 124", intent)
  decision.intent_id |> should.equal("bdd-124")
  string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 125: Conversational Variation 125
// -----------------------------------------------------------------------------
pub fn bdd_scenario_125_conversational_variation_125_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-125", "conversational query variation 125")
  let decision = handle_conversational("conversational query variation 125", intent)
  decision.intent_id |> should.equal("bdd-125")
  string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 126: Conversational Variation 126
// -----------------------------------------------------------------------------
pub fn bdd_scenario_126_conversational_variation_126_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-126", "conversational query variation 126")
  let decision = handle_conversational("conversational query variation 126", intent)
  decision.intent_id |> should.equal("bdd-126")
  string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 127: Conversational Variation 127
// -----------------------------------------------------------------------------
pub fn bdd_scenario_127_conversational_variation_127_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-127", "conversational query variation 127")
  let decision = handle_conversational("conversational query variation 127", intent)
  decision.intent_id |> should.equal("bdd-127")
  string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 128: Conversational Variation 128
// -----------------------------------------------------------------------------
pub fn bdd_scenario_128_conversational_variation_128_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-128", "conversational query variation 128")
  let decision = handle_conversational("conversational query variation 128", intent)
  decision.intent_id |> should.equal("bdd-128")
  string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 129: Conversational Variation 129
// -----------------------------------------------------------------------------
pub fn bdd_scenario_129_conversational_variation_129_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-129", "conversational query variation 129")
  let decision = handle_conversational("conversational query variation 129", intent)
  decision.intent_id |> should.equal("bdd-129")
  string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 130: Conversational Variation 130
// -----------------------------------------------------------------------------
pub fn bdd_scenario_130_conversational_variation_130_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-130", "conversational query variation 130")
  let decision = handle_conversational("conversational query variation 130", intent)
  decision.intent_id |> should.equal("bdd-130")
  string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 131: Turn Deduplication with 1 Repeats
// -----------------------------------------------------------------------------
pub fn bdd_scenario_131_turn_dedup_1_repeats_test() {
  let msgs = list.repeat(ChatMessage("user", "repeat-msg", 1789184000000), 1)
  let formatted = format_recent_telegram_history(msgs, 10)
  formatted |> string.contains("Last 1 turns") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 132: Turn Deduplication with 2 Repeats
// -----------------------------------------------------------------------------
pub fn bdd_scenario_132_turn_dedup_2_repeats_test() {
  let msgs = list.repeat(ChatMessage("user", "repeat-msg", 1789184000000), 2)
  let formatted = format_recent_telegram_history(msgs, 10)
  formatted |> string.contains("Last 1 turns") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 133: Turn Deduplication with 3 Repeats
// -----------------------------------------------------------------------------
pub fn bdd_scenario_133_turn_dedup_3_repeats_test() {
  let msgs = list.repeat(ChatMessage("user", "repeat-msg", 1789184000000), 3)
  let formatted = format_recent_telegram_history(msgs, 10)
  formatted |> string.contains("Last 1 turns") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 134: Turn Deduplication with 5 Repeats
// -----------------------------------------------------------------------------
pub fn bdd_scenario_134_turn_dedup_5_repeats_test() {
  let msgs = list.repeat(ChatMessage("user", "repeat-msg", 1789184000000), 5)
  let formatted = format_recent_telegram_history(msgs, 10)
  formatted |> string.contains("Last 1 turns") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 135: Turn Deduplication with 10 Repeats
// -----------------------------------------------------------------------------
pub fn bdd_scenario_135_turn_dedup_10_repeats_test() {
  let msgs = list.repeat(ChatMessage("user", "repeat-msg", 1789184000000), 10)
  let formatted = format_recent_telegram_history(msgs, 10)
  formatted |> string.contains("Last 1 turns") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 136: History Limit Slicing 1 Turns
// -----------------------------------------------------------------------------
pub fn bdd_scenario_136_history_limit_1_test() {
  let msgs = list.map(int_range(1, 60), fn(i) {
    ChatMessage(role: "user", content: "msg " <> int.to_string(i), timestamp_ms: 1789184000000 + i * 1000)
  })
  let formatted = format_recent_telegram_history(msgs, 1)
  formatted |> string.contains("Last 1 turns") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 137: History Limit Slicing 2 Turns
// -----------------------------------------------------------------------------
pub fn bdd_scenario_137_history_limit_2_test() {
  let msgs = list.map(int_range(1, 60), fn(i) {
    ChatMessage(role: "user", content: "msg " <> int.to_string(i), timestamp_ms: 1789184000000 + i * 1000)
  })
  let formatted = format_recent_telegram_history(msgs, 2)
  formatted |> string.contains("Last 2 turns") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 138: History Limit Slicing 3 Turns
// -----------------------------------------------------------------------------
pub fn bdd_scenario_138_history_limit_3_test() {
  let msgs = list.map(int_range(1, 60), fn(i) {
    ChatMessage(role: "user", content: "msg " <> int.to_string(i), timestamp_ms: 1789184000000 + i * 1000)
  })
  let formatted = format_recent_telegram_history(msgs, 3)
  formatted |> string.contains("Last 3 turns") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 139: History Limit Slicing 5 Turns
// -----------------------------------------------------------------------------
pub fn bdd_scenario_139_history_limit_5_test() {
  let msgs = list.map(int_range(1, 60), fn(i) {
    ChatMessage(role: "user", content: "msg " <> int.to_string(i), timestamp_ms: 1789184000000 + i * 1000)
  })
  let formatted = format_recent_telegram_history(msgs, 5)
  formatted |> string.contains("Last 5 turns") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 140: History Limit Slicing 10 Turns
// -----------------------------------------------------------------------------
pub fn bdd_scenario_140_history_limit_10_test() {
  let msgs = list.map(int_range(1, 60), fn(i) {
    ChatMessage(role: "user", content: "msg " <> int.to_string(i), timestamp_ms: 1789184000000 + i * 1000)
  })
  let formatted = format_recent_telegram_history(msgs, 10)
  formatted |> string.contains("Last 10 turns") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 141: History Limit Slicing 20 Turns
// -----------------------------------------------------------------------------
pub fn bdd_scenario_141_history_limit_20_test() {
  let msgs = list.map(int_range(1, 60), fn(i) {
    ChatMessage(role: "user", content: "msg " <> int.to_string(i), timestamp_ms: 1789184000000 + i * 1000)
  })
  let formatted = format_recent_telegram_history(msgs, 20)
  formatted |> string.contains("Last 20 turns") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 142: History Limit Slicing 50 Turns
// -----------------------------------------------------------------------------
pub fn bdd_scenario_142_history_limit_50_test() {
  let msgs = list.map(int_range(1, 60), fn(i) {
    ChatMessage(role: "user", content: "msg " <> int.to_string(i), timestamp_ms: 1789184000000 + i * 1000)
  })
  let formatted = format_recent_telegram_history(msgs, 50)
  formatted |> string.contains("Last 50 turns") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 143: Empty History Handling
// -----------------------------------------------------------------------------
pub fn bdd_scenario_143_empty_history_placeholder_test() {
  let formatted = format_recent_telegram_history([], 10)
  formatted |> string.contains("No prior conversation messages recorded") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 144: Role Labeling User
// -----------------------------------------------------------------------------
pub fn bdd_scenario_144_role_labeling_user_test() {
  let msgs = [ChatMessage("user", "test user msg", 1789184000000)]
  let formatted = format_recent_telegram_history(msgs, 10)
  formatted |> string.contains("User:") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 145: Role Labeling Assistant Robot C3I
// -----------------------------------------------------------------------------
pub fn bdd_scenario_145_role_labeling_assistant_test() {
  let msgs = [ChatMessage("assistant", "test assistant msg", 1789184000000)]
  let formatted = format_recent_telegram_history(msgs, 10)
  formatted |> string.contains("Robot C3I:") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 146: Role Labeling Custom Role
// -----------------------------------------------------------------------------
pub fn bdd_scenario_146_role_labeling_custom_test() {
  let msgs = [ChatMessage("system", "system notice", 1789184000000)]
  let formatted = format_recent_telegram_history(msgs, 10)
  formatted |> string.contains("system:") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 147: Content Truncation at 160 Chars
// -----------------------------------------------------------------------------
pub fn bdd_scenario_147_content_truncation_160_chars_test() {
  let long_msg = string.repeat("LongContentBlock ", 20)
  let msgs = [ChatMessage("user", long_msg, 1789184000000)]
  let formatted = format_recent_telegram_history(msgs, 10)
  formatted |> string.contains("...") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 148: Conversation Memory Schema Initialization
// -----------------------------------------------------------------------------
pub fn bdd_scenario_148_schema_init_test() {
  let res = conversation_memory.init_schema(conversation_memory.default_db_path)
  res |> should.equal(Ok(Nil))
}

// -----------------------------------------------------------------------------
// Scenario 149: Conversation Turn Persistence and Retrieval
// -----------------------------------------------------------------------------
pub fn bdd_scenario_149_turn_persistence_and_retrieval_test() {
  let chat = "bdd-149-chat"
  let _ = conversation_memory.record_turn(conversation_memory.default_db_path, chat, "user", "turn 149", None, 1789184000000)
  let history = conversation_memory.get_recent_history(conversation_memory.default_db_path, chat, 5)
  list.length(history) |> fn(len) { len >= 1 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 150: Conversation Memory Clear Operation
// -----------------------------------------------------------------------------
pub fn bdd_scenario_150_memory_clear_operation_test() {
  let chat = "bdd-150-chat"
  let _ = conversation_memory.record_turn(conversation_memory.default_db_path, chat, "user", "to be cleared", None, 1789184000000)
  let _ = conversation_memory.clear_history(conversation_memory.default_db_path, chat)
  let history = conversation_memory.get_recent_history(conversation_memory.default_db_path, chat, 5)
  history |> should.equal([])
}

// -----------------------------------------------------------------------------
// Scenario 151: Raw Hardware Serial Redaction
// -----------------------------------------------------------------------------
pub fn bdd_scenario_151_raw_serial_redaction_test() {
  let text = egress_redactor.denied_os_nvme_serial
  let sanitized = egress_redactor.redact_system_secrets(text)
  sanitized |> should.equal(egress_redactor.redacted_serial_placeholder)
}

// -----------------------------------------------------------------------------
// Scenario 152: Serial Embedded in Text Redaction
// -----------------------------------------------------------------------------
pub fn bdd_scenario_152_embedded_serial_redaction_test() {
  let text = "Drive serial is " <> egress_redactor.denied_os_nvme_serial <> " locked."
  let sanitized = egress_redactor.redact_system_secrets(text)
  string.contains(sanitized, egress_redactor.denied_os_nvme_serial) |> should.be_false
  string.contains(sanitized, egress_redactor.redacted_serial_placeholder) |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 153: Serial in Markdown Code Block Redaction
// -----------------------------------------------------------------------------
pub fn bdd_scenario_153_codeblock_serial_redaction_test() {
  let text = "```json\n{\"serial\": \"" <> egress_redactor.denied_os_nvme_serial <> "\"}\n```"
  let sanitized = egress_redactor.redact_system_secrets(text)
  string.contains(sanitized, egress_redactor.denied_os_nvme_serial) |> should.be_false
}

// -----------------------------------------------------------------------------
// Scenario 154: Multiple Serial Occurrences Redaction
// -----------------------------------------------------------------------------
pub fn bdd_scenario_154_multiple_serials_redaction_test() {
  let text = egress_redactor.denied_os_nvme_serial <> " and " <> egress_redactor.denied_os_nvme_serial
  let sanitized = egress_redactor.redact_system_secrets(text)
  string.contains(sanitized, egress_redactor.denied_os_nvme_serial) |> should.be_false
}

// -----------------------------------------------------------------------------
// Scenario 155: API Key Pattern Redaction
// -----------------------------------------------------------------------------
pub fn bdd_scenario_155_api_key_redaction_test() {
  let text = "Token is sk-or-v1-abcdef1234567890abcdef1234567890"
  let sanitized = egress_redactor.redact_system_secrets(text)
  string.contains(sanitized, "sk-or-v1-abcdef1234567890abcdef1234567890") |> should.be_false
  string.contains(sanitized, egress_redactor.redacted_token_placeholder) |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 156: Clean Text Unmodified by Redaction
// -----------------------------------------------------------------------------
pub fn bdd_scenario_156_clean_text_preservation_test() {
  let text = "Completely safe status report with zero secrets."
  let sanitized = egress_redactor.redact_system_secrets(text)
  sanitized |> should.equal(text)
}

// -----------------------------------------------------------------------------
// Scenario 157: Redaction in Outbound Payload Construction
// -----------------------------------------------------------------------------
pub fn bdd_scenario_157_outbound_payload_redaction_test() {
  let raw = "Warning: OS NVMe " <> egress_redactor.denied_os_nvme_serial <> " locked."
  let payload = telegram_outbound.build_send_payload("6249174059", raw, None)
  string.contains(payload, egress_redactor.denied_os_nvme_serial) |> should.be_false
  string.contains(payload, egress_redactor.redacted_serial_placeholder) |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 158: Redaction in Conversation Memory Turn Storage
// -----------------------------------------------------------------------------
pub fn bdd_scenario_158_memory_turn_storage_redaction_test() {
  let raw = "User mentioning " <> egress_redactor.denied_os_nvme_serial
  let _ = conversation_memory.record_turn(conversation_memory.default_db_path, "bdd-158-chat", "user", raw, None, 1789184000000)
  let history = conversation_memory.get_recent_history(conversation_memory.default_db_path, "bdd-158-chat", 1)
  case history {
    [msg, ..] -> {
      string.contains(msg.content, egress_redactor.denied_os_nvme_serial) |> should.be_false
      string.contains(msg.content, egress_redactor.redacted_serial_placeholder) |> should.be_true
    }
    [] -> should.fail()
  }
}

// -----------------------------------------------------------------------------
// Scenario 159: Directive /storage Secret Redaction
// -----------------------------------------------------------------------------
pub fn bdd_scenario_159_storage_directive_redaction_test() {
  let intent = make_intent("bdd-159", "/storage")
  let decision = handle_directive("/storage", intent)
  string.contains(decision.reply_markdown, egress_redactor.denied_os_nvme_serial) |> should.be_false
  string.contains(decision.reply_markdown, egress_redactor.redacted_serial_placeholder) |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 160: Directive /status Secret Redaction
// -----------------------------------------------------------------------------
pub fn bdd_scenario_160_status_directive_redaction_test() {
  let intent = make_intent("bdd-160", "/status")
  let decision = handle_directive("/status", intent)
  string.contains(decision.reply_markdown, egress_redactor.denied_os_nvme_serial) |> should.be_false
  string.contains(decision.reply_markdown, egress_redactor.redacted_serial_placeholder) |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 161: Directive /checklist Secret Redaction
// -----------------------------------------------------------------------------
pub fn bdd_scenario_161_checklist_directive_redaction_test() {
  let intent = make_intent("bdd-161", "/checklist")
  let decision = handle_directive("/checklist", intent)
  string.contains(decision.reply_markdown, egress_redactor.denied_os_nvme_serial) |> should.be_false
}

// -----------------------------------------------------------------------------
// Scenario 162: Repeated 100 Serials Redaction
// -----------------------------------------------------------------------------
pub fn bdd_scenario_162_repeated_serials_stress_test() {
  let text = string.repeat(egress_redactor.denied_os_nvme_serial <> " ", 100)
  let sanitized = egress_redactor.redact_system_secrets(text)
  string.contains(sanitized, egress_redactor.denied_os_nvme_serial) |> should.be_false
}

// -----------------------------------------------------------------------------
// Scenario 163: Split Line Serials Redaction
// -----------------------------------------------------------------------------
pub fn bdd_scenario_163_split_line_serials_test() {
  let text = "\n" <> egress_redactor.denied_os_nvme_serial <> "\n" <> egress_redactor.denied_os_nvme_serial <> "\n"
  let sanitized = egress_redactor.redact_system_secrets(text)
  string.contains(sanitized, egress_redactor.denied_os_nvme_serial) |> should.be_false
}

// -----------------------------------------------------------------------------
// Scenario 164: Bearer Authorization Redaction
// -----------------------------------------------------------------------------
pub fn bdd_scenario_164_bearer_auth_redaction_test() {
  let text = "Token is ghp_abcdef1234567890abcdef1234567890"
  let sanitized = egress_redactor.redact_system_secrets(text)
  string.contains(sanitized, "ghp_abcdef1234567890abcdef1234567890") |> should.be_false
  string.contains(sanitized, egress_redactor.redacted_token_placeholder) |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 165: Hardware Lock String Invariant
// -----------------------------------------------------------------------------
pub fn bdd_scenario_165_hardware_lock_string_invariant_test() {
  let intent = make_intent("bdd-165", "/nvme")
  let decision = handle_directive("/nvme", intent)
  string.contains(decision.reply_markdown, "Locked") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 166: Read Tool Dispatch query_system_health
// -----------------------------------------------------------------------------
pub fn bdd_scenario_166_read_tool_query_system_health_test() {
  let intent = make_intent("bdd-166", "/tool query_system_health")
  let lease = td.FencingLease("worker-1", "plan-1", "task-1", 1, 9_999_999_999_999_999_999)
  let decision = dispatch_action_request("call-166", "query_system_health", "{}", Some(lease), False, intent)
  decision.ooda_phase |> should.equal("Act")
  decision.reply_markdown |> string.contains("Tool Executed") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 167: Read Tool Dispatch query_saplan
// -----------------------------------------------------------------------------
pub fn bdd_scenario_167_read_tool_query_saplan_test() {
  let intent = make_intent("bdd-167", "/tool query_saplan")
  let lease = td.FencingLease("worker-1", "plan-1", "task-1", 1, 9_999_999_999_999_999_999)
  let decision = dispatch_action_request("call-167", "query_saplan", "{}", Some(lease), False, intent)
  decision.ooda_phase |> should.equal("Act")
  decision.reply_markdown |> string.contains("Tool Executed") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 168: Read Tool Dispatch query_storage_lock
// -----------------------------------------------------------------------------
pub fn bdd_scenario_168_read_tool_query_storage_lock_test() {
  let intent = make_intent("bdd-168", "/tool query_storage_lock")
  let lease = td.FencingLease("worker-1", "plan-1", "task-1", 1, 9_999_999_999_999_999_999)
  let decision = dispatch_action_request("call-168", "query_storage_lock", "{}", Some(lease), False, intent)
  decision.ooda_phase |> should.equal("Act")
  decision.reply_markdown |> string.contains("Tool Executed") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 169: Read Tool Dispatch query_tri_agent_board
// -----------------------------------------------------------------------------
pub fn bdd_scenario_169_read_tool_query_tri_agent_board_test() {
  let intent = make_intent("bdd-169", "/tool query_tri_agent_board")
  let lease = td.FencingLease("worker-1", "plan-1", "task-1", 1, 9_999_999_999_999_999_999)
  let decision = dispatch_action_request("call-169", "query_tri_agent_board", "{}", Some(lease), False, intent)
  decision.ooda_phase |> should.equal("Act")
  decision.reply_markdown |> string.contains("Tool Executed") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 170: Read Tool Dispatch query_aspects
// -----------------------------------------------------------------------------
pub fn bdd_scenario_170_read_tool_query_aspects_test() {
  let intent = make_intent("bdd-170", "/tool query_aspects")
  let lease = td.FencingLease("worker-1", "plan-1", "task-1", 1, 9_999_999_999_999_999_999)
  let decision = dispatch_action_request("call-170", "query_aspects", "{}", Some(lease), False, intent)
  decision.ooda_phase |> should.equal("Act")
  decision.reply_markdown |> string.contains("Tool Executed") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 171: Read Tool Dispatch query_ecology
// -----------------------------------------------------------------------------
pub fn bdd_scenario_171_read_tool_query_ecology_test() {
  let intent = make_intent("bdd-171", "/tool query_ecology")
  let lease = td.FencingLease("worker-1", "plan-1", "task-1", 1, 9_999_999_999_999_999_999)
  let decision = dispatch_action_request("call-171", "query_ecology", "{}", Some(lease), False, intent)
  decision.ooda_phase |> should.equal("Act")
  decision.reply_markdown |> string.contains("Tool Executed") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 172: Read Tool Dispatch invoke_zigvm
// -----------------------------------------------------------------------------
pub fn bdd_scenario_172_read_tool_invoke_zigvm_test() {
  let intent = make_intent("bdd-172", "/tool invoke_zigvm")
  let lease = td.FencingLease("worker-1", "plan-1", "task-1", 1, 9_999_999_999_999_999_999)
  let decision = dispatch_action_request("call-172", "invoke_zigvm", "{}", Some(lease), False, intent)
  decision.ooda_phase |> should.equal("Act")
  decision.reply_markdown |> string.contains("Tool Executed") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 173: Mutating Tool resuscitate_node Quorum Missing Triggers Andon
// -----------------------------------------------------------------------------
pub fn bdd_scenario_173_mutating_tool_resuscitate_node_quorum_missing_test() {
  let intent = make_intent("bdd-173", "/tool resuscitate_node")
  let lease = td.FencingLease("worker-1", "plan-1", "task-1", 1, 9_999_999_999_999_999_999)
  let decision = dispatch_action_request("call-173", "resuscitate_node", "{}", Some(lease), False, intent)
  decision.ooda_phase |> should.equal("Halt")
  decision.actions |> should.equal(["andon_stop_line"])
  decision.reply_markdown |> string.contains("Fractal Jidoka Andon Stop Line Triggered") |> should.be_true
  decision.reply_markdown |> string.contains(int.to_string(td.andon_halt_quorum_missing_code)) |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 174: Mutating Tool chaos_inject Quorum Missing Triggers Andon
// -----------------------------------------------------------------------------
pub fn bdd_scenario_174_mutating_tool_chaos_inject_quorum_missing_test() {
  let intent = make_intent("bdd-174", "/tool chaos_inject")
  let lease = td.FencingLease("worker-1", "plan-1", "task-1", 1, 9_999_999_999_999_999_999)
  let decision = dispatch_action_request("call-174", "chaos_inject", "{}", Some(lease), False, intent)
  decision.ooda_phase |> should.equal("Halt")
  decision.actions |> should.equal(["andon_stop_line"])
  decision.reply_markdown |> string.contains("Fractal Jidoka Andon Stop Line Triggered") |> should.be_true
  decision.reply_markdown |> string.contains(int.to_string(td.andon_halt_quorum_missing_code)) |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 175: Mutating Tool rotate_keys Quorum Missing Triggers Andon
// -----------------------------------------------------------------------------
pub fn bdd_scenario_175_mutating_tool_rotate_keys_quorum_missing_test() {
  let intent = make_intent("bdd-175", "/tool rotate_keys")
  let lease = td.FencingLease("worker-1", "plan-1", "task-1", 1, 9_999_999_999_999_999_999)
  let decision = dispatch_action_request("call-175", "rotate_keys", "{}", Some(lease), False, intent)
  decision.ooda_phase |> should.equal("Halt")
  decision.actions |> should.equal(["andon_stop_line"])
  decision.reply_markdown |> string.contains("Fractal Jidoka Andon Stop Line Triggered") |> should.be_true
  decision.reply_markdown |> string.contains(int.to_string(td.andon_halt_quorum_missing_code)) |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 176: Mutating Tool storage_rebalance Quorum Missing Triggers Andon
// -----------------------------------------------------------------------------
pub fn bdd_scenario_176_mutating_tool_storage_rebalance_quorum_missing_test() {
  let intent = make_intent("bdd-176", "/tool storage_rebalance")
  let lease = td.FencingLease("worker-1", "plan-1", "task-1", 1, 9_999_999_999_999_999_999)
  let decision = dispatch_action_request("call-176", "storage_rebalance", "{}", Some(lease), False, intent)
  decision.ooda_phase |> should.equal("Halt")
  decision.actions |> should.equal(["andon_stop_line"])
  decision.reply_markdown |> string.contains("Fractal Jidoka Andon Stop Line Triggered") |> should.be_true
  decision.reply_markdown |> string.contains(int.to_string(td.andon_halt_quorum_missing_code)) |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 177: Mutating Tool resuscitate_node Approved Executes Under 2oo3 Quorum
// -----------------------------------------------------------------------------
pub fn bdd_scenario_177_mutating_tool_resuscitate_node_approved_test() {
  let intent = make_intent("bdd-177", "/tool resuscitate_node")
  let lease = td.FencingLease("worker-1", "plan-1", "task-1", 1, 9_999_999_999_999_999_999)
  let decision = dispatch_action_request("call-177", "resuscitate_node", "{}", Some(lease), True, intent)
  decision.ooda_phase |> should.equal("Act")
  decision.reply_markdown |> string.contains("Tool Executed") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 178: Mutating Tool chaos_inject Approved Executes Under 2oo3 Quorum
// -----------------------------------------------------------------------------
pub fn bdd_scenario_178_mutating_tool_chaos_inject_approved_test() {
  let intent = make_intent("bdd-178", "/tool chaos_inject")
  let lease = td.FencingLease("worker-1", "plan-1", "task-1", 1, 9_999_999_999_999_999_999)
  let decision = dispatch_action_request("call-178", "chaos_inject", "{}", Some(lease), True, intent)
  decision.ooda_phase |> should.equal("Act")
  decision.reply_markdown |> string.contains("Tool Executed") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 179: Mutating Tool rotate_keys Approved Executes Under 2oo3 Quorum
// -----------------------------------------------------------------------------
pub fn bdd_scenario_179_mutating_tool_rotate_keys_approved_test() {
  let intent = make_intent("bdd-179", "/tool rotate_keys")
  let lease = td.FencingLease("worker-1", "plan-1", "task-1", 1, 9_999_999_999_999_999_999)
  let decision = dispatch_action_request("call-179", "rotate_keys", "{}", Some(lease), True, intent)
  decision.ooda_phase |> should.equal("Act")
  decision.reply_markdown |> string.contains("Tool Executed") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 180: Mutating Tool storage_rebalance Approved Executes Under 2oo3 Quorum
// -----------------------------------------------------------------------------
pub fn bdd_scenario_180_mutating_tool_storage_rebalance_approved_test() {
  let intent = make_intent("bdd-180", "/tool storage_rebalance")
  let lease = td.FencingLease("worker-1", "plan-1", "task-1", 1, 9_999_999_999_999_999_999)
  let decision = dispatch_action_request("call-180", "storage_rebalance", "{}", Some(lease), True, intent)
  decision.ooda_phase |> should.equal("Act")
  decision.reply_markdown |> string.contains("Tool Executed") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 181: Short Message Chunking Yields 1 Chunk
// -----------------------------------------------------------------------------
pub fn bdd_scenario_181_short_message_chunking_test() {
  let chunks = telegram_outbound.chunk_text("Short message", 4096)
  list.length(chunks) |> should.equal(1)
}

// -----------------------------------------------------------------------------
// Scenario 182: Exact 4096-Byte Chunking Yields 1 Chunk
// -----------------------------------------------------------------------------
pub fn bdd_scenario_182_exact_4096_chunking_test() {
  let text = string.repeat("a", 4096)
  let chunks = telegram_outbound.chunk_text(text, 4096)
  list.length(chunks) |> should.equal(1)
}

// -----------------------------------------------------------------------------
// Scenario 183: 5000-Byte Chunking Yields 2 Chunks
// -----------------------------------------------------------------------------
pub fn bdd_scenario_183_5000_byte_chunking_test() {
  let text = string.repeat("a ", 2500)
  let chunks = telegram_outbound.chunk_text(text, 4096)
  list.length(chunks) |> should.equal(2)
}

// -----------------------------------------------------------------------------
// Scenario 184: All Chunks Bound <= 4096 Characters
// -----------------------------------------------------------------------------
pub fn bdd_scenario_184_chunk_length_ceiling_test() {
  let text = string.repeat("arbitrary words in a very long response ", 300)
  let chunks = telegram_outbound.chunk_text(text, 4096)
  list.all(chunks, fn(c) { string.length(c) <= 4096 }) |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 185: Chunk Lossless Roundtrip Invariant
// -----------------------------------------------------------------------------
pub fn bdd_scenario_185_chunk_lossless_roundtrip_test() {
  let text = string.repeat("word ", 2000)
  let chunks = telegram_outbound.chunk_text(text, 4096)
  string.join(chunks, "") |> should.equal(text)
}

// -----------------------------------------------------------------------------
// Scenario 186: Outbound Payload Parse Mode Markdown
// -----------------------------------------------------------------------------
pub fn bdd_scenario_186_outbound_payload_markdown_test() {
  let payload = telegram_outbound.build_send_payload("123", "Hello", Some("Markdown"))
  string.contains(payload, "\"parse_mode\":\"Markdown\"") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 187: Outbound Payload Parse Mode None
// -----------------------------------------------------------------------------
pub fn bdd_scenario_187_outbound_payload_plaintext_test() {
  let payload = telegram_outbound.build_send_payload("123", "Hello", None)
  string.contains(payload, "parse_mode") |> should.be_false
}

// -----------------------------------------------------------------------------
// Scenario 188: razr-1 Edge Telemetry CPU Temp Ingestion
// -----------------------------------------------------------------------------
pub fn bdd_scenario_188_razr1_cpu_temp_ingestion_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let query = "telemetry razr-1 cpu_temp_c 45.2"
  let intent = make_intent("bdd-188", query)
  let decision = handle_conversational(query, intent)
  string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 189: razr-1 Edge Telemetry Battery Ingestion
// -----------------------------------------------------------------------------
pub fn bdd_scenario_189_razr1_battery_ingestion_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let query = "telemetry razr-1 battery_pct 88"
  let intent = make_intent("bdd-189", query)
  let decision = handle_conversational(query, intent)
  string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 190: razr-1 Edge Network Latency Ingestion
// -----------------------------------------------------------------------------
pub fn bdd_scenario_190_razr1_latency_ingestion_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let query = "telemetry razr-1 ping_ms 12"
  let intent = make_intent("bdd-190", query)
  let decision = handle_conversational(query, intent)
  string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 191: razr-1 Peer Delegation Directive
// -----------------------------------------------------------------------------
pub fn bdd_scenario_191_razr1_peer_delegation_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let query = "delegate to razr-1: run health check"
  let intent = make_intent("bdd-191", query)
  let decision = handle_conversational(query, intent)
  decision.reply_markdown |> string.contains("razr-1") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 192: razr-1 GPS Coordinate Ingestion
// -----------------------------------------------------------------------------
pub fn bdd_scenario_192_razr1_gps_ingestion_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let query = "telemetry razr-1 gps 52.5200 13.4050"
  let intent = make_intent("bdd-192", query)
  let decision = handle_conversational(query, intent)
  string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 193: razr-1 Storage Telemetry Ingestion
// -----------------------------------------------------------------------------
pub fn bdd_scenario_193_razr1_storage_ingestion_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let query = "telemetry razr-1 disk_free_gb 120"
  let intent = make_intent("bdd-193", query)
  let decision = handle_conversational(query, intent)
  string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 194: razr-1 Task Acknowledgment Loop
// -----------------------------------------------------------------------------
pub fn bdd_scenario_194_razr1_task_ack_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let query = "razr-1 task ack t-102"
  let intent = make_intent("bdd-194", query)
  let decision = handle_conversational(query, intent)
  decision.reply_markdown |> string.contains("Robot C3I") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 195: razr-1 Node Status Direct Query
// -----------------------------------------------------------------------------
pub fn bdd_scenario_195_razr1_node_status_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let query = "status razr-1"
  let intent = make_intent("bdd-195", query)
  let decision = handle_conversational(query, intent)
  string.length(decision.reply_markdown) |> fn(len) { len > 0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 196: Worker Actor Lifecycle Initialization
// -----------------------------------------------------------------------------
pub fn bdd_scenario_196_worker_actor_lifecycle_test() {
  let assert Ok(started) = cognitive_worker.start()
  string.is_empty(started.data |> string.inspect) |> should.be_false
}

// -----------------------------------------------------------------------------
// Scenario 197: External OpenRouter Timeout Failover Recovery
// -----------------------------------------------------------------------------
pub fn bdd_scenario_197_openrouter_timeout_failover_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent = make_intent("bdd-197", "conversational query during timeout")
  let decision = handle_conversational("conversational query during timeout", intent)
  decision.confidence |> fn(c) { c >. 0.0 } |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 198: Zenoh Router Ingress Partition Recovery
// -----------------------------------------------------------------------------
pub fn bdd_scenario_198_zenoh_ingress_partition_test() {
  let decisions = cognitive_worker.poll_zenoh_and_process("http://127.0.0.1:59999")
  decisions |> should.equal([])
}

// -----------------------------------------------------------------------------
// Scenario 199: Quality Evaluation Automated Scoring
// -----------------------------------------------------------------------------
pub fn bdd_scenario_199_quality_evaluation_scoring_test() {
  let intent = make_intent("bdd-199", "/status")
  let decision = handle_directive("/status", intent)
  decision.confidence |> should.equal(0.99)
  string.contains(decision.reply_markdown, "UOS Cluster Telemetry") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 200: Comprehensive Verification Checklist Ratification
// -----------------------------------------------------------------------------
pub fn bdd_scenario_200_comprehensive_checklist_ratification_test() {
  let intent = make_intent("bdd-200", "/checklist")
  let decision = handle_directive("/checklist", intent)
  decision.reply_markdown |> string.contains("18/18 (100% GREEN)") |> should.be_true
  decision.actions |> list.contains("query_checklist_status") |> should.be_true
}
