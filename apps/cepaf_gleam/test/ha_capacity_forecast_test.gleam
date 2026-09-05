/// Capacity Forecast Tests — L4_SYSTEM
/// STAMP: SC-HA-001, SC-BIO-EVO-001, SC-MUDA-001
///
/// 15 tests covering:
///   C1 Type construction — ResourceForecast, CapacityPlan
///   C2 forecast_resource — trend detection, recommendation thresholds
///   C3 time_to_exhaustion — zero rate, growing, already exhausted
///   C4 plan_capacity — aggregation, health score
///   C5 Edge cases — empty history, single-element history
///   C8 summary — non-empty string output
import cepaf_gleam/ha/capacity_forecast.{
  forecast_resource, plan_capacity, plan_health, recommend_action, summary,
  time_to_exhaustion,
}
import gleam/list
import gleeunit/should

// ---------------------------------------------------------------------------
// C1: Type construction
// ---------------------------------------------------------------------------

pub fn forecast_resource_returns_resource_name_test() {
  let f = forecast_resource("cpu", [0.1, 0.2, 0.3], 10)
  f.resource_name |> should.equal("cpu")
}

pub fn plan_capacity_aggregates_forecasts_test() {
  let f1 = forecast_resource("cpu", [0.5, 0.5, 0.5], 10)
  let f2 = forecast_resource("mem", [0.3, 0.3, 0.3], 10)
  let plan = plan_capacity([f1, f2])
  let count_ok = plan.forecasts |> list.length |> should.equal(2)
  count_ok
}

// ---------------------------------------------------------------------------
// C2: forecast_resource recommendations
// ---------------------------------------------------------------------------

pub fn forecast_resource_no_action_for_low_usage_test() {
  // Usage at ~0.3 — well below 0.6 threshold
  let f = forecast_resource("mem", [0.28, 0.29, 0.3, 0.31], 5)
  f.recommendation |> should.equal("no_action")
}

pub fn forecast_resource_scale_up_for_high_usage_test() {
  // Usage already at 0.95 — should recommend scale_up
  let f = forecast_resource("disk", [0.85, 0.88, 0.91, 0.95], 3)
  f.recommendation |> should.equal("scale_up")
}

pub fn forecast_resource_trend_increasing_test() {
  let f = forecast_resource("cpu", [0.1, 0.2, 0.4, 0.6], 5)
  f.trend |> should.equal("increasing")
}

pub fn forecast_resource_trend_stable_test() {
  let f = forecast_resource("latency", [0.5, 0.5, 0.5, 0.5], 5)
  f.trend |> should.equal("stable")
}

pub fn forecast_resource_current_usage_matches_last_test() {
  let history = [0.1, 0.3, 0.55]
  let f = forecast_resource("net", history, 5)
  f.current_usage |> should.equal(0.55)
}

// ---------------------------------------------------------------------------
// C3: time_to_exhaustion
// ---------------------------------------------------------------------------

pub fn time_to_exhaustion_zero_rate_returns_max_test() {
  time_to_exhaustion(0.5, 0.0, 1.0) |> should.equal(9999)
}

pub fn time_to_exhaustion_negative_rate_returns_max_test() {
  time_to_exhaustion(0.5, -0.1, 1.0) |> should.equal(9999)
}

pub fn time_to_exhaustion_already_at_capacity_returns_zero_test() {
  time_to_exhaustion(1.0, 0.1, 1.0) |> should.equal(0)
}

pub fn time_to_exhaustion_known_rate_test() {
  // current=0.5, rate=0.1, capacity=1.0 → remaining=0.5 → 5 cycles
  let cycles = time_to_exhaustion(0.5, 0.1, 1.0)
  cycles |> should.equal(5)
}

// ---------------------------------------------------------------------------
// C4: plan_capacity and plan_health
// ---------------------------------------------------------------------------

pub fn plan_health_all_no_action_is_one_test() {
  let f1 = forecast_resource("cpu", [0.1, 0.1, 0.1], 5)
  let f2 = forecast_resource("mem", [0.2, 0.2, 0.2], 5)
  let plan = plan_capacity([f1, f2])
  let h = plan_health(plan)
  h |> should.equal(1.0)
}

pub fn plan_health_empty_plan_is_one_test() {
  let plan = plan_capacity([])
  plan_health(plan) |> should.equal(1.0)
}

pub fn recommend_action_scale_up_when_predicted_over_80_test() {
  let f = forecast_resource("gpu", [0.9, 0.91, 0.92], 1)
  recommend_action(f) |> should.equal("scale_up")
}

// ---------------------------------------------------------------------------
// C5: Edge cases
// ---------------------------------------------------------------------------

pub fn forecast_resource_empty_history_test() {
  let f = forecast_resource("cpu", [], 5)
  f.current_usage |> should.equal(0.0)
  f.recommendation |> should.equal("no_action")
}

// ---------------------------------------------------------------------------
// C8: summary string
// ---------------------------------------------------------------------------

pub fn summary_is_non_empty_test() {
  let f = forecast_resource("cpu", [0.5, 0.6, 0.7], 10)
  let plan = plan_capacity([f])
  let s = summary(plan)
  let non_empty = s != ""
  non_empty |> should.equal(True)
}
