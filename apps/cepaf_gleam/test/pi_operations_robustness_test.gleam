// =============================================================================
// [C3I-SIL6-MSTS] Pi Operations Robustness Test Suite
// =============================================================================
// STAMP: SC-PI-001..010, SC-PI-EVO-001..008, SC-ZMOF-001
// Layer: L6_ECOSYSTEM
//
// 48 tests across 6 categories:
//   §1  Session Lifecycle (10)
//   §2  AG-UI State Machine (10)
//   §3  Tool Federation Robustness (10)
//   §4  Provider & Inference (5)
//   §5  Zenoh Topics (5)
//   §6  Fractal Layer Coverage (8)
//
// SC-PI-001: Pi events → AG-UI events conversion verified end-to-end.
// SC-PI-002: Session lifecycle functions never panic; all edge cases handled.
// SC-PI-005: Federated tool registry returns 93 total (6+14+73).
// SC-ZMOF-001: All Zenoh topics start with "indrajaal/pi" prefix.
// =============================================================================

import cepaf_gleam/agui/events
import cepaf_gleam/bridge/pi_agent
import cepaf_gleam/bridge/pi_claude_code
import cepaf_gleam/bridge/pi_provider
import cepaf_gleam/bridge/pi_tools
import gleam/json
import gleam/list
import gleam/option.{None}
import gleam/string
import gleeunit/should

// =============================================================================
// §1 Session Lifecycle (10 tests)
// =============================================================================

/// start_session returns a valid PiSession with a matched RunStarted PiEvent.
pub fn session_lifecycle_start_returns_valid_pair_test() {
  let #(session, event) =
    pi_agent.start_session("sess-001", "c3i_cortex", "gemini-2.5-flash")

  session.session_id
  |> should.equal("sess-001")

  event.kind
  |> should.equal(pi_agent.PiAgentStart)
}

/// RunStarted event emitted by start_session MUST carry sequence number 0.
pub fn session_lifecycle_run_started_sequence_zero_test() {
  let #(_, event) =
    pi_agent.start_session("sess-seq0", "c3i_cortex", "gemini-2.5-flash")

  event.sequence
  |> should.equal(0)
}

/// RunStarted event session_id MUST match the session_id argument.
pub fn session_lifecycle_run_started_session_id_matches_test() {
  let target_id = "sess-id-match"
  let #(_, event) =
    pi_agent.start_session(target_id, "c3i_cortex", "gemini-2.5-flash")

  event.session_id
  |> should.equal(target_id)
}

/// complete_session sets ended_at to Some(timestamp).
pub fn session_lifecycle_complete_sets_ended_at_test() {
  let #(session, _) =
    pi_agent.start_session("sess-complete", "c3i_cortex", "gemma-3")

  let completed = pi_agent.complete_session(session)

  completed.ended_at
  |> should.not_equal(None)
}

/// append_jsonl preserves the data and separates lines with newline.
pub fn session_lifecycle_append_jsonl_preserves_data_test() {
  let #(session, _) =
    pi_agent.start_session("sess-jsonl", "c3i_cortex", "gemma-3")

  let s1 = pi_agent.append_jsonl(session, "{\"type\":\"start\"}")
  let s2 = pi_agent.append_jsonl(s1, "{\"type\":\"end\"}")

  s2.raw_jsonl
  |> string.contains("{\"type\":\"start\"}")
  |> should.be_true()

  s2.raw_jsonl
  |> string.contains("{\"type\":\"end\"}")
  |> should.be_true()
}

/// increment_turn increases the turn_count by exactly 1.
pub fn session_lifecycle_increment_turn_increases_counter_test() {
  let #(session, _) =
    pi_agent.start_session("sess-turn", "c3i_cortex", "gemma-3")

  let before = session.turn_count
  let after = pi_agent.increment_turn(session)

  after.turn_count
  |> should.equal(before + 1)
}

/// Session state transitions: PiIdle → PiProcessing → PiStreaming
/// represented as string labels via state_to_string.
pub fn session_lifecycle_state_transitions_test() {
  pi_agent.PiIdle
  |> pi_agent.state_to_string()
  |> should.equal("idle")

  pi_agent.PiProcessing(session_id: "s1", turn_index: 2)
  |> pi_agent.state_to_string()
  |> string.starts_with("processing")
  |> should.be_true()

  pi_agent.PiStreaming(session_id: "s1", message_id: "m1")
  |> pi_agent.state_to_string()
  |> string.starts_with("streaming")
  |> should.be_true()
}

