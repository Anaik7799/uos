//// apps/cepaf_gleam/test/cognitive_doctor_truth_test.gleam
//// Truthful Doctor, EV-Cycle Diagnostic & Fenced Dispatch Negative Tests
//// Contract Reference: SC-PROVENANCE-001, SC-COG-001, SC-CHECKLIST-001, SC-JIDOKA-001

import cepaf_gleam/harness/cognitive_worker.{
  type CognitiveIntent, CognitiveIntent, dispatch_action_request,
  execute_harness_tool, handle_directive, query_doctor_detail,
}
import cepaf_gleam/harness/doctor_projection
import cepaf_gleam/harness/tool_fenced_dispatcher as td
import cepaf_gleam/intent/denotational
import gleam/io
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should

fn make_test_intent(id: String, text: String) -> CognitiveIntent {
  CognitiveIntent(
    intent_id: id,
    source: "test",
    user: "operator",
    chat_id: "0000",
    text: text,
    timestamp_ms: 1_790_800_000_000,
  )
}

// =============================================================================
// Doctor & EV Diagnostic Truth Tests (DOCTOR_FIX1 + Reviewer Containment)
// =============================================================================

pub fn doctor_directive_metadata_test() {
  let intent = make_test_intent("doc-001", "/doctor")
  let decision = handle_directive("/doctor", intent)
  decision.intent_id |> should.equal("doc-001")
  // Do not claim action/check execution
  decision.actions |> should.equal([])
  decision.confidence |> should.not_equal(1.0)
  decision.confidence |> should.equal(0.5)

  // Negative assertions on metadata
  string.contains(decision.reasoning, "diagnose_ev_status") |> should.be_false
  string.contains(decision.reasoning, "verify_zero_muda") |> should.be_false
}

pub fn ev_directive_metadata_test() {
  let intent = make_test_intent("ev-001", "/ev")
  let decision = handle_directive("/ev", intent)
  decision.intent_id |> should.equal("ev-001")
  // Do not claim action/check execution
  decision.actions |> should.equal([])
  decision.confidence |> should.not_equal(1.0)
  decision.confidence |> should.equal(0.5)

  // Negative assertions on metadata
  string.contains(decision.reasoning, "diagnose_ev_status") |> should.be_false
  string.contains(decision.reasoning, "verify_zero_muda") |> should.be_false
}

pub fn doctor_markdown_truth_and_negative_test() {
  let reply = query_doctor_detail()
  // Positive assertions: Truthful EV ceiling, unadmitted range, unobserved runtime state
  string.contains(reply, "EV-93") |> should.be_true
  string.contains(reply, "SC-PROVENANCE-001") |> should.be_true
  string.contains(reply, "EV-94..EV-109") |> should.be_true
  string.contains(reply, "NOT_ADMITTED") |> should.be_true
  string.contains(reply, "UNOBSERVED") |> should.be_true
  string.contains(reply, "Standalone Jujutsu Monorepo") |> should.be_true
  string.contains(reply, "• *Zero-Muda Compliance:* UNOBSERVED")
  |> should.be_true
  string.contains(reply, "• *Verified Cycles:* UNOBSERVED") |> should.be_true

  // Negative assertions: Old false claims and unobserved purity MUST NOT be present
  string.contains(reply, "EV-108") |> should.be_false
  string.contains(reply, "EV-109 (Ratified)") |> should.be_false
  string.contains(reply, "Ratified") |> should.be_false
  string.contains(reply, ">10,636") |> should.be_false
  string.contains(reply, "100% Clean") |> should.be_false
  string.contains(reply, "18/18 Checks PASS") |> should.be_false
  string.contains(reply, "Sovereign Consensus") |> should.be_false
  string.contains(reply, "0 Bevy, 0 Graphite") |> should.be_false
}

pub fn doctor_directive_reply_markdown_test() {
  let intent = make_test_intent("doc-002", "/doctor")
  let decision = handle_directive("/doctor", intent)
  string.contains(decision.reply_markdown, "EV-93") |> should.be_true
  string.contains(decision.reply_markdown, "NOT_ADMITTED") |> should.be_true
  string.contains(decision.reply_markdown, "EV-108") |> should.be_false
  string.contains(decision.reply_markdown, "Ratified") |> should.be_false
  string.contains(decision.reply_markdown, "0 Bevy") |> should.be_false
}

