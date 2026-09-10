//// =============================================================================
//// [UOS-TEST] Telegram Agentic Gemma 4 Full Wiring Test Suite (SPEC-TELEGRAM-GEMMA-001)
//// =============================================================================

import cepaf_gleam/harness/cognitive_worker.{
  CognitiveIntent, evaluate_intent, execute_harness_tool,
  extract_directives_from_response, handle_conversational_offline_gateway,
  query_tri_agent_board_detail, query_tri_agent_board_summary,
  query_tri_agent_peers, strip_directive_lines,
}
import cepaf_gleam/harness/conversation_memory
import cepaf_gleam/harness/egress_redactor
import cepaf_gleam/harness/telegram_creative
import envoy
import gleam/string
import gleeunit/should

pub fn telegram_board_directive_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let summary = query_tri_agent_board_summary()
  summary |> string.is_empty |> should.be_false

  let detail = query_tri_agent_board_detail()
  detail |> string.contains("Tri-Agent Swarm Message Board") |> should.be_true
  detail |> string.contains("var/coordination/tri-agent/events/") |> should.be_true
  detail |> string.contains("SC-TRI-AGENT-001") |> should.be_true

  let intent =
    CognitiveIntent(
      intent_id: "cog-board-1",
      source: "telegram",
      user: "Avi",
      chat_id: "test-chat-board",
      text: "/board",
      timestamp_ms: 1788978900000,
    )
  let decision = evaluate_intent(intent)
  decision.reply_markdown |> string.contains("Tri-Agent Swarm Message Board") |> should.be_true
  decision.ooda_phase |> should.equal("Completed")
}

pub fn telegram_peers_directive_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let peers = query_tri_agent_peers()
  peers |> string.contains("Tri-Agent Swarm Active Peer Registry") |> should.be_true
  peers |> string.contains("AGY (Google DeepMind Antigravity)") |> should.be_true
  peers |> string.contains("Claude (Anthropic)") |> should.be_true
  peers |> string.contains("Codex (OpenAI)") |> should.be_true

  let intent =
    CognitiveIntent(
      intent_id: "cog-peers-1",
      source: "telegram",
      user: "Avi",
      chat_id: "test-chat-peers",
      text: "/peers",
      timestamp_ms: 1788978900000,
    )
  let decision = evaluate_intent(intent)
  decision.reply_markdown |> string.contains("Tri-Agent Swarm Active Peer Registry") |> should.be_true
}

pub fn telegram_memory_lifecycle_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let chat_id = "test-chat-mem-lifecycle"
  let _ = conversation_memory.clear_history(conversation_memory.default_db_path, chat_id)

  let intent1 =
    CognitiveIntent(
      intent_id: "cog-mem-1",
      source: "telegram",
      user: "Avi",
      chat_id: chat_id,
      text: "hello uos system",
      timestamp_ms: 1788978900000,
    )
  let _ = evaluate_intent(intent1)

  let intent2 =
    CognitiveIntent(
      intent_id: "cog-mem-2",
      source: "telegram",
      user: "Avi",
      chat_id: chat_id,
      text: "/memory",
      timestamp_ms: 1788978901000,
    )
  let decision2 = evaluate_intent(intent2)
  decision2.reply_markdown |> string.contains("Conversation Memory State") |> should.be_true

  let intent3 =
    CognitiveIntent(
      intent_id: "cog-mem-3",
      source: "telegram",
      user: "Avi",
      chat_id: chat_id,
      text: "/memory clear",
      timestamp_ms: 1788978902000,
    )
  let decision3 = evaluate_intent(intent3)
  decision3.reply_markdown |> string.contains("Conversation Memory Reset") |> should.be_true
}

pub fn telegram_fenced_tool_read_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent =
    CognitiveIntent(
      intent_id: "cog-tool-read-1",
      source: "telegram",
      user: "Avi",
      chat_id: "test-chat-tool-read",
      text: "/tool query_system_health",
      timestamp_ms: 1788978900000,
    )
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Act")
  decision.reply_markdown |> string.contains("Tool Executed (`query_system_health`)") |> should.be_true
}

pub fn telegram_fenced_tool_mutating_quorum_halt_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent =
    CognitiveIntent(
      intent_id: "cog-tool-mut-1",
      source: "telegram",
      user: "Avi",
      chat_id: "test-chat-tool-mut",
      text: "/tool resuscitate_node",
      timestamp_ms: 1788978900000,
    )
  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Halt")
  decision.reply_markdown |> string.contains("Fractal Jidoka Andon Stop Line Triggered") |> should.be_true
  decision.reply_markdown |> string.contains("-32003") |> should.be_true
  decision.reply_markdown |> string.contains("Constitutional Quorum Violation") |> should.be_true
}

pub fn telegram_multimodal_rack_cv_redacted_test() {
  let output = telegram_creative.handle_rack_cv(["test-chassis-photo"])
  output |> string.contains("Computer Vision Server Rack Diagnostic") |> should.be_true
  output |> string.contains("Multimodal Vector (SC-MM-001)") |> should.be_true
  output |> string.contains("vision_rack_inspection") |> should.be_true
  output |> string.contains(egress_redactor.redacted_serial_placeholder) |> should.be_true
  output |> string.contains(egress_redactor.denied_os_nvme_serial) |> should.be_false
}