/// PiError state is isolated: state string contains "error", session_id, code.
pub fn session_lifecycle_error_state_isolation_test() {
  let err_state = pi_agent.PiError("sess-err", "connection timeout", "E503")
  let label = pi_agent.state_to_string(err_state)

  label |> string.contains("error") |> should.be_true()
  label |> string.contains("sess-err") |> should.be_true()
  label |> string.contains("E503") |> should.be_true()
}

/// Two concurrent sessions do not share state (independent record values).
pub fn session_lifecycle_concurrent_sessions_independent_test() {
  let #(s1, _) = pi_agent.start_session("sess-a", "prov-1", "gemma-3")
  let #(s2, _) = pi_agent.start_session("sess-b", "prov-2", "gemma-4")

  s1.session_id |> should.not_equal(s2.session_id)
  s1.provider_id |> should.not_equal(s2.provider_id)

  // Mutating s1 does not affect s2
  let s1_incremented = pi_agent.increment_turn(s1)
  s1_incremented.turn_count |> should.equal(1)
  s2.turn_count |> should.equal(0)
}

/// Session with empty provider_id is structurally valid (no panic).
pub fn session_lifecycle_empty_provider_id_handled_test() {
  let #(session, event) = pi_agent.start_session("sess-empty-prov", "", "")

  session.provider_id |> should.equal("")
  event.session_id |> should.equal("sess-empty-prov")
  event.sequence |> should.equal(0)
}

// =============================================================================
// §2 AG-UI State Machine (10 tests)
// =============================================================================

/// All 12 PiEventKind values map to a valid EventType (exhaustive, no panic).
pub fn agui_sm_all_12_pi_event_kinds_map_test() {
  let kinds = [
    pi_agent.PiAgentStart,
    pi_agent.PiAgentEnd,
    pi_agent.PiTurnStart,
    pi_agent.PiTurnEnd,
    pi_agent.PiMessageStart,
    pi_agent.PiMessageUpdate,
    pi_agent.PiMessageEnd,
    pi_agent.PiToolExecutionStart,
    pi_agent.PiToolExecutionUpdate,
    pi_agent.PiToolExecutionEnd,
    pi_agent.PiAgentError,
    pi_agent.PiAgentMeta,
  ]

  // Every kind must yield a valid EventType without panic
  let mapped = list.map(kinds, pi_agent.pi_event_kind_to_agui)

  list.length(mapped)
  |> should.equal(12)
}

/// bridge_event for PiAgentStart produces Ok(AgUiEvent) with RunStarted.
pub fn agui_sm_agent_start_produces_run_started_test() {
  let pi_ev =
    pi_agent.PiEvent(
      session_id: "sess-bridge",
      kind: pi_agent.PiAgentStart,
      sequence: 0,
      timestamp: 1_700_000_000_000,
      payload: json.object([]),
    )

  let result = pi_agent.bridge_event(pi_ev)
  let agui_ev = result |> should.be_ok()
  agui_ev.event_type |> should.equal(events.RunStarted)
}