pub fn query_doctor_harness_tool_json_test() {
  let res = execute_harness_tool("query_doctor", "{}")
  res |> should.be_ok
  let assert Ok(json_str) = res

  // Positive assertions
  string.contains(json_str, "\"doctor_status\":\"UNOBSERVED_RUNTIME\"")
  |> should.be_true
  string.contains(json_str, "\"admitted_ev_ceiling\":93")
  |> should.be_true
  string.contains(json_str, "\"ev_cycles_verified\":null")
  |> should.be_true
  string.contains(json_str, "\"unadmitted_range\":\"EV-94..EV-109\"")
  |> should.be_true
  string.contains(json_str, "\"admission_status\":\"NOT_ADMITTED\"")
  |> should.be_true
  string.contains(json_str, "\"gate\":\"UNOBSERVED\"")
  |> should.be_true
  string.contains(json_str, "\"checks_passed\":\"UNOBSERVED\"")
  |> should.be_true
  string.contains(json_str, "\"zero_muda\":null")
  |> should.be_true
  string.contains(json_str, "\"observed_in_query\":false")
  |> should.be_true

  // Negative assertions (no fabricated health, verified counts, or purity)
  string.contains(json_str, "\"doctor_status\":\"HEALTHY\"")
  |> should.be_false
  string.contains(json_str, "108")
  |> should.be_false
  string.contains(json_str, "\"gate\":\"PASS\"")
  |> should.be_false
  string.contains(json_str, "108/108")
  |> should.be_false
  string.contains(json_str, "\"zero_muda\":true")
  |> should.be_false
  string.contains(json_str, "\"ev_cycles_verified\":93")
  |> should.be_false
}

pub fn doctor_pure_projection_model_test() {
  let p = doctor_projection.project()
  p.admitted_ev_ceiling |> should.equal(denotational.admitted_ev_ceiling)
  p.admitted_ev_ceiling |> should.equal(93)
  p.unadmitted_range |> should.equal("EV-94..EV-109")
  p.doctor_status |> should.equal("UNOBSERVED_RUNTIME")
  p.zero_muda_compliance
  |> string.contains("UNOBSERVED")
  |> should.be_true
  p.observed_in_query |> should.be_false
}

// =============================================================================
// Fenced Dispatch Negative Tests (DISPATCH_FIX1)
// =============================================================================

pub fn dispatch_missing_lease_fails_closed_test() {
  let intent = make_test_intent("disp-neg-1", "dispatch with no lease")
  let decision =
    dispatch_action_request(
      "call-neg-1",
      "query_system_health",
      "{}",
      None,
      False,
      intent,
    )
  decision.ooda_phase |> should.equal("Halt")
  decision.actions |> should.equal(["andon_stop_line"])
  string.contains(decision.reply_markdown, "Andon Stop Line") |> should.be_true
  string.contains(
    decision.reply_markdown,
    "Non-sa-plan task execution attempted",
  )
  |> should.be_true
  decision.ooda_phase |> should.not_equal("Act")
  string.contains(decision.reply_markdown, "Tool Executed") |> should.be_false
}

pub fn dispatch_synthetic_lease_fails_closed_test() {
  let intent =
    make_test_intent("disp-neg-2", "dispatch with caller synthetic lease")
  let synthetic_lease =
    td.FencingLease(
      worker: "worker-agy",
      plan_id: "telegram-gemma-wiring",
      task_id: "task-3",
      fencing_token: 1,
      lease_until_ns: 9_999_999_999_999_999_999,
    )
  let decision =
    dispatch_action_request(
      "call-neg-2",
      "query_system_health",
      "{}",
      Some(synthetic_lease),
      False,
      intent,
    )
  decision.ooda_phase |> should.equal("Halt")
  decision.actions |> should.equal(["andon_stop_line"])
  string.contains(decision.reply_markdown, "Unverified lease authority")
  |> should.be_true
  decision.ooda_phase |> should.not_equal("Act")
  string.contains(decision.reply_markdown, "Tool Executed") |> should.be_false
}

pub fn dispatch_expired_lease_fails_closed_test() {
  let intent = make_test_intent("disp-neg-3", "dispatch with expired lease")
  let expired_lease =
    td.FencingLease(
      worker: "worker-agy",
      plan_id: "plan-1",
      task_id: "task-1",
      fencing_token: 1,
      lease_until_ns: 1000,
    )
  let decision =
    dispatch_action_request(
      "call-neg-3",
      "query_system_health",
      "{}",
      Some(expired_lease),
      False,
      intent,
    )
  decision.ooda_phase |> should.equal("Halt")
  decision.actions |> should.equal(["andon_stop_line"])
  decision.ooda_phase |> should.not_equal("Act")
  string.contains(decision.reply_markdown, "Tool Executed") |> should.be_false
}