pub fn telegram_multimodal_acoustic_fft_test() {
  let output = telegram_creative.handle_acoustic(["test-audio-sample"])
  output |> string.contains("Acoustic Bearing Degradation Diagnostic") |> should.be_true
  output |> string.contains("Multimodal Vector (SC-MM-001)") |> should.be_true
  output |> string.contains("acoustic_vibration") |> should.be_true
  output |> string.contains("1240.0") |> should.be_true
}

pub fn telegram_directive_extractor_test() {
  let text =
    "I have analyzed the UOS system state.\n"
    <> "Here is the cluster status:\n"
    <> "DIRECTIVE: /status\n"
    <> "And here are the latest swarm messages:\n"
    <> "DIRECTIVE: /board\n"
    <> "DIRECTIVE: /tool query_immune_status\n"
    <> "DIRECTIVE: storage\n"
    <> "All systems are operating nominally."

  let dirs = extract_directives_from_response(text)
  dirs |> should.equal(["/status", "/board", "/tool query_immune_status", "/storage"])

  let stripped = strip_directive_lines(text)
  stripped |> string.contains("DIRECTIVE:") |> should.be_false
  stripped |> string.contains("I have analyzed the UOS system state.") |> should.be_true
  stripped |> string.contains("All systems are operating nominally.") |> should.be_true
}

pub fn telegram_autonomous_offline_gateway_generic_query_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let chat_id = "test-offline-generic-chat"
  let _ = conversation_memory.clear_history(conversation_memory.default_db_path, chat_id)

  let intent =
    CognitiveIntent(
      intent_id: "cog-offline-generic-1",
      source: "telegram",
      user: "Avi",
      chat_id: chat_id,
      text: "show me what is happening in the uos system",
      timestamp_ms: 1788978910000,
    )

  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  decision.reply_markdown |> string.contains("Deterministic Autonomous Directive Gateway") |> should.be_true
  decision.reply_markdown |> string.contains("UOS Cluster Telemetry") |> should.be_true
  decision.reply_markdown |> string.contains("Tri-Agent Swarm Message Board") |> should.be_true

  // Verify direct gateway invocation
  let direct_decision = handle_conversational_offline_gateway("status", intent)
  direct_decision.reply_markdown |> string.contains("UOS Cluster Telemetry") |> should.be_true

  // Verify memory persistence across turn
  let history = conversation_memory.get_recent_history(conversation_memory.default_db_path, chat_id, 5)
  history |> should.not_equal([])
}

pub fn telegram_autonomous_offline_gateway_storage_query_test() {
  envoy.set("UOS_TEST_MODE", "1")
  let intent =
    CognitiveIntent(
      intent_id: "cog-offline-storage-1",
      source: "telegram",
      user: "Avi",
      chat_id: "test-offline-storage-chat",
      text: "check storage nvme and disk pools",
      timestamp_ms: 1788978911000,
    )

  let decision = evaluate_intent(intent)
  decision.ooda_phase |> should.equal("Completed")
  decision.reply_markdown |> string.contains("Deterministic Autonomous Directive Gateway: /storage") |> should.be_true
  decision.reply_markdown |> string.contains(egress_redactor.redacted_serial_placeholder) |> should.be_true
  decision.reply_markdown |> string.contains(egress_redactor.denied_os_nvme_serial) |> should.be_false
}

pub fn telegram_execute_harness_tools_expanded_test() {
  // Immune and metabolic
  let immune = execute_harness_tool("query_immune_status", "{}")
  immune |> should.be_ok

  // FMEA report
  let fmea = execute_harness_tool("query_fmea_report", "{}")
  fmea |> should.be_ok

  // HA status
  let ha = execute_harness_tool("query_ha_status", "{}")
  ha |> should.be_ok

  // Modular MAX inference tier
  let inf = execute_harness_tool("query_inference_tier", "{}")
  inf |> should.be_ok
  case inf {
    Ok(json_str) -> json_str |> string.contains("Modular MAX") |> should.be_true
    Error(_) -> panic as "expected ok"
  }

  // Voice status
  let voice = execute_harness_tool("query_voice_status", "{}")
  voice |> should.be_ok

  // OODA loop phase
  let ooda = execute_harness_tool("query_ooda_phase", "{}")
  ooda |> should.be_ok

  // 13D trace coordinates
  let trace = execute_harness_tool("query_traces_recent", "{}")
  trace |> should.be_ok

  // Multimodal rack cv and acoustic fft
  let cv = execute_harness_tool("query_rack_cv", "{}")
  cv |> should.be_ok
  case cv {
    Ok(s) -> {
      s |> string.contains(egress_redactor.redacted_serial_placeholder) |> should.be_true
      s |> string.contains(egress_redactor.denied_os_nvme_serial) |> should.be_false
    }
    Error(_) -> panic as "expected ok"
  }

  let acoustic = execute_harness_tool("query_acoustic_fft", "{}")
  acoustic |> should.be_ok

  // Verification and checklist
  let chk = execute_harness_tool("query_checklist", "{}")
  chk |> should.be_ok
  case chk {
    Ok(s) -> s |> string.contains("18/18 GREEN") |> should.be_true
    Error(_) -> panic as "expected ok"
  }
}

