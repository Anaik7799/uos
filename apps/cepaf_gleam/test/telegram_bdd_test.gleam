//// =============================================================================
//// [UOS-BDD] Telegram Cognitive Interface BDD Test Suite (SPEC-TELEGRAM-BDD-001)
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>test/telegram_bdd_test</module>
////     <authority>UOS-CANONICAL-AGENT-POLICY</authority>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////     <topology>BDD Specification for Robot C3I Telegram Interface</topology>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-TELEGRAM-001, SC-COG-001, SC-DRIVE-001, SC-MUDA-001</stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================

import cepaf_gleam/harness/cognitive_worker.{
  CognitiveIntent, evaluate_intent, format_recent_telegram_history,
  handle_directive,
}
import cepaf_gleam/harness/conversation_memory.{ChatMessage}
import cepaf_gleam/harness/egress_redactor
import cepaf_gleam/harness/telegram_outbound
import envoy
import gleam/list
import gleam/option.{None}
import gleam/string
import gleeunit/should

// -----------------------------------------------------------------------------
// Scenario 1: Sovereign Cognitive Architecture & Processing Path Inquiry
// -----------------------------------------------------------------------------
pub fn bdd_scenario_1_cognitive_architecture_query_test() {
  // GIVEN: An operator inquiring about the Sovereign Cognitive Architecture and its processing path
  envoy.set("UOS_TEST_MODE", "1")
  let intent =
    CognitiveIntent(
      intent_id: "bdd-sc1-intent",
      source: "telegram",
      user: "Avi",
      chat_id: "6249174059",
      text: "what does the sovereign cognitive architect do — show processing path",
      timestamp_ms: 1789184000000,
    )

  // WHEN: The cognitive worker evaluates the intent
  let decision = evaluate_intent(intent)

  // THEN: It responds as Robot C3I and details the full 5-stage OODA processing path
  decision.reply_markdown |> string.contains("Robot C3I") |> should.be_true
  decision.reply_markdown
  |> string.contains("5-Stage OODA Processing Path")
  |> should.be_true
  decision.reply_markdown |> string.contains("Edge Ingress") |> should.be_true
  decision.reply_markdown |> string.contains("OODA Cognitive Loop") |> should.be_true
  decision.reply_markdown |> string.contains("Formal Verification") |> should.be_true
  decision.reply_markdown |> string.contains("Egress Delivery") |> should.be_true
  decision.actions
  |> list.contains("explain_cognitive_architecture")
  |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 2: Recent Telegram Message History Request
// -----------------------------------------------------------------------------
pub fn bdd_scenario_2_telegram_message_history_query_test() {
  // GIVEN: Prior turns exist in conversation memory
  let test_db = "var/telegram/test_bdd_history.sqlite3"
  let _ = conversation_memory.init_schema(test_db)
  let _ =
    conversation_memory.record_turn(
      test_db,
      "bdd-chat-1",
      "user",
      "Hello Robot C3I",
      None,
      1789184001000,
    )
  let _ =
    conversation_memory.record_turn(
      test_db,
      "bdd-chat-1",
      "assistant",
      "Greetings Operator Avi",
      None,
      1789184002000,
    )

  // WHEN: The operator asks to show last 10 telegram messages
  let raw_history = conversation_memory.get_recent_history(test_db, "bdd-chat-1", 10)
  let formatted = format_recent_telegram_history(raw_history, 10)

  // THEN: It returns the formatted stream of user and bot turns, not the agent swarm board
  formatted |> string.contains("Recent Telegram Conversation Stream") |> should.be_true
  formatted |> string.contains("User:") |> should.be_true
  formatted |> string.contains("Hello Robot C3I") |> should.be_true
  formatted |> string.contains("Robot C3I:") |> should.be_true
  formatted |> string.contains("Greetings Operator Avi") |> should.be_true
  formatted |> string.contains("Tri-Agent Swarm Message Board") |> should.be_false
}

// -----------------------------------------------------------------------------
// Scenario 3: Persona Identity & Coordination with AGY @ razr-1
// -----------------------------------------------------------------------------
pub fn bdd_scenario_3_identity_and_peer_coordination_test() {
  // GIVEN: An operator asking for the bot's identity
  envoy.set("UOS_TEST_MODE", "1")
  let intent =
    CognitiveIntent(
      intent_id: "bdd-sc3-intent",
      source: "telegram",
      user: "Avi",
      chat_id: "6249174059",
      text: "who are you?",
      timestamp_ms: 1789184003000,
    )

  // WHEN: The cognitive worker evaluates identity
  let decision = evaluate_intent(intent)

  // THEN: It identifies itself as Robot C3I and specifies AGY as the remote coordinator
  decision.reply_markdown |> string.contains("Robot C3I") |> should.be_true
  decision.reply_markdown |> string.contains("@c3i_talk_bot") |> should.be_true
  decision.reply_markdown |> string.contains("AGY (Google DeepMind Antigravity)") |> should.be_true
  decision.reply_markdown |> string.contains("Pure Gleam/OTP 29") |> should.be_true
  decision.actions |> list.contains("respond_identity") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 4: Hardware NVMe Safety & Secret Redaction (SC-DRIVE-001)
// -----------------------------------------------------------------------------
pub fn bdd_scenario_4_hardware_nvme_redaction_guard_test() {
  // GIVEN: A user query or injected text that mentions the forbidden root OS NVMe serial
  let dangerous_text = "diagnose disk with serial 25503L801736 on cluster"

  // WHEN: The text passes through egress redaction
  let sanitized = egress_redactor.redact_system_secrets(dangerous_text)

  // THEN: The hardware serial is replaced with the redacted placeholder
  sanitized |> string.contains("25503L801736") |> should.be_false
  sanitized |> string.contains("[REDACTED_SYSTEM_OS_SERIAL]") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 5: Single Recording of Turns (Elimination of Turn Duplication)
// -----------------------------------------------------------------------------
pub fn bdd_scenario_5_turn_deduplication_persistence_test() {
  // GIVEN: A test conversation database with duplicate consecutive turns
  let msgs = [
    ChatMessage("user", "ping", 1789184010000),
    ChatMessage("user", "ping", 1789184010000),
    ChatMessage("assistant", "pong", 1789184011000),
    ChatMessage("assistant", "pong", 1789184011000),
  ]

  // WHEN: Sliced through format_recent_telegram_history
  let formatted = format_recent_telegram_history(msgs, 10)

  // THEN: Consecutive duplicates are pruned, leaving exactly 2 distinct turns
  formatted |> string.contains("Last 2 turns") |> should.be_true
  formatted |> string.contains("1. 👤 *User:* ping") |> should.be_true
  formatted |> string.contains("2. 🤖 *Robot C3I:* pong") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 6: Directives /messages and /history Support
// -----------------------------------------------------------------------------
pub fn bdd_scenario_6_messages_directive_execution_test() {
  // GIVEN: The operator sends a canonical directive /messages 5
  let intent =
    CognitiveIntent(
      intent_id: "bdd-sc6-dir",
      source: "telegram",
      user: "Avi",
      chat_id: "bdd-chat-dir",
      text: "/messages 5",
      timestamp_ms: 1789184020000,
    )

  // WHEN: The directive is handled
  let decision = handle_directive("/messages 5", intent)

  // THEN: It returns the formatted stream and tracks action query_telegram_history
  decision.ooda_phase |> should.equal("Completed")
  decision.actions |> list.contains("query_telegram_history") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 7: Outbound Chunking under 4096-byte Telegram API Limit
// -----------------------------------------------------------------------------
pub fn bdd_scenario_7_outbound_chunking_limit_test() {
  // GIVEN: A large cognitive response of 10,000 characters
  let large_response = string.repeat("UOS Sovereign Cockpit Telemetry Line\n", 280)
  string.length(large_response) |> fn(n) { n > 4096 } |> should.be_true

  // WHEN: It is sliced into Telegram chunks
  let chunks = telegram_outbound.chunk_text(large_response, 4096)

  // THEN: Every chunk is <= 4096 characters and the complete text is preserved
  list.length(chunks) |> fn(n) { n >= 2 } |> should.be_true
  list.all(chunks, fn(chunk) { string.length(chunk) <= 4096 }) |> should.be_true
  string.join(chunks, "") |> should.equal(large_response)
}

// -----------------------------------------------------------------------------
// Scenario 8: Directive /status Cluster Telemetry Integrity
// -----------------------------------------------------------------------------
pub fn bdd_scenario_8_status_directive_integrity_test() {
  // GIVEN: The operator explicitly requests cluster telemetry via /status
  let intent =
    CognitiveIntent(
      intent_id: "bdd-sc8-status",
      source: "telegram",
      user: "Avi",
      chat_id: "bdd-chat-status",
      text: "/status",
      timestamp_ms: 1789184030000,
    )

  // WHEN: The directive is handled
  let decision = handle_directive("/status", intent)

  // THEN: It outputs cluster telemetry with OTP 29 authority, zero muda, and locked storage
  decision.reply_markdown |> string.contains("UOS Cluster Telemetry") |> should.be_true
  decision.reply_markdown |> string.contains("Gleam/OTP 29 Root Supervisor") |> should.be_true
  decision.reply_markdown |> string.contains("Zero-Muda Purity") |> should.be_true
  decision.reply_markdown |> string.contains("100%") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 9: Multi-Turn Memory Clear Directive (/memory clear)
// -----------------------------------------------------------------------------
pub fn bdd_scenario_9_memory_clear_directive_test() {
  // GIVEN: An operator requesting to clear conversation memory
  let intent =
    CognitiveIntent(
      intent_id: "bdd-sc9-clear",
      source: "telegram",
      user: "Avi",
      chat_id: "bdd-chat-clear",
      text: "/memory clear",
      timestamp_ms: 1789184040000,
    )

  // WHEN: The directive is handled
  let decision = handle_directive("/memory clear", intent)

  // THEN: Memory reset confirmation is returned
  decision.reply_markdown |> string.contains("Conversation Memory Reset") |> should.be_true
  decision.actions |> list.contains("clear_conversation_memory") |> should.be_true
}

// -----------------------------------------------------------------------------
// Scenario 10: Edge Telemetry Ingestion from razr-1
// -----------------------------------------------------------------------------
pub fn bdd_scenario_10_razr1_telemetry_ingestion_test() {
  // GIVEN: Inbound telemetry payload from AGY on razr-1
  envoy.set("UOS_TEST_MODE", "1")
  let telemetry_payload = "{\"node\":\"razr-1\",\"cpu_temp_c\":42.5,\"battery_pct\":98}"
  let intent =
    CognitiveIntent(
      intent_id: "bdd-sc10-razr1",
      source: "telegram",
      user: "Avi",
      chat_id: "6249174059",
      text: telemetry_payload,
      timestamp_ms: 1789184050000,
    )

  // WHEN: Handled by the cognitive worker
  let decision = evaluate_intent(intent)

  // THEN: Robot C3I ingests telemetry payload and confirms edge verification
  decision.reply_markdown |> string.contains("Robot C3I: Telemetry Ingest & Edge Verification") |> should.be_true
  decision.reply_markdown |> string.contains("AGY @ razr-1") |> should.be_true
  decision.actions |> list.contains("ingest_razr1_telemetry") |> should.be_true
}
