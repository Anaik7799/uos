//// =============================================================================
//// [UOS-TEST] Zenoh Cognitive Worker & OODA Reasoning Test Suite
//// =============================================================================

import cepaf_gleam/harness/cognitive_worker.{
  CognitiveIntent, GetWorkerStatus, ProcessIntent, decode_intent, encode_decision,
  evaluate_intent, handle_message, init_worker,
}
import gleam/erlang/process
import gleam/list
import gleam/string
import gleeunit/should

pub fn decode_standard_intent_test() {
  let raw =
    "{\"intent_id\": \"cog-101\", \"source\": \"telegram\", \"user\": \"Avi\", \"chat_id\": \"142270921\", \"text\": \"cluster health report\", \"timestamp_ms\": 1788978900000}"

  let result = decode_intent(raw)
  result |> should.be_ok

  let assert Ok(intent) = result
  intent.intent_id |> should.equal("cog-101")
  intent.source |> should.equal("telegram")
  intent.user |> should.equal("Avi")
  intent.chat_id |> should.equal("142270921")
  intent.text |> should.equal("cluster health report")
  intent.timestamp_ms |> should.equal(1788978900000)
}

pub fn decode_edge_telegram_intent_test() {
  let raw =
    "{\"update_id\": 811568285, \"from_user\": \"Avi\", \"chat_id\": \"142270921\", \"text\": \"what tasks are in plan\", \"timestamp_ms\": 1788978900000}"

  let result = decode_intent(raw)
  result |> should.be_ok

  let assert Ok(intent) = result
  intent.intent_id |> should.equal("tg-811568285")
  intent.source |> should.equal("telegram")
  intent.user |> should.equal("Avi")
  intent.chat_id |> should.equal("142270921")
  intent.text |> should.equal("what tasks are in plan")
}

pub fn encode_decision_test() {
  let decision =
    cognitive_worker.CognitiveDecision(
      intent_id: "cog-102",
      ooda_phase: "Completed",
      reasoning: "Test reasoning",
      actions: ["action1", "action2"],
      reply_markdown: "Markdown reply",
      confidence: 0.98,
      timestamp_ms: 1788978900000,
    )

  let json_str = encode_decision(decision)
  json_str |> string.contains("\"intent_id\":\"cog-102\"") |> should.be_true
  json_str |> string.contains("\"ooda_phase\":\"Completed\"") |> should.be_true
  json_str |> string.contains("\"worker\":\"uos-gleam-cognitive-worker-1\"") |> should.be_true
}

pub fn evaluate_cluster_health_intent_test() {
  let intent =
    CognitiveIntent(
      intent_id: "cog-103",
      source: "telegram",
      user: "Avi",
      chat_id: "142270921",
      text: "analyze cluster load and health",
      timestamp_ms: 1788978900000,
    )

  let decision = evaluate_intent(intent)
  decision.intent_id |> should.equal("cog-103")
  decision.ooda_phase |> should.equal("Completed")
  decision.reply_markdown |> string.contains("Cluster Health") |> should.be_true
  decision.actions |> list.contains("check_beam_health") |> should.be_true
}

pub fn evaluate_saplan_intent_test() {
  let intent =
    CognitiveIntent(
      intent_id: "cog-104",
      source: "telegram",
      user: "Avi",
      chat_id: "142270921",
      text: "what is the current task in sa-plan",
      timestamp_ms: 1788978900000,
    )

  let decision = evaluate_intent(intent)
  decision.intent_id |> should.equal("cog-104")
  decision.reply_markdown |> string.contains("Sa-Plan") |> should.be_true
  decision.actions |> list.contains("query_sqlite_saplan") |> should.be_true
}

pub fn evaluate_formal_math_intent_test() {
  let intent =
    CognitiveIntent(
      intent_id: "cog-105",
      source: "telegram",
      user: "Avi",
      chat_id: "142270921",
      text: "explain lean 4 proof and mathematical gates",
      timestamp_ms: 1788978900000,
    )

  let decision = evaluate_intent(intent)
  decision.intent_id |> should.equal("cog-105")
  decision.reply_markdown |> string.contains("Traceability.lean") |> should.be_true
  decision.reply_markdown |> string.contains("Shannon Entropy Gate") |> should.be_true
}

pub fn evaluate_zigvm_intent_test() {
  let intent =
    CognitiveIntent(
      intent_id: "cog-106",
      source: "telegram",
      user: "Avi",
      chat_id: "142270921",
      text: "run deterministic zigvm calc",
      timestamp_ms: 1788978900000,
    )

  let decision = evaluate_intent(intent)
  decision.intent_id |> should.equal("cog-106")
  decision.reply_markdown |> string.contains("ZigVM") |> should.be_true
}

