//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/capacity_forecast</module>
////     <fsharp-lineage>None — novel capacity planning module (L4_SYSTEM)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L4_SYSTEM</layer>
////     <mesh-domain>
////       Predictive resource capacity planning for the SIL-6 mesh.
////       Analyses usage history to forecast exhaustion timelines and
////       generate scaling recommendations for CPU, memory, and storage.
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>HIGH</criticality>
////     <stamp-controls>SC-HA-001, SC-BIO-EVO-001, SC-MUDA-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       EMA-based trend extrapolation ↪ Gleam pure value type ResourceForecast.
////     </morphism>
////     <morphism type="surjective" loss="floating-point-precision">
////       IEEE 754 Float64 arithmetic — adequate for advisory; not safety actuation.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// CAPACITY FORECAST — PREDICTIVE RESOURCE PLANNING
//// चयापचय — Metabolism: knowing when the system will exhaust its fuel.
////
//// STAMP: SC-HA-001, SC-BIO-EVO-001, SC-MUDA-001

import gleam/float
import gleam/int
import gleam/list

// =============================================================================
// Public Types
// =============================================================================

/// Forecast for a single named resource (CPU, memory, storage, etc.).
pub type ResourceForecast {
  ResourceForecast(
    /// Human-readable resource name, e.g. "cpu", "heap_mb"
    resource_name: String,
    /// Most recent observed usage fraction ∈ [0, 1]
    current_usage: Float,
    /// Predicted usage at the planning horizon
    predicted_usage: Float,
    /// Qualitative trend: "increasing" | "decreasing" | "stable"
    trend: String,
    /// Estimated number of cycles until the resource is exhausted (capacity = 1.0)
    exhaustion_cycles: Int,
    /// Action recommendation: "scale_up" | "optimize" | "no_action"
    recommendation: String,
  )
}

/// Capacity plan aggregating multiple resource forecasts.
pub type CapacityPlan {
  CapacityPlan(
    /// Per-resource forecasts
    forecasts: List(ResourceForecast),
    /// Composite health score ∈ [0, 1]
    overall_health: Float,
    /// Number of cycles the plan looks ahead
    planning_horizon: Int,
  )
}

// =============================================================================
// Public API
// =============================================================================

/// Produce a `ResourceForecast` for a named resource.
///
/// Applies an EMA (α = 0.3) to `usage_history`, extrapolates `horizon` steps,
/// detects trend, estimates time-to-exhaustion, and recommends an action.
///
/// `usage_history` — fractional usage values ∈ [0, 1], oldest first.
/// `horizon`       — planning lookahead in cycles (must be ≥ 1).
pub fn forecast_resource(
  name: String,
  usage_history: List(Float),
  horizon: Int,
) -> ResourceForecast {
  let safe_horizon = int.max(horizon, 1)
  let current = list.last(usage_history) |> unwrap_float(0.0)

  case usage_history {
    [] ->
      ResourceForecast(
        resource_name: name,
        current_usage: 0.0,
        predicted_usage: 0.0,
        trend: "stable",
        exhaustion_cycles: 9999,
        recommendation: "no_action",
      )
    _ -> {
      let ema_series = compute_ema(usage_history, 0.3)
      let last_ema = list.last(ema_series) |> unwrap_float(current)
      let drift = estimate_drift(ema_series)
      let h_f = int.to_float(safe_horizon)
      let predicted = clamp(last_ema +. drift *. h_f, 0.0, 1.0)
      let t = detect_trend(usage_history)
      let cycles = time_to_exhaustion(current, drift, 1.0)
      let rec = recommend_action_from_predicted(predicted)
      ResourceForecast(
        resource_name: name,
        current_usage: current,
        predicted_usage: predicted,
        trend: t,
        exhaustion_cycles: cycles,
        recommendation: rec,
      )
    }
  }
}

/// Estimate how many cycles remain before `current` usage reaches `capacity`
/// at the given `rate` (usage increase per cycle).
///
/// Returns 9999 when rate ≤ 0 (resource not growing) or already exhausted.
pub fn time_to_exhaustion(current: Float, rate: Float, capacity: Float) -> Int {
  case rate <=. 0.0 {
    True -> 9999
    False -> {
      let remaining = capacity -. current
      case remaining <=. 0.0 {
        True -> 0
        False -> {
          let cycles_f = remaining /. rate
          let cycles = float.round(cycles_f)
          int.max(cycles, 0)
        }
      }
    }
  }
}

/// Map a predicted usage fraction to a scaling recommendation.
///
/// > 0.80 → "scale_up"   (near-capacity, action urgent)
/// > 0.60 → "optimize"   (elevated, watch closely)
/// ≤ 0.60 → "no_action"  (healthy headroom)
pub fn recommend_action(forecast: ResourceForecast) -> String {
  recommend_action_from_predicted(forecast.predicted_usage)
}

