// ==============================================================================
// [UOS-SDLC-FORECAST-TEST] Test Suite for Fractal Forecasting & Tool Net
// ==============================================================================

import cepaf_gleam/sdlc/forecasting_engine.{
  ConfidenceEstimated, ConfidenceMeasured, ConfidenceUnknown,
  SliceForecast, ToolDebouncedEdit, ToolTrappedViolation,
  confidence_meet, evaluate_prediction_maximization, evaluate_tool_invocation,
  fold_slices_into_goal, generate_prebrief_forecast_block,
}
import gleam/string
import gleeunit/should

pub fn confidence_meet_lattice_test() {
  confidence_meet(ConfidenceMeasured, ConfidenceEstimated)
  |> should.equal(ConfidenceEstimated)

  confidence_meet(ConfidenceEstimated, ConfidenceUnknown)
  |> should.equal(ConfidenceUnknown)

  confidence_meet(ConfidenceMeasured, ConfidenceMeasured)
  |> should.equal(ConfidenceMeasured)
}

pub fn slices_fold_goal_test() {
  let s1 =
    SliceForecast(
      slice_id: "SLICE-01",
      title: "Core Kernel Implementation",
      eta_ms: 1500,
      fuel_estimate: 200,
      confidence: ConfidenceMeasured,
      is_registered: True,
    )

  let s2 =
    SliceForecast(
      slice_id: "SLICE-02",
      title: "Verification Suite",
      eta_ms: 2500,
      fuel_estimate: 350,
      confidence: ConfidenceEstimated,
      is_registered: True,
    )

  let fold = fold_slices_into_goal("GOAL-FRACTAL-SYNTHESIS", [s1, s2])

  fold.total_eta_ms |> should.equal(4000)
  fold.total_fuel |> should.equal(550)
  fold.slice_count |> should.equal(2)
  fold.all_registered |> should.equal(True)
  // Confidence meets to weakest child: meet(Measured, Estimated) = Estimated
  fold.aggregate_confidence |> should.equal(ConfidenceEstimated)
}

pub fn prebrief_forecast_block_formatting_test() {
  let s1 =
    SliceForecast(
      slice_id: "SLICE-01",
      title: "Core Kernel",
      eta_ms: 1000,
      fuel_estimate: 100,
      confidence: ConfidenceMeasured,
      is_registered: True,
    )
  let fold = fold_slices_into_goal("GOAL-01", [s1])
  let block = generate_prebrief_forecast_block(fold)

  block |> string.contains("PRE-BRIEF FORECAST") |> should.equal(True)
  block |> string.contains("Estimated Duration: 1000 ms") |> should.equal(True)
  block |> string.contains("Aggregate Confidence: Measured") |> should.equal(True)
}

pub fn prediction_maximization_transition_test() {
  case
    evaluate_prediction_maximization(ConfidenceUnknown, ConfidenceMeasured)
  {
    forecasting_engine.TransitionValid(from, to) -> {
      from |> should.equal(ConfidenceUnknown)
      to |> should.equal(ConfidenceMeasured)
      True
    }
    _ -> False
  }
  |> should.equal(True)

  case
    evaluate_prediction_maximization(ConfidenceMeasured, ConfidenceUnknown)
  {
    forecasting_engine.TransitionDegradation(from, to) -> {
      from |> should.equal(ConfidenceMeasured)
      to |> should.equal(ConfidenceUnknown)
      True
    }
    _ -> False
  }
  |> should.equal(True)
}

pub fn tool_interception_net_test() {
  // Authorized edit
  case evaluate_tool_invocation("write_to_file") {
    forecasting_engine.ToolAllowed(class, mint) -> {
      class |> should.equal(ToolDebouncedEdit)
      mint |> should.equal(True)
      True
    }
    _ -> False
  }
  |> should.equal(True)

  // Banned MCP browser plugin trapped
  case evaluate_tool_invocation("mcp__plugin_playwright_navigate") {
    ToolTrappedViolation(tool, reason) -> {
      tool |> should.equal("mcp__plugin_playwright_navigate")
      reason |> string.contains("prohibited") |> should.equal(True)
      True
    }
    _ -> False
  }
  |> should.equal(True)
}