pub fn evaluate_general_intent_test() {
  let intent =
    CognitiveIntent(
      intent_id: "cog-107",
      source: "telegram",
      user: "Avi",
      chat_id: "142270921",
      text: "good morning system",
      timestamp_ms: 1788978900000,
    )

  let decision = evaluate_intent(intent)
  decision.intent_id |> should.equal("cog-107")
  decision.reply_markdown |> string.contains("AGY Sovereign Agent Synthesis") |> should.be_true
}

pub fn actor_message_handling_test() {
  let state = init_worker("test-worker-1")
  state.worker_id |> should.equal("test-worker-1")
  state.intents_processed |> should.equal(0)

  let intent =
    CognitiveIntent(
      intent_id: "cog-108",
      source: "telegram",
      user: "Avi",
      chat_id: "142270921",
      text: "status check",
      timestamp_ms: 1788978900000,
    )

  let sub = process.new_subject()
  let _ = handle_message(state, ProcessIntent(intent, sub))

  let assert Ok(res) = process.receive(sub, 500)
  res.intent_id |> should.equal("cog-108")
}

pub fn actor_get_status_test() {
  let state = init_worker("test-worker-2")
  let sub = process.new_subject()
  let _ = handle_message(state, GetWorkerStatus(sub))

  let assert Ok(status) = process.receive(sub, 500)
  status.worker_id |> should.equal("test-worker-2")
  status.intents_processed |> should.equal(0)
}

pub fn decode_zenoh_intents_array_test() {
  let raw =
    "[{\"key\":\"indrajaal/l5/cog/intent/req\",\"value\":{\"intent_id\":\"cog-999\",\"source\":\"telegram\",\"user\":\"Avi\",\"chat_id\":\"142270921\",\"text\":\"system health\",\"timestamp_ms\":1788978900000}}]"

  let intents = cognitive_worker.decode_zenoh_intents(raw)
  intents |> list.length |> should.equal(1)

  let assert [first] = intents
  first.intent_id |> should.equal("cog-999")
  first.user |> should.equal("Avi")
  first.text |> should.equal("system health")
}

pub fn evaluate_directive_help_test() {
  let intent =
    CognitiveIntent(
      intent_id: "cog-help-1",
      source: "telegram",
      user: "Avi",
      chat_id: "142270921",
      text: "/help",
      timestamp_ms: 1788978900000,
    )
  let decision = evaluate_intent(intent)
  decision.intent_id |> should.equal("cog-help-1")
  decision.reply_markdown |> string.contains("Available Operator Directives") |> should.be_true
  decision.actions |> list.contains("show_directive_reference") |> should.be_true
}

pub fn evaluate_directive_status_test() {
  let intent =
    CognitiveIntent(
      intent_id: "cog-status-1",
      source: "telegram",
      user: "Avi",
      chat_id: "142270921",
      text: "/status",
      timestamp_ms: 1788978900000,
    )
  let decision = evaluate_intent(intent)
  decision.intent_id |> should.equal("cog-status-1")
  decision.reply_markdown |> string.contains("UOS Cluster Telemetry") |> should.be_true
  decision.actions |> list.contains("query_zenoh") |> should.be_true
}

pub fn evaluate_directive_cockpit_test() {
  let intent =
    CognitiveIntent(
      intent_id: "cog-cockpit-1",
      source: "telegram",
      user: "Avi",
      chat_id: "142270921",
      text: "/cockpit",
      timestamp_ms: 1788978900000,
    )
  let decision = evaluate_intent(intent)
  decision.intent_id |> should.equal("cog-cockpit-1")
  decision.reply_markdown |> string.contains("nas-1.tail55d152.ts.net:4100") |> should.be_true
}

pub fn evaluate_identity_query_test() {
  let intent =
    CognitiveIntent(
      intent_id: "cog-id-1",
      source: "telegram",
      user: "Avi",
      chat_id: "142270921",
      text: "who are you?",
      timestamp_ms: 1788978900000,
    )
  let decision = evaluate_intent(intent)
  decision.intent_id |> should.equal("cog-id-1")
  decision.reply_markdown |> string.contains("UOS Sovereign Cybernetic Harness") |> should.be_true
  decision.actions |> list.contains("respond_identity") |> should.be_true
}

pub fn actor_tick_handling_test() {
  let state = init_worker("test-worker-3")
  let _next = handle_message(state, cognitive_worker.Tick)
  state.worker_id |> should.equal("test-worker-3")
}
