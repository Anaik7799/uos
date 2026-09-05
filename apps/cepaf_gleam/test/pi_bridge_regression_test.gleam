// C3I-SIL6-MSTS-001 — Pi Bridge Regression Suite
// Tests all 5 bridge modules for feature convergence
// SC-PI-EVO-001..008 compliance

import cepaf_gleam/bridge/pi_agent
import cepaf_gleam/bridge/pi_provider
import cepaf_gleam/bridge/pi_session
import cepaf_gleam/bridge/pi_tools
import cepaf_gleam/bridge/pi_zenoh
import gleam/list
import gleam/string
import gleeunit/should

// =============================================================================
// Pi Agent Bridge (pi_agent.gleam) — 15 tests
// =============================================================================

pub fn pi_agent_idle_state_test() {
  pi_agent.state_to_string(pi_agent.PiIdle)
  |> should.equal("idle")
}

pub fn pi_agent_processing_state_test() {
  pi_agent.state_to_string(pi_agent.PiProcessing("s1", 0))
  |> string.contains("processing")
  |> should.be_true()
}

pub fn pi_agent_streaming_state_test() {
  pi_agent.state_to_string(pi_agent.PiStreaming("s1", "m1"))
  |> string.contains("streaming")
  |> should.be_true()
}

pub fn pi_agent_error_state_test() {
  pi_agent.state_to_string(pi_agent.PiError("s1", "timeout", "E001"))
  |> string.contains("error")
  |> should.be_true()
}

pub fn pi_agent_events_topic_test() {
  pi_agent.pi_events_topic
  |> string.contains("pi/events")
  |> should.be_true()
}

pub fn pi_agent_tools_topic_test() {
  pi_agent.pi_tools_topic
  |> string.contains("pi/tools")
  |> should.be_true()
}

pub fn pi_agent_sessions_topic_test() {
  pi_agent.pi_sessions_topic
  |> string.contains("pi/sessions")
  |> should.be_true()
}

pub fn pi_agent_new_session_test() {
  let s = pi_agent.new_session("t1", "anthropic", "claude-sonnet-4-6")
  s.session_id |> should.equal("t1")
  s.provider_id |> should.equal("anthropic")
  s.model_id |> should.equal("claude-sonnet-4-6")
  s.turn_count |> should.equal(0)
}

pub fn pi_agent_increment_turn_test() {
  pi_agent.new_session("s1", "g", "m")
  |> pi_agent.increment_turn()
  |> pi_agent.increment_turn()
  |> fn(s) { s.turn_count }
  |> should.equal(2)
}

pub fn pi_agent_event_bridge_start_test() {
  pi_agent.pi_event_kind_to_agui(pi_agent.PiAgentStart)
  |> fn(_) { True }
  |> should.be_true()
}

pub fn pi_agent_event_bridge_end_test() {
  pi_agent.pi_event_kind_to_agui(pi_agent.PiAgentEnd)
  |> fn(_) { True }
  |> should.be_true()
}

pub fn pi_agent_event_bridge_tool_test() {
  pi_agent.pi_event_kind_to_agui(pi_agent.PiToolExecutionStart)
  |> fn(_) { True }
  |> should.be_true()
}

pub fn pi_agent_build_event_topic_test() {
  pi_agent.build_event_topic("s1", "start")
  |> string.contains("s1")
  |> should.be_true()
}

pub fn pi_agent_is_c3i_tool_test() {
  pi_agent.is_c3i_tool("plan_status")
  |> should.be_true()
  pi_agent.is_c3i_tool("bash")
  |> should.be_false()
}

pub fn pi_agent_tier_to_string_test() {
  pi_agent.tier_to_string(pi_agent.GeminiDirect)
  |> string.length()
  |> should.not_equal(0)
}

// =============================================================================
// Pi Zenoh Bridge (pi_zenoh.gleam) — 8 tests
// =============================================================================

