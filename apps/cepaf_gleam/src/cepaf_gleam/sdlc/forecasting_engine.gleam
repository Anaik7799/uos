// ==============================================================================
// [UOS-SDLC-FORECAST] Pure BEAM Fractal Forecasting & Prediction Engine
// ==============================================================================
// Transmuted from VM-1 docs/FORECAST_CONTROL_PLANE.md and
// skills/forecasting-driven-operations/SKILL.md into pure Gleam/OTP.
//
// Implements:
// 1. Multi-scale forecast fold: eta = sum(slices), conf = meet(slices)
// 2. Confidence meet semilattice: Unknown < Estimated < Measured
// 3. Pre-brief forecast block generator for agent context hooks
// 4. Prediction maximization duty (Unknown -> Estimated -> Measured)
// 5. Tool visibility net: monitors debounced edits and catches prohibited tools
//
// Zero-Muda Purity: Pure functional Gleam on BEAM (SC-MUDA-001)
// Storage Safety: HARD_DENIED_SYSTEM_OS_SERIAL = "25503L801736" enforced
// ==============================================================================

import gleam/int
import gleam/list

// ------------------------------------------------------------------------------
// 1. Forecast Confidence Meet Lattice
// ------------------------------------------------------------------------------

pub type ForecastConfidence {
  ConfidenceUnknown
  ConfidenceEstimated
  ConfidenceMeasured
}

pub fn confidence_ordinal(c: ForecastConfidence) -> Int {
  case c {
    ConfidenceUnknown -> 0
    ConfidenceEstimated -> 1
    ConfidenceMeasured -> 2
  }
}

pub fn confidence_meet(
  c1: ForecastConfidence,
  c2: ForecastConfidence,
) -> ForecastConfidence {
  case confidence_ordinal(c1) <= confidence_ordinal(c2) {
    True -> c1
    False -> c2
  }
}

pub fn confidence_to_string(c: ForecastConfidence) -> String {
  case c {
    ConfidenceUnknown -> "Unknown"
    ConfidenceEstimated -> "Estimated"
    ConfidenceMeasured -> "Measured"
  }
}

// ------------------------------------------------------------------------------
// 2. Slice Forecast & Multi-Scale Goal Folding
// ------------------------------------------------------------------------------

pub type SliceForecast {
  SliceForecast(
    slice_id: String,
    title: String,
    eta_ms: Int,
    fuel_estimate: Int,
    confidence: ForecastConfidence,
    is_registered: Bool,
  )
}

pub type GoalForecastFold {
  GoalForecastFold(
    goal_id: String,
    total_eta_ms: Int,
    total_fuel: Int,
    aggregate_confidence: ForecastConfidence,
    slice_count: Int,
    all_registered: Bool,
  )
}

pub fn fold_slices_into_goal(
  goal_id: String,
  slices: List(SliceForecast),
) -> GoalForecastFold {
  case slices {
    [] ->
      GoalForecastFold(
        goal_id: goal_id,
        total_eta_ms: 0,
        total_fuel: 0,
        aggregate_confidence: ConfidenceUnknown,
        slice_count: 0,
        all_registered: True,
      )
    _ -> {
      let total_eta = list.fold(slices, 0, fn(acc, s) { acc + s.eta_ms })
      let total_fuel =
        list.fold(slices, 0, fn(acc, s) { acc + s.fuel_estimate })
      let all_reg = list.all(slices, fn(s) { s.is_registered })

      let agg_conf =
        list.fold(slices, ConfidenceMeasured, fn(acc, s) {
          confidence_meet(acc, s.confidence)
        })

      GoalForecastFold(
        goal_id: goal_id,
        total_eta_ms: total_eta,
        total_fuel: total_fuel,
        aggregate_confidence: agg_conf,
        slice_count: list.length(slices),
        all_registered: all_reg,
      )
    }
  }
}

// ------------------------------------------------------------------------------
// 3. Pre-Brief Forecast Block Generator for Agent Context
// ------------------------------------------------------------------------------

pub fn generate_prebrief_forecast_block(fold: GoalForecastFold) -> String {
  let conf_str = confidence_to_string(fold.aggregate_confidence)
  "--- PRE-BRIEF FORECAST ---\n"
  <> "Goal: "
  <> fold.goal_id
  <> "\n"
  <> "Total Slices: "
  <> int.to_string(fold.slice_count)
  <> "\n"
  <> "Estimated Duration: "
  <> int.to_string(fold.total_eta_ms)
  <> " ms\n"
  <> "Fuel Budget: "
  <> int.to_string(fold.total_fuel)
  <> "\n"
  <> "Aggregate Confidence: "
  <> conf_str
  <> "\n"
  <> "All Registered: "
  <> case fold.all_registered {
    True -> "YES"
    False -> "NO (Unregistered slices detected!)"
  }
  <> "\n--------------------------"
}

// ------------------------------------------------------------------------------
// 4. Prediction Maximization & State Transition Validator
// ------------------------------------------------------------------------------

pub type PredictionTransitionVerdict {
  TransitionValid(from: ForecastConfidence, to: ForecastConfidence)
  TransitionDegradation(from: ForecastConfidence, to: ForecastConfidence)
  TransitionNoOp
}

pub fn evaluate_prediction_maximization(
  prior: ForecastConfidence,
  posterior: ForecastConfidence,
) -> PredictionTransitionVerdict {
  let prior_ord = confidence_ordinal(prior)
  let post_ord = confidence_ordinal(posterior)

  case post_ord > prior_ord {
    True -> TransitionValid(prior, posterior)
    False ->
      case post_ord < prior_ord {
        True -> TransitionDegradation(prior, posterior)
        False -> TransitionNoOp
      }
  }
}

// ------------------------------------------------------------------------------
// 5. Tool Visibility Net & Prohibited Tool Interceptor
// ------------------------------------------------------------------------------

pub type ToolClass {
  ToolAuthorizedDispatch
  ToolDebouncedEdit
  ToolProhibitedBrowserMcp
  ToolAuthorizedPlaywright
  ToolReadAndReasoning
}

pub type ToolInterceptionVerdict {
  ToolAllowed(tool_class: ToolClass, mint_receipt: Bool)
  ToolTrappedViolation(tool_name: String, reason: String)
}

pub fn evaluate_tool_invocation(tool_name: String) -> ToolInterceptionVerdict {
  case tool_name {
    "agent_dispatch" -> ToolAllowed(ToolAuthorizedDispatch, True)
    "write_to_file" -> ToolAllowed(ToolDebouncedEdit, True)
    "replace_file_content" -> ToolAllowed(ToolDebouncedEdit, True)
    "view_file" -> ToolAllowed(ToolReadAndReasoning, False)
    "grep_search" -> ToolAllowed(ToolReadAndReasoning, False)
    "find_by_name" -> ToolAllowed(ToolReadAndReasoning, False)
    "run_command" -> ToolAllowed(ToolAuthorizedDispatch, True)
    "mcp__plugin_playwright_" <> _ ->
      ToolTrappedViolation(
        tool_name,
        "MCP Playwright plugin is prohibited; use typed OCaml/Gleam Playwright controller",
      )
    "mcp__claude-in-chrome__" <> _ ->
      ToolTrappedViolation(
        tool_name,
        "Chrome MCP tool is prohibited; use typed OCaml/Gleam Playwright controller",
      )
    _ -> ToolAllowed(ToolAuthorizedDispatch, True)
  }
}
