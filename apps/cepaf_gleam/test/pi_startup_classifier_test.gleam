//// =============================================================================
//// Test Module: test/pi_startup_classifier_test.gleam
//// Subject: Pi Startup Process Classification, Intelligent Messaging & GUI Events
//// =============================================================================

import cepaf_gleam/agui/events.{Custom}
import cepaf_gleam/bridge/pi_startup_classifier.{
  StageFailed, StageMeshSync, StageOperationalReady, StagePreflight,
  StageProcessSpawn, StageProtocolHandshake, StageProviderAuth,
  StageToolFederation, advance_stage, fail_startup, format_intelligent_message,
  init_startup, nominal_stages, render_ansi_startup_banner,
  render_html_startup_card, stage_metadata, stage_to_id, stage_to_json,
  to_agui_event,
}
import gleam/json
import gleam/list
import gleam/string
import gleeunit/should

pub fn nominal_stages_sequence_test() {
  let stages = nominal_stages()
  list.length(stages) |> should.equal(7)

  case stages {
    [s1, s2, s3, s4, s5, s6, s7] -> {
      s1 |> should.equal(StagePreflight)
      s2 |> should.equal(StageProviderAuth)
      s3 |> should.equal(StageProcessSpawn)
      s4 |> should.equal(StageProtocolHandshake)
      s5 |> should.equal(StageToolFederation)
      s6 |> should.equal(StageMeshSync)
      s7 |> should.equal(StageOperationalReady)
    }
    _ -> panic as "Nominal stages sequence mismatch"
  }
}

pub fn stage_to_id_test() {
  stage_to_id(StagePreflight) |> should.equal("preflight_env")
  stage_to_id(StageProviderAuth) |> should.equal("provider_auth")
  stage_to_id(StageProcessSpawn) |> should.equal("process_spawn")
  stage_to_id(StageProtocolHandshake) |> should.equal("protocol_handshake")
  stage_to_id(StageToolFederation) |> should.equal("tool_federation")
  stage_to_id(StageMeshSync) |> should.equal("mesh_sync")
  stage_to_id(StageOperationalReady) |> should.equal("operational_ready")
  stage_to_id(StageFailed("timeout", "API quota exceeded"))
  |> should.equal("failed_at_timeout")
}

pub fn stage_metadata_calculation_test() {
  let meta1 =
    stage_metadata(StagePreflight, 50, "anthropic", "claude-3-5-sonnet")
  meta1.step_number |> should.equal(1)
  meta1.progress_pct |> should.equal(15)
  meta1.is_active |> should.equal(True)
  meta1.is_completed |> should.equal(False)
  meta1.icon |> should.equal("🔍")
  string.contains(meta1.title, "Preflight") |> should.equal(True)

  let meta_ready =
    stage_metadata(StageOperationalReady, 980, "deepseek", "deepseek-coder")
  meta_ready.progress_pct |> should.equal(100)
  meta_ready.is_active |> should.equal(False)
  meta_ready.is_completed |> should.equal(True)
  meta_ready.icon |> should.equal("✅")
  meta_ready.estimated_remaining_ms |> should.equal(0)

  let meta_failed =
    stage_metadata(
      StageFailed("provider_auth", "invalid key"),
      200,
      "openai",
      "gpt-4o",
    )
  meta_failed.progress_pct |> should.equal(0)
  meta_failed.icon |> should.equal("❌")
  string.contains(meta_failed.detail, "invalid key") |> should.equal(True)
}