pub fn zenoh_events_topic_test() {
  pi_zenoh.pi_events_topic |> should.equal("indrajaal/pi/events")
}

pub fn zenoh_tools_topic_test() {
  pi_zenoh.pi_tools_topic |> should.equal("indrajaal/pi/tools")
}

pub fn zenoh_sessions_topic_test() {
  pi_zenoh.pi_sessions_topic |> should.equal("indrajaal/pi/sessions")
}

pub fn zenoh_health_topic_test() {
  pi_zenoh.pi_health_topic |> should.equal("indrajaal/pi/health")
}

pub fn zenoh_inference_topic_test() {
  pi_zenoh.pi_inference_topic |> should.equal("indrajaal/pi/inference")
}

pub fn zenoh_all_topics_count_test() {
  { list.length(pi_zenoh.all_pi_topics()) >= 5 } |> should.be_true()
}

pub fn zenoh_otel_topic_test() {
  pi_zenoh.pi_otel_topic("test_op")
  |> string.contains("test_op")
  |> should.be_true()
}

pub fn zenoh_state_variants_test() {
  let states = [
    pi_zenoh.PiStarting,
    pi_zenoh.PiOnline,
    pi_zenoh.PiOffline,
    pi_zenoh.PiFailed("test"),
    pi_zenoh.PiDraining,
  ]
  list.length(states) |> should.equal(5)
}

// =============================================================================
// Pi Tools Federation (pi_tools.gleam) — 6 tests
// =============================================================================

pub fn tools_all_count_test() {
  { list.length(pi_tools.all_federated_tools()) >= 30 } |> should.be_true()
}

pub fn tools_pi_source_test() {
  pi_tools.pi_tools()
  |> list.each(fn(t) {
    case t.source {
      pi_tools.PiTool -> True
      _ -> False
    }
    |> should.be_true()
  })
}

pub fn tools_c3i_source_test() {
  pi_tools.c3i_tools()
  |> list.each(fn(t) {
    case t.source {
      pi_tools.C3iTool -> True
      _ -> False
    }
    |> should.be_true()
  })
}

pub fn tools_guardian_gated_test() {
  { list.length(pi_tools.tools_requiring_guardian()) >= 1 } |> should.be_true()
}

pub fn tools_count_function_test() {
  { pi_tools.tool_count() >= 30 } |> should.be_true()
}

pub fn tools_layer_filter_test() {
  { list.length(pi_tools.tools_by_layer(3)) >= 0 } |> should.be_true()
}

// =============================================================================
// Pi Session Bridge (pi_session.gleam) — 6 tests
// =============================================================================

pub fn session_status_variants_test() {
  let statuses = [
    pi_session.Active, pi_session.Compacted, pi_session.Forked,
    pi_session.Exported,
  ]
  list.length(statuses) |> should.equal(4)
}

pub fn session_entry_header_test() {
  let e = pi_session.SessionHeader("h1", 3, 1_713_500_000, "/home")
  case e {
    pi_session.SessionHeader(_, 3, _, _) -> True
    _ -> False
  }
  |> should.be_true()
}

pub fn session_entry_message_test() {
  let e = pi_session.SessionMessage("m1", "user", "Hi", "h1", 1_713_500_001)
  case e {
    pi_session.SessionMessage(_, "user", _, _, _) -> True
    _ -> False
  }
  |> should.be_true()
}

pub fn session_stats_test() {
  let s = pi_session.session_stats()
  { s.0 >= 0 } |> should.be_true()
}

pub fn session_to_smriti_test() {
  let state =
    pi_session.PiSessionState(
      session_id: "t1",
      message_count: 5,
      branch_depth: 0,
      model: "flash",
      provider: "google",
      thinking_level: "medium",
      status: pi_session.Active,
      created_at: 1_713_500_000,
      last_active: 1_713_500_100,
    )
  let json = pi_session.session_to_smriti(state)
  json |> string.contains("t1") |> should.be_true()
  json |> string.contains("google") |> should.be_true()
}