/// bridge_event for PiToolExecutionStart produces Ok with ToolCallStart.
pub fn agui_sm_tool_execution_start_produces_tool_call_start_test() {
  let pi_ev =
    pi_agent.PiEvent(
      session_id: "sess-tool",
      kind: pi_agent.PiToolExecutionStart,
      sequence: 5,
      timestamp: 1_700_000_001_000,
      payload: json.object([#("tool", json.string("plan_status"))]),
    )

  let agui_ev = pi_agent.bridge_event(pi_ev) |> should.be_ok()
  agui_ev.event_type |> should.equal(events.ToolCallStart)
}

/// bridge_event for PiAgentError returns Error (special-cased path).
pub fn agui_sm_agent_error_returns_error_result_test() {
  let pi_ev =
    pi_agent.PiEvent(
      session_id: "sess-err",
      kind: pi_agent.PiAgentError,
      sequence: 3,
      timestamp: 1_700_000_002_000,
      payload: json.object([#("reason", json.string("timeout"))]),
    )

  let err_msg = pi_agent.bridge_event(pi_ev) |> should.be_error()
  err_msg
  |> string.contains("pi_error")
  |> should.be_true()
}

/// bridge_event thread_id matches session_id for non-error events.
pub fn agui_sm_bridge_event_thread_id_matches_session_id_test() {
  let target_session = "sess-thread-check"
  let pi_ev =
    pi_agent.PiEvent(
      session_id: target_session,
      kind: pi_agent.PiTurnStart,
      sequence: 1,
      timestamp: 1_700_000_003_000,
      payload: json.object([]),
    )

  let agui_ev = pi_agent.bridge_event(pi_ev) |> should.be_ok()
  agui_ev.thread_id |> should.equal(target_session)
}

/// Event sequence from consecutive bridge calls produces the correct batch size.
pub fn agui_sm_event_sequence_preserved_test() {
  let make_event = fn(seq) {
    pi_agent.PiEvent(
      session_id: "sess-seq",
      kind: pi_agent.PiMessageStart,
      sequence: seq,
      timestamp: 1_700_000_000_000 + seq,
      payload: json.object([]),
    )
  }

  let evs = [make_event(0), make_event(1), make_event(2)]
  let #(ok_evs, errors) = pi_agent.bridge_events(evs)

  // All three should succeed (PiMessageStart → TextMessageStart)
  list.length(errors) |> should.equal(0)
  // bridge_events uses fold so results are reversed; length must be 3
  list.length(ok_evs) |> should.equal(3)
}

/// pi_claude_code bidirectional mapping: claude_to_pi then pi_to_claude returns original.
pub fn agui_sm_bidirectional_mapping_consistent_test() {
  let claude_tools = ["Read", "Write", "Edit", "Bash", "Grep", "Glob"]

  list.each(claude_tools, fn(ct) {
    let pi_name = pi_claude_code.claude_to_pi_tool(ct)
    let back = pi_claude_code.pi_to_claude_tool(pi_name)
    back |> should.equal(ct)
  })
}

/// mapped_pi_event_count returns at least 27 entries.
pub fn agui_sm_mapped_pi_event_count_gte_27_test() {
  { pi_claude_code.mapped_pi_event_count() > 26 }
  |> should.be_true()
}

/// bidirectional_count returns at least 15.
pub fn agui_sm_bidirectional_count_gte_15_test() {
  { pi_claude_code.bidirectional_count() > 14 }
  |> should.be_true()
}

/// agui_only_events includes "Heartbeat" as a C3I-specific event.
pub fn agui_sm_agui_only_events_includes_heartbeat_test() {
  pi_claude_code.agui_only_events()
  |> list.contains("Heartbeat")
  |> should.be_true()
}

// =============================================================================
// §3 Tool Federation Robustness (10 tests)
// =============================================================================

/// is_c3i_tool("plan_status") returns True.
pub fn tool_fed_plan_status_is_c3i_tool_test() {
  pi_agent.is_c3i_tool("plan_status")
  |> should.be_true()
}

/// is_c3i_tool("bash") returns False (Pi native tool, not C3I).
pub fn tool_fed_bash_is_not_c3i_tool_test() {
  pi_agent.is_c3i_tool("bash")
  |> should.be_false()
}

/// is_c3i_tool("system_health") returns True.
pub fn tool_fed_system_health_is_c3i_tool_test() {
  pi_agent.is_c3i_tool("system_health")
  |> should.be_true()
}

/// resolve_tool_source for a C3I tool returns C3iMcpTool variant.
pub fn tool_fed_c3i_tool_resolves_to_c3i_mcp_source_test() {
  case pi_agent.resolve_tool_source("plan_status") {
    pi_agent.C3iMcpTool(_) -> should.be_true(True)
    pi_agent.PiNativeTool -> should.fail()
  }
}

/// resolve_tool_source for Pi native tool "bash" returns PiNativeTool.
pub fn tool_fed_pi_tool_resolves_to_pi_native_source_test() {
  case pi_agent.resolve_tool_source("bash") {
    pi_agent.PiNativeTool -> should.be_true(True)
    pi_agent.C3iMcpTool(_) -> should.fail()
  }
}

/// pi_agent.federated_tool_count equals 93 (6 Claude + 14 Pi + 73 C3I).
pub fn tool_fed_federated_tool_count_equals_93_test() {
  pi_agent.federated_tool_count
  |> should.equal(93)
}

/// claude_to_pi_tool covers all 6 Claude Code built-in tools without "unknown".
pub fn tool_fed_claude_to_pi_tool_covers_6_tools_test() {
  let claude_tools = ["Read", "Write", "Edit", "Bash", "Grep", "Glob"]
  let mappings = list.map(claude_tools, pi_claude_code.claude_to_pi_tool)

  // None of the mappings should be "unknown"
  mappings
  |> list.filter(fn(m) { m == "unknown" })
  |> list.length()
  |> should.equal(0)
}

/// pi_to_claude_tool reverse mapping is consistent for known Pi tools.
pub fn tool_fed_pi_to_claude_tool_reverse_consistent_test() {
  let pi_tools_under_test = ["read", "write", "edit", "bash", "grep", "find"]
  let mappings = list.map(pi_tools_under_test, pi_claude_code.pi_to_claude_tool)

  // None should be "Unknown"
  mappings
  |> list.filter(fn(m) { m == "Unknown" })
  |> list.length()
  |> should.equal(0)
}

/// Tool count breakdown: claude(6) + pi(14) + c3i(73) = 93.
pub fn tool_fed_tool_count_breakdown_sums_to_93_test() {
  let total = pi_claude_code.total_tool_count()
  total |> should.equal(93)

  pi_agent.claude_tool_count |> should.equal(6)
  pi_agent.pi_native_tool_count |> should.equal(14)
  pi_agent.c3i_mcp_tool_count |> should.equal(73)
}

/// Unknown tool names are handled gracefully by resolve_tool_source — no panic.
pub fn tool_fed_unknown_tool_name_handled_gracefully_test() {
  // resolve_tool_source is total; any input must return a variant
  let source = pi_agent.resolve_tool_source("totally_unknown_tool_xyz")
  // It is valid for either variant to be returned; we only verify no crash
  case source {
    pi_agent.PiNativeTool -> should.be_true(True)
    pi_agent.C3iMcpTool(_) -> should.be_true(True)
  }
}

// =============================================================================
// §4 Provider & Inference (5 tests)
// =============================================================================

/// default_provider_config returns a valid config with provider_id "c3i_cortex".
pub fn provider_default_config_valid_test() {
  let config =
    pi_agent.default_provider_config("http://localhost:4100", "test-token")

  config.provider_id |> should.equal("c3i_cortex")
  { config.max_tokens > 0 } |> should.be_true()
  { config.timeout_ms > 0 } |> should.be_true()
}

/// All 6 inference tiers in pi_provider have non-empty string representations.
pub fn provider_all_6_inference_tiers_have_string_repr_test() {
  let tiers = pi_provider.all_tiers()

  list.length(tiers) |> should.equal(6)

  tiers
  |> list.map(pi_provider.tier_name)
  |> list.filter(fn(s) { s == "" })
  |> list.length()
  |> should.equal(0)
}

/// tier_to_string (pi_agent) never returns empty string for any tier.
pub fn provider_tier_to_string_never_empty_test() {
  let tiers = [
    pi_agent.GeminiDirect,
    pi_agent.OpenRouter,
    pi_agent.OllamaGemma4,
    pi_agent.OllamaGemma3,
    pi_agent.ReteUlRules,
    pi_agent.StaticAck,
  ]

  tiers
  |> list.map(pi_agent.tier_to_string)
  |> list.filter(fn(s) { s == "" })
  |> list.length()
  |> should.equal(0)
}

/// provider_config_to_json serializes to a JSON string containing provider_id.
pub fn provider_config_serializes_to_json_test() {
  let config =
    pi_agent.default_provider_config(
      "http://localhost:4100/api/v1/inference",
      "tok-secret",
    )
  let json_val = pi_agent.provider_config_to_json(config)

  json.to_string(json_val)
  |> string.contains("c3i_cortex")
  |> should.be_true()
}

/// CircuitBreakerState types are all constructible and distinct.
pub fn provider_circuit_breaker_states_constructible_test() {
  let closed = pi_provider.Closed
  let open_state = pi_provider.Open(opened_at: 1_700_000_000_000)
  let half_open = pi_provider.HalfOpen

  // Verify each state is a distinct constructor (structural equality)
  closed |> should.not_equal(half_open)
  half_open |> should.not_equal(open_state)
}

// =============================================================================
// §5 Zenoh Topics (5 tests)
// =============================================================================

/// All topic constants are prefixed with "indrajaal/pi".
pub fn zenoh_topics_all_prefixed_with_indrajaal_pi_test() {
  let topics = [
    pi_agent.pi_namespace,
    pi_agent.pi_events_topic,
    pi_agent.pi_tools_topic,
    pi_agent.pi_sessions_topic,
    pi_agent.pi_providers_topic,
    pi_agent.pi_registry_topic,
  ]

  topics
  |> list.filter(fn(t) { !string.starts_with(t, "indrajaal/pi") })
  |> list.length()
  |> should.equal(0)
}

/// build_event_topic includes the session_id in the resulting topic string.
pub fn zenoh_topics_event_topic_includes_session_id_test() {
  let topic = pi_agent.build_event_topic("my-session-42", "RunStarted")

  topic
  |> string.contains("my-session-42")
  |> should.be_true()
}

/// build_tool_topic includes the tool_name in the resulting topic string.
pub fn zenoh_topics_tool_topic_includes_tool_name_test() {
  let topic = pi_agent.build_tool_topic("plan_status", "call-001")

  topic
  |> string.contains("plan_status")
  |> should.be_true()
}

/// Topic constants all start with "indrajaal/pi" prefix (SC-ZMOF-001).
pub fn zenoh_topics_constants_start_with_indrajaal_pi_test() {
  pi_agent.pi_events_topic
  |> string.starts_with("indrajaal/pi")
  |> should.be_true()

  pi_agent.pi_tools_topic
  |> string.starts_with("indrajaal/pi")
  |> should.be_true()

  pi_agent.pi_sessions_topic
  |> string.starts_with("indrajaal/pi")
  |> should.be_true()
}

/// Event topic, tool topic, and session topic have no namespace collision.
pub fn zenoh_topics_no_collision_between_namespaces_test() {
  let ev_topic = pi_agent.build_event_topic("s1", "start")
  let tool_topic = pi_agent.build_tool_topic("plan_status", "c1")
  let sess_topic = pi_agent.build_session_topic("s1")

  ev_topic |> should.not_equal(tool_topic)
  ev_topic |> should.not_equal(sess_topic)
  tool_topic |> should.not_equal(sess_topic)
}

// =============================================================================
// §6 Fractal Layer Coverage (8 tests)
// =============================================================================

/// L0 Constitutional: GuardianRequired gate applies to L0 tools (SC-PI-002).
pub fn fractal_l0_guardian_gate_type_exists_test() {
  let l0_tools = pi_tools.tools_by_layer(0)
  { l0_tools != [] } |> should.be_true()

  let guardian_tools = pi_tools.tools_requiring_guardian()
  { guardian_tools != [] } |> should.be_true()
}

/// L1 Atomic/Debug: tools exist at layer 1 for OTel/compute (gleam_compute).
pub fn fractal_l1_otel_span_topic_defined_test() {
  pi_agent.pi_events_topic
  |> string.starts_with("indrajaal/pi")
  |> should.be_true()

  let l1_tools = pi_tools.tools_by_layer(1)
  { l1_tools != [] } |> should.be_true()
}

/// L2 Component: TypeBox schema bridge type ClaudeCodeTool is constructible.
pub fn fractal_l2_typebox_schema_types_test() {
  let tool =
    pi_claude_code.ClaudeCodeTool(
      name: "Read",
      description: "Read file",
      fractal_layer: 3,
    )

  tool.name |> should.equal("Read")
  tool.fractal_layer |> should.equal(3)
}

/// L3 Transaction: Session record round-trips through session_to_row correctly.
pub fn fractal_l3_session_persistence_types_test() {
  let #(session, _) = pi_agent.start_session("sess-l3", "c3i_cortex", "gemma-3")
  let row = pi_agent.session_to_row(session)

  row.session_id |> should.equal("sess-l3")
  row.provider_id |> should.equal("c3i_cortex")
  row.turn_count |> should.equal(0)
  row.persisted |> should.be_false()
}

/// L4 System: Pod management tools exist at fractal_layer 4 in the registry.
pub fn fractal_l4_pod_management_tools_exist_test() {
  let l4_tools = pi_tools.tools_by_layer(4)
  { l4_tools != [] } |> should.be_true()
}

/// L5 Cognitive: 6-tier OODA inference cascade in pi_provider with rete-ul-rules.
pub fn fractal_l5_ooda_steering_types_test() {
  let tiers = pi_provider.all_tiers()
  list.length(tiers) |> should.equal(6)

  tiers
  |> list.map(pi_provider.tier_name)
  |> list.contains("rete-ul-rules")
  |> should.be_true()
}

/// L6 Ecosystem: Primary bridge layer has 29 Pi and 32 AG-UI events mapped.
pub fn fractal_l6_event_bus_types_test() {
  let bridge = pi_claude_code.init()

  bridge.pi_events_mapped |> should.equal(29)
  bridge.agui_events_mapped |> should.equal(32)
  bridge.zenoh_publishing |> should.be_false()
}

/// L7 Federation: Bridge starts in Disconnected / NotStarted state with 93 tools.
pub fn fractal_l7_federation_gateway_types_test() {
  let bridge = pi_claude_code.init()
  let status = pi_claude_code.bridge_status(bridge)

  status.rpc_connected |> should.be_false()
  status.session_active |> should.be_false()
  status.total_tools |> should.equal(93)
}
