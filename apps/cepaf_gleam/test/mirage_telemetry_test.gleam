//// MirageOS Solo5 Telemetry Unit Tests
//// STAMP: SC-MIRAGE-PROD-001, SC-AGUI-001

import cepaf_gleam/agui/events.{StateDelta, ToolCallResult}
import cepaf_gleam/services/mirage_telemetry.{
  Hvt, Spt, UnikernelMetric, init_telemetry_state, record_metric, render_ansi,
  state_to_json, to_agui_state_delta, to_agui_tool_result,
}
import gleeunit/should

pub fn init_telemetry_state_test() {
  let state = init_telemetry_state("nas-1")
  state.node_id |> should.equal("nas-1")
  state.total_runs |> should.equal(0)
  state.successful_runs |> should.equal(0)
  state.failed_runs |> should.equal(0)
}

pub fn record_metric_success_test() {
  let state = init_telemetry_state("nas-1")
  let metric =
    UnikernelMetric(
      tender: Hvt,
      unikernel_name: "test_hello.hvt",
      boot_duration_us: 14_200,
      exit_code: 0,
      monotonic_timestamp_ns: 1_788_800_000_000_000,
      verified_success: True,
      host_boot_id: "1d08ac42-93f9-4839-951f-f7745671cca3",
    )

  let state1 = record_metric(state, metric)
  state1.total_runs |> should.equal(1)
  state1.successful_runs |> should.equal(1)
  state1.failed_runs |> should.equal(0)
}

pub fn record_metric_failure_test() {
  let state = init_telemetry_state("nas-1")
  let metric =
    UnikernelMetric(
      tender: Spt,
      unikernel_name: "test_hello.spt",
      boot_duration_us: 5_000_000,
      exit_code: 137,
      monotonic_timestamp_ns: 1_788_800_000_000_000,
      verified_success: False,
      host_boot_id: "1d08ac42-93f9-4839-951f-f7745671cca3",
    )

  let state1 = record_metric(state, metric)
  state1.total_runs |> should.equal(1)
  state1.successful_runs |> should.equal(0)
  state1.failed_runs |> should.equal(1)
}

pub fn agui_event_generation_test() {
  let metric =
    UnikernelMetric(
      tender: Hvt,
      unikernel_name: "test_hello.hvt",
      boot_duration_us: 14_200,
      exit_code: 0,
      monotonic_timestamp_ns: 1_788_800_000_000_000,
      verified_success: True,
      host_boot_id: "1d08ac42-93f9-4839-951f-f7745671cca3",
    )

  let ev = to_agui_tool_result(metric, "thread-01", "run-01", 1_788_800_000)
  ev.event_type |> should.equal(ToolCallResult)

  let state = init_telemetry_state("nas-1")
  let delta_ev = to_agui_state_delta(state, "thread-01", "run-01", 1_788_800_000)
  delta_ev.event_type |> should.equal(StateDelta)
}

pub fn triple_surface_rendering_test() {
  let state = init_telemetry_state("nas-1")
  let _json_val = state_to_json(state)
  let ansi_val = render_ansi(state)
  ansi_val |> should.not_equal("")
}
