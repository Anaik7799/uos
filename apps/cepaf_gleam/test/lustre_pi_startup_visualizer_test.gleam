//// =============================================================================
//// Test Module: test/lustre_pi_startup_visualizer_test.gleam
//// Subject: Lustre MVU Pi Startup Visualizer Component Tests
//// =============================================================================

import gleeunit/should
import gleam/list
import gleam/option.{Some}
import gleam/string
import cepaf_gleam/bridge/pi_startup_classifier.{
  StageOperationalReady, StagePreflight, StageProviderAuth,
}
import cepaf_gleam/ui/lustre/pi_startup_visualizer.{
  ClearLogs, FailStage, NextStage, ResetStartup, SetStepDetail, init, update,
  view,
}

pub fn init_model_test() {
  let model = init()
  model.state.current_stage |> should.equal(StagePreflight)
  model.simulated_now_ms |> should.equal(0)
  model.selected_step_info |> should.equal(Some(1))
  { list.length(model.log_messages) >= 1 } |> should.equal(True)
}

pub fn update_progression_test() {
  let m0 = init()
  let m1 = update(m0, NextStage)
  m1.state.current_stage |> should.equal(StageProviderAuth)
  m1.simulated_now_ms |> should.equal(140)

  // Advance through to operational ready
  let m2 =
    m1
    |> update(NextStage)
    |> update(NextStage)
    |> update(NextStage)
    |> update(NextStage)
    |> update(NextStage)
  m2.state.current_stage |> should.equal(StageOperationalReady)

  // Fail stage
  let m3 = update(m2, FailStage("Process SIGSEGV"))
  case m3.state.current_stage {
    pi_startup_classifier.StageFailed(stage, reason) -> {
      stage |> should.equal("operational_ready")
      reason |> should.equal("Process SIGSEGV")
    }
    _ -> panic as "Expected StageFailed"
  }

  // Reset
  let m4 = update(m3, ResetStartup)
  m4.state.current_stage |> should.equal(StagePreflight)
  m4.simulated_now_ms |> should.equal(0)

  // Step detail & clear logs
  let m5 = update(m4, SetStepDetail(4))
  m5.selected_step_info |> should.equal(Some(4))
  let m6 = update(m5, ClearLogs)
  m6.log_messages |> should.equal([])
}

pub fn view_render_test() {
  let model = init()
  let elem = view(model)
  let elem_str = string.inspect(elem)
  string.contains(elem_str, "pi-startup-visualizer") |> should.equal(True)
  string.contains(elem_str, "SC-PI-STARTUP-001") |> should.equal(True)
}