pub fn format_intelligent_message_test() {
  let meta_stage =
    stage_metadata(StageToolFederation, 420, "anthropic", "claude-3-7-sonnet")
  let msg = format_intelligent_message(meta_stage)

  string.contains(msg, "[pi_startup]") |> should.equal(True)
  string.contains(msg, "Step 5/6") |> should.equal(True)
  string.contains(msg, "80%") |> should.equal(True)
  string.contains(msg, "420ms elapsed") |> should.equal(True)
  string.contains(msg, "150ms remaining") |> should.equal(True)

  let meta_ready =
    stage_metadata(StageOperationalReady, 820, "anthropic", "claude-3-7-sonnet")
  let ready_msg = format_intelligent_message(meta_ready)
  string.contains(ready_msg, "Operational & Ready (820ms total)")
  |> should.equal(True)

  let meta_failed =
    stage_metadata(
      StageFailed("mesh_sync", "zenoh connection refused"),
      550,
      "modular",
      "max-engine",
    )
  let failed_msg = format_intelligent_message(meta_failed)
  string.contains(failed_msg, "Startup Failed") |> should.equal(True)
  string.contains(failed_msg, "zenoh connection refused") |> should.equal(True)
  string.contains(failed_msg, "Hint:") |> should.equal(True)
}

pub fn stage_to_json_and_agui_event_test() {
  let meta =
    stage_metadata(StageMeshSync, 650, "anthropic", "claude-3-5-sonnet")
  let json_val = stage_to_json(meta, "anthropic", "claude-3-5-sonnet")
  let json_str = json.to_string(json_val)

  string.contains(json_str, "\"subsystem\":\"pi_runtime\"")
  |> should.equal(True)
  string.contains(json_str, "\"stage_id\":\"mesh_sync\"") |> should.equal(True)
  string.contains(json_str, "\"progress_pct\":95") |> should.equal(True)

  let event =
    to_agui_event(
      meta,
      "anthropic",
      "claude-3-5-sonnet",
      "thread-42",
      "run-99",
      1_725_564_000,
    )

  event.event_type |> should.equal(Custom)
  event.thread_id |> should.equal("thread-42")
  event.run_id |> should.equal("run-99")
  event.timestamp |> should.equal(1_725_564_000)
}

pub fn state_machine_transitions_test() {
  let s0 = init_startup("anthropic", "claude-3-7-sonnet", 1000)
  s0.current_stage |> should.equal(StagePreflight)
  s0.provider |> should.equal("anthropic")
  s0.model |> should.equal("claude-3-7-sonnet")
  s0.current_elapsed_ms |> should.equal(0)
  s0.completed_stages |> should.equal([])

  let s1 = advance_stage(s0, StageProviderAuth, 1120)
  s1.current_stage |> should.equal(StageProviderAuth)
  s1.current_elapsed_ms |> should.equal(120)
  s1.completed_stages |> should.equal([StagePreflight])

  let s2 = advance_stage(s1, StageProcessSpawn, 1250)
  s2.current_stage |> should.equal(StageProcessSpawn)
  s2.current_elapsed_ms |> should.equal(250)
  s2.completed_stages |> should.equal([StagePreflight, StageProviderAuth])

  let s_fail = fail_startup(s2, "Spawn failed: command not found", 1300)
  case s_fail.current_stage {
    StageFailed(stage_id, reason) -> {
      stage_id |> should.equal("process_spawn")
      reason |> should.equal("Spawn failed: command not found")
    }
    _ -> panic as "Expected StageFailed"
  }
  s_fail.current_elapsed_ms |> should.equal(300)
}

pub fn render_ui_test() {
  let s0 = init_startup("anthropic", "claude-3-7-sonnet", 0)
  let s_active = advance_stage(s0, StageProtocolHandshake, 350)

  // Verify ANSI rendering
  let ansi = render_ansi_startup_banner(s_active)
  string.contains(ansi, "[PI-STARTUP]") |> should.equal(True)
  string.contains(ansi, "Protocol Handshake") |> should.equal(True)
  string.contains(ansi, "65%") |> should.equal(True)

  // Verify HTML component rendering
  let elem = render_html_startup_card(s_active)
  // Ensure element has child elements
  let rendered_str = string.inspect(elem)
  string.contains(rendered_str, "pi-startup-card") |> should.equal(True)
}