pub fn dispatch_quorum_true_unverified_lease_fails_closed_test() {
  let intent =
    make_test_intent(
      "disp-neg-4",
      "dispatch with quorum True but unverified lease",
    )
  let synthetic_lease =
    td.FencingLease(
      worker: "worker-agy",
      plan_id: "plan-1",
      task_id: "task-1",
      fencing_token: 1,
      lease_until_ns: 9_999_999_999_999_999_999,
    )
  let decision =
    dispatch_action_request(
      "call-neg-4",
      "resuscitate_node",
      "{}",
      Some(synthetic_lease),
      True,
      intent,
    )
  decision.ooda_phase |> should.equal("Halt")
  decision.actions |> should.equal(["andon_stop_line"])
  string.contains(decision.reply_markdown, "Unverified lease authority")
  |> should.be_true
  decision.ooda_phase |> should.not_equal("Act")
  string.contains(decision.reply_markdown, "Tool Executed") |> should.be_false
}

pub fn dispatch_quorum_true_missing_lease_fails_closed_test() {
  let intent =
    make_test_intent("disp-neg-5", "dispatch with quorum True but no lease")
  let decision =
    dispatch_action_request(
      "call-neg-5",
      "resuscitate_node",
      "{}",
      None,
      True,
      intent,
    )
  decision.ooda_phase |> should.equal("Halt")
  decision.actions |> should.equal(["andon_stop_line"])
  string.contains(
    decision.reply_markdown,
    "Non-sa-plan task execution attempted",
  )
  |> should.be_true
  decision.ooda_phase |> should.not_equal("Act")
  string.contains(decision.reply_markdown, "Tool Executed") |> should.be_false
}

pub fn tool_directive_no_synthetic_lease_fails_closed_test() {
  let intent = make_test_intent("disp-neg-6", "/tool query_system_health")
  let decision = handle_directive("/tool query_system_health", intent)
  decision.ooda_phase |> should.equal("Halt")
  decision.actions |> should.equal(["andon_stop_line"])
  string.contains(decision.reply_markdown, "Andon Stop Line") |> should.be_true
  decision.ooda_phase |> should.not_equal("Act")
  string.contains(decision.reply_markdown, "Tool Executed") |> should.be_false
}

pub fn action_directive_no_synthetic_lease_fails_closed_test() {
  let intent = make_test_intent("disp-neg-7", "/action resuscitate_node")
  let decision = handle_directive("/action resuscitate_node", intent)
  decision.ooda_phase |> should.equal("Halt")
  decision.actions |> should.equal(["andon_stop_line"])
  string.contains(decision.reply_markdown, "Andon Stop Line") |> should.be_true
  decision.ooda_phase |> should.not_equal("Act")
  string.contains(decision.reply_markdown, "Tool Executed") |> should.be_false
}

pub fn doctor_and_ev_pure_projection_unregressed_test() {
  let doc_intent = make_test_intent("doc-unreg-1", "/doctor")
  let doc_decision = handle_directive("/doctor", doc_intent)
  doc_decision.ooda_phase |> should.equal("Completed")
  doc_decision.actions |> should.equal([])
  doc_decision.confidence |> should.equal(0.5)
  string.contains(doc_decision.reply_markdown, "EV-93") |> should.be_true
  string.contains(doc_decision.reply_markdown, "NOT_ADMITTED") |> should.be_true
  string.contains(doc_decision.reply_markdown, "EV-108") |> should.be_false
  string.contains(doc_decision.reply_markdown, "Ratified") |> should.be_false

  let ev_intent = make_test_intent("ev-unreg-1", "/ev")
  let ev_decision = handle_directive("/ev", ev_intent)
  ev_decision.ooda_phase |> should.equal("Completed")
  ev_decision.actions |> should.equal([])
  ev_decision.confidence |> should.equal(0.5)
  string.contains(ev_decision.reply_markdown, "EV-93") |> should.be_true
  string.contains(ev_decision.reply_markdown, "NOT_ADMITTED") |> should.be_true
  string.contains(ev_decision.reply_markdown, "EV-108") |> should.be_false
  string.contains(ev_decision.reply_markdown, "Ratified") |> should.be_false
}

pub fn main() {
  // Doctor & EV diagnostic tests (6)
  doctor_directive_metadata_test()
  ev_directive_metadata_test()
  doctor_markdown_truth_and_negative_test()
  doctor_directive_reply_markdown_test()
  query_doctor_harness_tool_json_test()
  doctor_pure_projection_model_test()

  // Fenced dispatch negative containment tests (8)
  dispatch_missing_lease_fails_closed_test()
  dispatch_synthetic_lease_fails_closed_test()
  dispatch_expired_lease_fails_closed_test()
  dispatch_quorum_true_unverified_lease_fails_closed_test()
  dispatch_quorum_true_missing_lease_fails_closed_test()
  tool_directive_no_synthetic_lease_fails_closed_test()
  action_directive_no_synthetic_lease_fails_closed_test()
  doctor_and_ev_pure_projection_unregressed_test()

  io.println(
    "PASS: ALL 14 COGNITIVE DOCTOR TRUTH AND DISPATCH NEGATIVE TESTS PASSED",
  )
}
