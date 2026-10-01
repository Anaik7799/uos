//// apps/cepaf_gleam/test/cognitive_doctor_truth_test.gleam
//// Truthful Doctor & EV-Cycle Diagnostic Regression Tests
//// Contract Reference: SC-PROVENANCE-001, SC-COG-001, SC-CHECKLIST-001

import cepaf_gleam/harness/cognitive_worker.{
  type CognitiveIntent, CognitiveIntent, execute_harness_tool, handle_directive,
  query_doctor_detail,
}
import cepaf_gleam/harness/doctor_projection
import cepaf_gleam/intent/denotational
import gleam/io
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
  // Positive assertions: Truthful EV ceiling and unadmitted range
  string.contains(reply, "EV-93") |> should.be_true
  string.contains(reply, "SC-PROVENANCE-001") |> should.be_true
  string.contains(reply, "EV-94..EV-109") |> should.be_true
  string.contains(reply, "NOT_ADMITTED") |> should.be_true
  string.contains(reply, "UNOBSERVED") |> should.be_true
  string.contains(reply, "Standalone Jujutsu Monorepo") |> should.be_true
  string.contains(reply, "0 Bevy, 0 Graphite") |> should.be_true

  // Negative assertions: Old false claims MUST NOT be present
  string.contains(reply, "EV-108") |> should.be_false
  string.contains(reply, "EV-109 (Ratified)") |> should.be_false
  string.contains(reply, "Ratified") |> should.be_false
  string.contains(reply, ">10,636") |> should.be_false
  string.contains(reply, "100% Clean") |> should.be_false
  string.contains(reply, "18/18 Checks PASS") |> should.be_false
  string.contains(reply, "Sovereign Consensus") |> should.be_false
}

pub fn doctor_directive_reply_markdown_test() {
  let intent = make_test_intent("doc-002", "/doctor")
  let decision = handle_directive("/doctor", intent)
  string.contains(decision.reply_markdown, "EV-93") |> should.be_true
  string.contains(decision.reply_markdown, "NOT_ADMITTED") |> should.be_true
  string.contains(decision.reply_markdown, "EV-108") |> should.be_false
  string.contains(decision.reply_markdown, "Ratified") |> should.be_false
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
  string.contains(json_str, "\"ev_cycles_verified\":93")
  |> should.be_true
  string.contains(json_str, "\"unadmitted_range\":\"EV-94..EV-109\"")
  |> should.be_true
  string.contains(json_str, "\"admission_status\":\"NOT_ADMITTED\"")
  |> should.be_true
  string.contains(json_str, "\"gate\":\"UNOBSERVED\"")
  |> should.be_true
  string.contains(json_str, "\"checks_passed\":\"UNOBSERVED\"")
  |> should.be_true
  string.contains(json_str, "\"zero_muda\":true")
  |> should.be_true
  string.contains(json_str, "\"observed_in_query\":false")
  |> should.be_true

  // Negative assertions
  string.contains(json_str, "\"doctor_status\":\"HEALTHY\"")
  |> should.be_false
  string.contains(json_str, "108")
  |> should.be_false
  string.contains(json_str, "\"gate\":\"PASS\"")
  |> should.be_false
  string.contains(json_str, "108/108")
  |> should.be_false
}

pub fn doctor_pure_projection_model_test() {
  let p = doctor_projection.project()
  p.admitted_ev_ceiling |> should.equal(denotational.admitted_ev_ceiling)
  p.admitted_ev_ceiling |> should.equal(93)
  p.unadmitted_range |> should.equal("EV-94..EV-109")
  p.doctor_status |> should.equal("UNOBSERVED_RUNTIME")
  p.observed_in_query |> should.be_false
}

pub fn main() {
  doctor_directive_metadata_test()
  ev_directive_metadata_test()
  doctor_markdown_truth_and_negative_test()
  doctor_directive_reply_markdown_test()
  query_doctor_harness_tool_json_test()
  doctor_pure_projection_model_test()
  io.println("PASS: ALL 6 COGNITIVE DOCTOR TRUTH AND NEGATIVE TESTS PASSED")
}