/// Aggregate individual `ResourceForecast` values into a `CapacityPlan`.
///
/// `planning_horizon` is taken from the first forecast's implied horizon;
/// when the list is empty a horizon of 0 is used.
pub fn plan_capacity(forecasts: List(ResourceForecast)) -> CapacityPlan {
  let horizon = case forecasts {
    [] -> 0
    [f, ..] -> {
      // Derive horizon heuristic from exhaustion_cycles (bounded to 100)
      int.min(f.exhaustion_cycles, 100)
    }
  }
  let health = plan_health_from_list(forecasts)
  CapacityPlan(
    forecasts: forecasts,
    overall_health: health,
    planning_horizon: horizon,
  )
}

/// Compute the composite health score of a plan.
///
/// health = 1 − (count of forecasts needing action / total forecasts)
///
/// A forecast "needs action" when its recommendation is "scale_up" or
/// "optimize".  Returns 1.0 when the list is empty.
pub fn plan_health(plan: CapacityPlan) -> Float {
  plan_health_from_list(plan.forecasts)
}

/// Render a human-readable summary of the capacity plan.
pub fn summary(plan: CapacityPlan) -> String {
  let n = list.length(plan.forecasts)
  let needing =
    list.filter(plan.forecasts, fn(f) { f.recommendation != "no_action" })
    |> list.length
  "CapacityPlan{resources="
  <> int.to_string(n)
  <> " needing_action="
  <> int.to_string(needing)
  <> " health="
  <> float.to_string(plan.overall_health)
  <> " horizon="
  <> int.to_string(plan.planning_horizon)
  <> "}"
}

// =============================================================================
// Internal helpers
// =============================================================================

/// Compute the full EMA sequence for `series` with smoothing `alpha`.
fn compute_ema(series: List(Float), alpha: Float) -> List(Float) {
  let safe_alpha = clamp(alpha, 1.0e-6, 1.0)
  case series {
    [] -> []
    [h, ..rest] ->
      list.fold(rest, [h], fn(acc, x) {
        let prev = list.last(acc) |> unwrap_float(x)
        let new_ema = safe_alpha *. x +. { 1.0 -. safe_alpha } *. prev
        list.append(acc, [new_ema])
      })
  }
}

/// Estimate per-step drift as the mean of consecutive differences in the EMA tail.
fn estimate_drift(ema_values: List(Float)) -> Float {
  let n = list.length(ema_values)
  case n < 2 {
    True -> 0.0
    False -> {
      let tail = list.drop(ema_values, int.max(n - 4, 0))
      let diffs =
        list.window_by_2(tail)
        |> list.map(fn(p) { p.1 -. p.0 })
      case list.length(diffs) {
        0 -> 0.0
        k -> list.fold(diffs, 0.0, fn(a, d) { a +. d }) /. int.to_float(k)
      }
    }
  }
}

/// Detect qualitative trend from the last 3 values of `series`.
fn detect_trend(series: List(Float)) -> String {
  case list.length(series) < 2 {
    True -> "stable"
    False -> {
      let tail = list.drop(series, int.max(list.length(series) - 3, 0))
      let first = list.first(tail) |> unwrap_float(0.0)
      let last = list.last(tail) |> unwrap_float(0.0)
      let avg = { first +. last } /. 2.0
      let threshold = case avg <. 1.0e-10 {
        True -> 1.0e-10
        False -> avg *. 0.01
      }
      case last -. first >. threshold {
        True -> "increasing"
        False ->
          case first -. last >. threshold {
            True -> "decreasing"
            False -> "stable"
          }
      }
    }
  }
}

fn recommend_action_from_predicted(predicted: Float) -> String {
  case predicted >. 0.8 {
    True -> "scale_up"
    False ->
      case predicted >. 0.6 {
        True -> "optimize"
        False -> "no_action"
      }
  }
}

fn plan_health_from_list(forecasts: List(ResourceForecast)) -> Float {
  let total = list.length(forecasts)
  case total {
    0 -> 1.0
    n -> {
      let needing =
        list.filter(forecasts, fn(f) { f.recommendation != "no_action" })
        |> list.length
      1.0 -. int.to_float(needing) /. int.to_float(n)
    }
  }
}

/// Clamp `x` to the closed interval [lo, hi].
fn clamp(x: Float, lo: Float, hi: Float) -> Float {
  case x <. lo {
    True -> lo
    False ->
      case x >. hi {
        True -> hi
        False -> x
      }
  }
}

/// Unwrap a Float Result, returning `default` on Error.
fn unwrap_float(r: Result(Float, e), default: Float) -> Float {
  case r {
    Ok(v) -> v
    Error(_) -> default
  }
}
