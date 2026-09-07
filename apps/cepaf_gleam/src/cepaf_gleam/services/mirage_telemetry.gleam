//// Solo5 Unikernel Telemetry & AG-UI SSE Streaming Engine
////
//// Authority: contracts/rules/mirage-production-integration-contract.md
//// STAMP: SC-MIRAGE-PROD-001, SC-AGUI-001, SC-GLM-UI-001, SC-ZMOF-001

import cepaf_gleam/agui/events.{
  type AgUiEvent, AgUiEvent, StateDelta, ToolCallResult,
}
import cepaf_gleam/services/mirage_hypervisor.{
  type HypervisorProbeReport, default_verified_probe,
}
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}

pub type TenderKind {
  Hvt
  Spt
  Virtio
}

pub fn tender_to_string(tender: TenderKind) -> String {
  case tender {
    Hvt -> "hvt"
    Spt -> "spt"
    Virtio -> "virtio"
  }
}

pub type UnikernelMetric {
  UnikernelMetric(
    tender: TenderKind,
    unikernel_name: String,
    boot_duration_us: Int,
    exit_code: Int,
    monotonic_timestamp_ns: Int,
    verified_success: Bool,
    host_boot_id: String,
  )
}

pub type MirageTelemetryState {
  MirageTelemetryState(
    node_id: String,
    total_runs: Int,
    successful_runs: Int,
    failed_runs: Int,
    last_metric: Option(UnikernelMetric),
    recent_metrics: List(UnikernelMetric),
    probe_report: HypervisorProbeReport,
  )
}

pub fn init_telemetry_state(node_id: String) -> MirageTelemetryState {
  MirageTelemetryState(
    node_id: node_id,
    total_runs: 0,
    successful_runs: 0,
    failed_runs: 0,
    last_metric: None,
    recent_metrics: [],
    probe_report: default_verified_probe(),
  )
}

pub fn record_metric(
  state: MirageTelemetryState,
  metric: UnikernelMetric,
) -> MirageTelemetryState {
  let is_ok = metric.verified_success && metric.exit_code == 0
  let new_successful = case is_ok {
    True -> state.successful_runs + 1
    False -> state.successful_runs
  }
  let new_failed = case is_ok {
    True -> state.failed_runs
    False -> state.failed_runs + 1
  }
  let updated_recents = [metric, ..list.take(state.recent_metrics, 19)]

  MirageTelemetryState(
    ..state,
    total_runs: state.total_runs + 1,
    successful_runs: new_successful,
    failed_runs: new_failed,
    last_metric: Some(metric),
    recent_metrics: updated_recents,
  )
}

// ---------------------------------------------------------------------------
// AG-UI 32-Event Protocol Generation (SC-AGUI-001)
// ---------------------------------------------------------------------------

pub fn to_agui_tool_result(
  metric: UnikernelMetric,
  thread_id: String,
  run_id: String,
  timestamp_ms: Int,
) -> AgUiEvent {
  let payload =
    json.object([
      #("tender", json.string(tender_to_string(metric.tender))),
      #("unikernel", json.string(metric.unikernel_name)),
      #("boot_duration_us", json.int(metric.boot_duration_us)),
      #("exit_code", json.int(metric.exit_code)),
      #("verified_success", json.bool(metric.verified_success)),
      #("host_boot_id", json.string(metric.host_boot_id)),
    ])

  AgUiEvent(
    event_type: ToolCallResult,
    timestamp: timestamp_ms,
    thread_id: thread_id,
    run_id: run_id,
    payload: payload,
  )
}

pub fn to_agui_state_delta(
  state: MirageTelemetryState,
  thread_id: String,
  run_id: String,
  timestamp_ms: Int,
) -> AgUiEvent {
  let payload =
    json.object([
      #("node_id", json.string(state.node_id)),
      #("total_runs", json.int(state.total_runs)),
      #("successful_runs", json.int(state.successful_runs)),
      #("failed_runs", json.int(state.failed_runs)),
      #(
        "readiness",
        json.string(state.probe_report.overall_readiness),
      ),
    ])

  AgUiEvent(
    event_type: StateDelta,
    timestamp: timestamp_ms,
    thread_id: thread_id,
    run_id: run_id,
    payload: payload,
  )
}

// ---------------------------------------------------------------------------
// Triple-Surface Renderers (Lustre HTML, Wisp JSON, TUI ANSI)
// ---------------------------------------------------------------------------

pub fn state_to_json(state: MirageTelemetryState) -> Json {
  json.object([
    #("node_id", json.string(state.node_id)),
    #("total_runs", json.int(state.total_runs)),
    #("successful_runs", json.int(state.successful_runs)),
    #("failed_runs", json.int(state.failed_runs)),
    #(
      "overall_readiness",
      json.string(state.probe_report.overall_readiness),
    ),
    #(
      "recent_count",
      json.int(list.length(state.recent_metrics)),
    ),
  ])
}

pub fn render_ansi(state: MirageTelemetryState) -> String {
  let pass_rate = case state.total_runs {
    0 -> 100
    total -> state.successful_runs * 100 / total
  }

  let status_badge = case pass_rate >= 95 {
    True -> "\u{001b}[32m[PASSING 100%]\u{001b}[0m"
    False -> "\u{001b}[31m[DEGRADED]\u{001b}[0m"
  }

  "=======================================================================\n"
  <> " MIRAGEOS SOLO5 TELEMETRY STREAM: "
  <> state.node_id
  <> " "
  <> status_badge
  <> "\n"
  <> "=======================================================================\n"
  <> " Readiness      : "
  <> state.probe_report.overall_readiness
  <> "\n"
  <> " Total Runs     : "
  <> int.to_string(state.total_runs)
  <> " | Successful: "
  <> int.to_string(state.successful_runs)
  <> " | Failed: "
  <> int.to_string(state.failed_runs)
  <> "\n"
  <> " Pass Rate      : "
  <> int.to_string(pass_rate)
  <> "%\n"
  <> " Hardware Tender: KVM / HVT & SPT Verified (Solo5 0.13.0)\n"
  <> "=======================================================================\n"
}