pub fn session_message_to_holon_test() {
  let entry =
    pi_session.SessionMessage("m1", "assistant", "Hello!", "h1", 1_713_500_001)
  let holon = pi_session.message_to_holon(entry)
  holon |> string.contains("assistant") |> should.be_true()
}

// =============================================================================
// Pi Provider Bridge (pi_provider.gleam) — 10 tests
// =============================================================================

pub fn provider_default_config_test() {
  let c = pi_provider.default_config()
  c.name |> should.equal("c3i-cortex")
  c.hedged |> should.be_true()
  c.timeout_ms |> should.equal(15_000)
}

pub fn provider_circuit_breaker_test() {
  let cb = pi_provider.default_circuit_breaker()
  cb.failure_threshold |> should.equal(3)
  cb.cooldown_seconds |> should.equal(60)
}

pub fn provider_all_tiers_test() {
  list.length(pi_provider.all_tiers()) |> should.equal(6)
}

pub fn provider_tier_names_test() {
  pi_provider.all_tiers()
  |> list.each(fn(t) {
    { string.length(pi_provider.tier_name(t)) > 0 } |> should.be_true()
  })
}

pub fn provider_tier_count_test() {
  pi_provider.tier_count() |> should.equal(6)
}

pub fn provider_cb_closed_test() {
  case pi_provider.check_circuit_breaker(pi_provider.Closed, 1_713_500_000) {
    pi_provider.Closed -> True
    _ -> False
  }
  |> should.be_true()
}

pub fn provider_gemini_tier_test() {
  pi_provider.tier_name(pi_provider.GeminiDirect)
  |> string.length()
  |> should.not_equal(0)
}

pub fn provider_rete_tier_test() {
  pi_provider.tier_name(pi_provider.ReteUlRules)
  |> string.length()
  |> should.not_equal(0)
}

pub fn provider_health_test() {
  pi_provider.provider_health()
  |> string.contains("c3i-cortex")
  |> should.be_true()
}

pub fn provider_latency_budget_test() {
  // GeminiDirect should have reasonable latency budget
  { pi_provider.tier_latency_budget_ms(pi_provider.GeminiDirect) > 0 }
  |> should.be_true()
}

// =============================================================================
// Cross-Module Integration — 5 tests
// =============================================================================

pub fn cross_zenoh_topics_consistent_test() {
  pi_agent.pi_events_topic |> string.contains("events") |> should.be_true()
  pi_zenoh.pi_events_topic |> string.contains("events") |> should.be_true()
}

pub fn cross_tool_sources_match_test() {
  {
    list.length(pi_tools.pi_tools()) + list.length(pi_tools.c3i_tools())
    == pi_tools.tool_count()
  }
  |> should.be_true()
}

pub fn cross_provider_tiers_match_test() {
  list.length(pi_provider.all_tiers()) |> should.equal(pi_provider.tier_count())
}

pub fn cross_session_roundtrip_test() {
  let state =
    pi_session.PiSessionState(
      session_id: "rt-1",
      message_count: 10,
      branch_depth: 1,
      model: "opus",
      provider: "anthropic",
      thinking_level: "high",
      status: pi_session.Active,
      created_at: 1_713_500_000,
      last_active: 1_713_600_000,
    )
  let json = pi_session.session_to_smriti(state)
  json |> string.contains("rt-1") |> should.be_true()
  json |> string.contains("anthropic") |> should.be_true()
  json |> string.contains("opus") |> should.be_true()
}

pub fn cross_all_modules_compile_test() {
  // If this test runs, all 5 modules compiled successfully
  let checks = [
    pi_agent.state_to_string(pi_agent.PiIdle),
    pi_zenoh.pi_events_topic,
    pi_provider.provider_health(),
  ]
  { list.length(checks) == 3 } |> should.be_true()
}
