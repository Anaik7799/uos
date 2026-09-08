//// =============================================================================
//// [UOS-FRACTAL-FORECAST] Unified Fractal Forecasting & Predictive OODA Engine
//// =============================================================================
//// Transmuted and synthesized from VM-1 ZigVM (Stan, PHIA/NATO probability,
//// SEU, Brier calibration, Admiralty A1-F6) and VM-1 C3I (Kalman filter,
//// EMA capacity forecasting, Lyapunov drift, health calculus derivatives).
////
//// Zero-Muda Purity: Pure functional Gleam on BEAM (SC-MUDA-001)
//// Storage Safety: HARD_DENIED_SYSTEM_OS_SERIAL = "25503L801736" enforced
//// Contracts: SC-HIVE-DECISION-001, SC-HIVE-FORECAST-001, SC-HIVE-KPI-001
//// =============================================================================

import gleam/float
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/string

// -----------------------------------------------------------------------------
// 1. NATO / PHIA Estimative Probability Yardstick & Linguistic Scales
// -----------------------------------------------------------------------------

pub type NatoBand {
  RemoteChance
  HighlyUnlikely
  Unlikely
  RealisticPossibility
  Likely
  HighlyLikely
  AlmostCertain
  BufferZone(lower: String, upper: String, estimate: Float)
}

pub fn classify_probability(p: Float) -> String {
  case p {
    _ if p <. 0.0 -> "Invalid (<0.0)"
    _ if p <=. 0.05 -> "Remote chance (0-5%)"
    _ if p <. 0.1 ->
      "Buffer zone: Remote to Highly unlikely (~" <> format_percent(p) <> ")"
    _ if p <=. 0.2 -> "Highly unlikely (10-20%)"
    _ if p <. 0.25 ->
      "Buffer zone: Highly unlikely to Unlikely (~" <> format_percent(p) <> ")"
    _ if p <=. 0.35 -> "Unlikely (25-35%)"
    _ if p <. 0.4 ->
      "Buffer zone: Unlikely to Realistic possibility (~"
      <> format_percent(p)
      <> ")"
    _ if p <=. 0.5 -> "Realistic possibility (40-50%)"
    _ if p <. 0.55 ->
      "Buffer zone: Realistic possibility to Likely (~"
      <> format_percent(p)
      <> ")"
    _ if p <=. 0.75 -> "Likely / probably (55-75%)"
    _ if p <. 0.8 ->
      "Buffer zone: Likely to Highly likely (~" <> format_percent(p) <> ")"
    _ if p <=. 0.9 -> "Highly likely (80-90%)"
    _ if p <. 0.95 ->
      "Buffer zone: Highly likely to Almost certain (~"
      <> format_percent(p)
      <> ")"
    _ if p <=. 1.0 -> "Almost certain (95-100%)"
    _ -> "Invalid (>1.0)"
  }
}

/// Band a layer forecast's risk score.
///
/// A risk score here is a normalized distance between a predicted metric and
/// its threshold — not the probability of a proposition. The NATO/PHIA yardstick
/// (`classify_probability`) is for stated likelihoods, and feeding a threshold
/// gap or a sample count into it printed "Almost certain (95-100%)" for values
/// that were never probabilities. Risk gets its own vocabulary so a reader
/// cannot mistake one for the other.
pub fn classify_risk(risk: Float) -> String {
  case risk {
    _ if risk <. 0.0 -> "Invalid risk (<0.0)"
    _ if risk <=. 0.0 -> "No risk detected (threshold not approached)"
    _ if risk <=. 0.15 -> "Low risk (0-15% of threshold margin consumed)"
    _ if risk <=. 0.35 -> "Moderate risk (15-35%)"
    _ if risk <=. 0.6 -> "Elevated risk (35-60%)"
    _ if risk <=. 0.85 -> "High risk (60-85%)"
    _ if risk <=. 1.0 -> "Severe risk (85-100%)"
    _ -> "Invalid risk (>1.0)"
  }
}

pub fn to_nato_band(p: Float) -> NatoBand {
  case p {
    _ if p <=. 0.05 -> RemoteChance
    _ if p <. 0.1 -> BufferZone("Remote chance", "Highly unlikely", p)
    _ if p <=. 0.2 -> HighlyUnlikely
    _ if p <. 0.25 -> BufferZone("Highly unlikely", "Unlikely", p)
    _ if p <=. 0.35 -> Unlikely
    _ if p <. 0.4 -> BufferZone("Unlikely", "Realistic possibility", p)
    _ if p <=. 0.5 -> RealisticPossibility
    _ if p <. 0.55 -> BufferZone("Realistic possibility", "Likely", p)
    _ if p <=. 0.75 -> Likely
    _ if p <. 0.8 -> BufferZone("Likely", "Highly likely", p)
    _ if p <=. 0.9 -> HighlyLikely
    _ if p <. 0.95 -> BufferZone("Highly likely", "Almost certain", p)
    _ -> AlmostCertain
  }
}

pub fn nato_band_rank(band: NatoBand) -> Int {
  case band {
    RemoteChance -> 0
    BufferZone(_, _, _) -> 1
    HighlyUnlikely -> 2
    Unlikely -> 3
    RealisticPossibility -> 4
    Likely -> 5
    HighlyLikely -> 6
    AlmostCertain -> 7
  }
}

// -----------------------------------------------------------------------------
// 2. Subjective Expected Utility (SEU) & Break-Even Analysis
// -----------------------------------------------------------------------------

pub fn calculate_seu(p: Float, benefit: Float, cost: Float) -> Float {
  let bounded_p = clamp_float(p, 0.0, 1.0)
  { bounded_p *. benefit } -. { { 1.0 -. bounded_p } *. cost }
}

pub fn breakeven_probability(benefit: Float, cost: Float) -> Float {
  let total = benefit +. cost
  case total <=. 0.0 {
    True -> 0.5
    False -> cost /. total
  }
}

// -----------------------------------------------------------------------------
// 3. Kalman State Estimator & Innovation Residuals
// -----------------------------------------------------------------------------

pub type Kalman1D {
  Kalman1D(
    estimate: Float,
    error_covariance: Float,
    process_noise: Float,
    measurement_noise: Float,
  )
}

pub fn init_kalman(
  initial_estimate: Float,
  initial_error: Float,
  q: Float,
  r: Float,
) -> Kalman1D {
  Kalman1D(
    estimate: initial_estimate,
    error_covariance: initial_error,
    process_noise: q,
    measurement_noise: r,
  )
}

pub fn kalman_predict_step(state: Kalman1D) -> #(Float, Float) {
  let predicted_estimate = state.estimate
  let predicted_cov = state.error_covariance +. state.process_noise
  #(predicted_estimate, predicted_cov)
}

pub fn kalman_update_step(
  state: Kalman1D,
  measurement: Float,
) -> #(Kalman1D, Float, Float) {
  let #(pred_x, pred_p) = kalman_predict_step(state)
  let innovation = measurement -. pred_x
  let innovation_cov = pred_p +. state.measurement_noise
  let kalman_gain = case innovation_cov >. 0.0 {
    True -> pred_p /. innovation_cov
    False -> 0.0
  }
  let new_estimate = pred_x +. kalman_gain *. innovation
  let new_cov = { 1.0 -. kalman_gain } *. pred_p

  let next_state =
    Kalman1D(
      estimate: new_estimate,
      error_covariance: new_cov,
      process_noise: state.process_noise,
      measurement_noise: state.measurement_noise,
    )

  let normalized_residual_sq = case innovation_cov >. 0.0 {
    True -> { innovation *. innovation } /. innovation_cov
    False -> 0.0
  }

  #(next_state, innovation, normalized_residual_sq)
}

// -----------------------------------------------------------------------------
// 4. Bayesian EMA & Trend Horizon Extrapolator
// -----------------------------------------------------------------------------

pub type EmaForecast {
  EmaForecast(
    current_val: Float,
    predicted_val: Float,
    horizon_steps: Int,
    lower_bound_90: Float,
    upper_bound_90: Float,
    drift_rate: Float,
    sample_weight: Float,
  )
}

pub fn forecast_series_ema(
  history: List(Float),
  alpha: Float,
  horizon: Int,
) -> EmaForecast {
  case history {
    [] -> EmaForecast(0.0, 0.0, horizon, 0.0, 0.0, 0.0, 0.0)
    [single] -> EmaForecast(single, single, horizon, single, single, 0.0, 0.3)
    [first, second, ..rest] -> {
      let n = list.length([first, second, ..rest])
      let ema = calculate_ema([first, second, ..rest], alpha)
      let drift = calculate_drift([first, second, ..rest])
      let h_f = int.to_float(horizon)
      let predicted = ema +. drift *. h_f
      let variance = calculate_variance([first, second, ..rest], ema)
      let std_dev = case float.square_root(variance) {
        Ok(v) -> v
        Error(_) -> 0.01
      }
      let margin_90 = 1.645 *. std_dev *. { 1.0 +. 0.1 *. h_f }
      let sample_weight = clamp_float(int.to_float(n) /. 10.0, 0.2, 0.95)

      EmaForecast(
        current_val: ema,
        predicted_val: predicted,
        horizon_steps: horizon,
        lower_bound_90: predicted -. margin_90,
        upper_bound_90: predicted +. margin_90,
        drift_rate: drift,
        sample_weight: sample_weight,
      )
    }
  }
}

// -----------------------------------------------------------------------------
// 5. Lyapunov Dynamical Stability Predictor
// -----------------------------------------------------------------------------

pub type StabilityVerdict {
  StableConverging(decay_rate: Float)
  MarginallyStable(variance: Float)
  UnstableDiverging(growth_rate: Float)
  /// Fewer than two observations: no drift can be computed. Distinct from
  /// `MarginallyStable`, which is a measured verdict about a real series.
  Undetermined(reason: String)
}

pub fn evaluate_lyapunov_drift(
  series: List(Float),
  target: Float,
) -> StabilityVerdict {
  case series {
    [] | [_] ->
      Undetermined("fewer than two observations; no energy drift to measure")
    _ -> {
      let energy =
        list.map(series, fn(x) { 0.5 *. { x -. target } *. { x -. target } })
      let energy_diffs = list.window_by_2(energy)
      let drift_sum =
        list.fold(energy_diffs, 0.0, fn(acc, pair) {
          let #(e_prev, e_curr) = pair
          acc +. { e_curr -. e_prev }
        })
      let count = int.to_float(list.length(energy_diffs))
      let mean_drift = case count >. 0.0 {
        True -> drift_sum /. count
        False -> 0.0
      }
      // The verdict must not depend on the unit of `series`. Energy is
      // 0.5·(x−target)², so an absolute threshold on its drift calls a series
      // measured in millions "marginally stable" at drifts that are enormous,
      // and a series measured in fractions "diverging" at noise. Compare the
      // drift with the scale of the energy it moves through instead.
      let scale =
        list.fold(energy, 0.0, fn(acc, e) { acc +. float.absolute_value(e) })
        /. int.to_float(list.length(energy))
      // Energies are non-negative, so a zero mean energy means every point sits
      // exactly on the target: stationary, not drifting. Any fixed epsilon here
      // would reintroduce the scale dependence this normalization removes — a
      // series in units of 1e-6 has energies around 1e-12 and would be silently
      // called marginal.
      let relative = case scale >. 0.0 {
        True -> mean_drift /. scale
        False -> 0.0
      }

      case relative <. -0.001 {
        True -> StableConverging(float.absolute_value(mean_drift))
        False ->
          case relative >. 0.001 {
            True -> UnstableDiverging(mean_drift)
            False -> MarginallyStable(mean_drift)
          }
      }
    }
  }
}

// -----------------------------------------------------------------------------
// 6. Brier Calibration Ledger & Scoring
// -----------------------------------------------------------------------------

pub type BrierRecord {
  BrierRecord(
    prediction_id: String,
    predicted_probability: Float,
    observed_outcome: Bool,
  )
}

/// Calibration carries its denominator, because a Brier score without one is
/// not a measurement.
///
/// The previous API returned `0.0` for an empty ledger and `is_brier_calibrated`
/// then reported `True`: a system that had never resolved a single forecast
/// claimed perfect calibration. That is the H-1 hazard (green while unmeasured)
/// and it contradicts SC-HIVE-KPI-001, which states that a zero denominator is
/// unavailable, not perfect performance.
pub type Calibration {
  /// Brier score over `samples` resolved, precommitted forecasts.
  Calibrated(score: Float, samples: Int)
  /// No resolved forecast to score. Never comparable to a score.
  Unavailable(reason: String)
}

/// Mean squared error between each precommitted probability and its observed
/// outcome, over resolved forecasts only. Lower is better; 0.25 is the score of
/// always predicting 0.5, so it is the line above which a forecaster carries no
/// information.
pub fn brier_calibration(records: List(BrierRecord)) -> Calibration {
  case list.length(records) {
    0 -> Unavailable("no resolved forecast has been scored")
    count -> {
      let total_squared_error =
        list.fold(records, 0.0, fn(acc, rec) {
          let outcome_float = case rec.observed_outcome {
            True -> 1.0
            False -> 0.0
          }
          let err = rec.predicted_probability -. outcome_float
          acc +. { err *. err }
        })
      Calibrated(total_squared_error /. int.to_float(count), count)
    }
  }
}

/// `Unavailable` is never calibrated: absence of evidence is not evidence of
/// calibration.
pub fn is_brier_calibrated(calibration: Calibration) -> Bool {
  case calibration {
    Calibrated(score, _) -> score <=. 0.25
    Unavailable(_) -> False
  }
}

/// Render a calibration for a report or an endpoint without inventing a number.
pub fn calibration_json(calibration: Calibration) -> Json {
  case calibration {
    Calibrated(score, samples) ->
      json.object([
        #("brier_score", json.float(score)),
        #("samples", json.int(samples)),
        #("calibrated", json.bool(score <=. 0.25)),
        #("evidence_grade", json.string("Measured")),
      ])
    Unavailable(reason) ->
      json.object([
        #("brier_score", json.null()),
        #("samples", json.int(0)),
        #("calibrated", json.bool(False)),
        #("evidence_grade", json.string("Unknown")),
        #("reason", json.string(reason)),
      ])
  }
}

// -----------------------------------------------------------------------------
// 7. Fractal Cross-Layer Forecast Envelope (L0 .. L9)
// -----------------------------------------------------------------------------

pub type FractalLayer {
  LayerL0Constitutional
  LayerL1Atomic
  LayerL2Component
  LayerL3Transaction
  LayerL4System
  LayerL5Cognitive
  LayerL6Ecosystem
  LayerL7Federation
  LayerL8Mutation
  LayerL9Verification
}

pub fn fractal_layer_to_string(layer: FractalLayer) -> String {
  case layer {
    LayerL0Constitutional -> "L0_Constitutional"
    LayerL1Atomic -> "L1_Atomic"
    LayerL2Component -> "L2_Component"
    LayerL3Transaction -> "L3_Transaction"
    LayerL4System -> "L4_System"
    LayerL5Cognitive -> "L5_Cognitive"
    LayerL6Ecosystem -> "L6_Ecosystem"
    LayerL7Federation -> "L7_Federation"
    LayerL8Mutation -> "L8_Mutation"
    LayerL9Verification -> "L9_Verification"
  }
}

pub type LayerForecast {
  LayerForecast(
    layer: FractalLayer,
    metric_name: String,
    current_value: Float,
    predicted_value: Float,
    horizon_seconds: Int,
    credible_lower: Float,
    credible_upper: Float,
    sample_weight: Float,
    risk_band: String,
    risk_score: Float,
    recommendation: String,
  )
}

pub fn predict_l0_constitutional(
  health_history: List(Float),
  horizon_s: Int,
) -> LayerForecast {
  let forecast = forecast_series_ema(health_history, 0.3, horizon_s)
  let risk = case forecast.predicted_val <. 0.7 {
    True -> clamp_float({ 0.7 -. forecast.predicted_val } /. 0.7, 0.0, 1.0)
    False -> 0.0
  }
  let rec = case risk >. 0.3 {
    True -> "EmergencyHalt: Invariant breach predicted within horizon"
    False -> "Nominal: Constitutional invariants preserved"
  }
  LayerForecast(
    layer: LayerL0Constitutional,
    metric_name: "constitutional_health",
    current_value: forecast.current_val,
    predicted_value: forecast.predicted_val,
    horizon_seconds: horizon_s,
    credible_lower: forecast.lower_bound_90,
    credible_upper: forecast.upper_bound_90,
    sample_weight: forecast.sample_weight,
    risk_band: classify_risk(risk),
    risk_score: risk,
    recommendation: rec,
  )
}

pub fn predict_l1_atomic(
  telemetry_stream: List(Float),
  horizon_s: Int,
) -> LayerForecast {
  let forecast = forecast_series_ema(telemetry_stream, 0.4, horizon_s)
  let stability = evaluate_lyapunov_drift(telemetry_stream, 1.0)
  let risk = case stability {
    UnstableDiverging(rate) -> clamp_float(rate *. 2.0, 0.0, 1.0)
    _ -> 0.05
  }
  let rec = case risk >. 0.2 {
    True -> "FilterRecalibrate: Atomic sensor variance diverging"
    False -> "Nominal: Telemetry stream predictable"
  }
  LayerForecast(
    layer: LayerL1Atomic,
    metric_name: "telemetry_signal",
    current_value: forecast.current_val,
    predicted_value: forecast.predicted_val,
    horizon_seconds: horizon_s,
    credible_lower: forecast.lower_bound_90,
    credible_upper: forecast.upper_bound_90,
    sample_weight: forecast.sample_weight,
    risk_band: classify_risk(risk),
    risk_score: risk,
    recommendation: rec,
  )
}

pub fn predict_l2_component(
  resource_usage_history: List(Float),
  horizon_s: Int,
) -> LayerForecast {
  let forecast = forecast_series_ema(resource_usage_history, 0.25, horizon_s)
  let risk = case forecast.predicted_val >. 0.85 {
    True -> clamp_float({ forecast.predicted_val -. 0.85 } /. 0.15, 0.0, 1.0)
    False -> 0.0
  }
  let rec = case forecast.predicted_val >. 0.8 {
    True -> "ScaleUp: Resource exhaustion predicted before horizon expiry"
    False ->
      case forecast.predicted_val <. 0.3 {
        True -> "ScaleDown: Resource underutilization predicted"
        False -> "NoAction: Resource capacity balanced"
      }
  }
  LayerForecast(
    layer: LayerL2Component,
    metric_name: "resource_utilization",
    current_value: forecast.current_val,
    predicted_value: forecast.predicted_val,
    horizon_seconds: horizon_s,
    credible_lower: forecast.lower_bound_90,
    credible_upper: forecast.upper_bound_90,
    sample_weight: forecast.sample_weight,
    risk_band: classify_risk(risk),
    risk_score: risk,
    recommendation: rec,
  )
}

pub fn predict_l3_transaction(
  contention_history: List(Float),
  horizon_s: Int,
) -> LayerForecast {
  let forecast = forecast_series_ema(contention_history, 0.3, horizon_s)
  let risk = clamp_float(forecast.predicted_val, 0.0, 1.0)
  let rec = case risk >. 0.5 {
    True -> "ExtendLeaseEpoch: High transaction contention predicted"
    False -> "Nominal: Low lease collision probability"
  }
  LayerForecast(
    layer: LayerL3Transaction,
    metric_name: "lease_contention",
    current_value: forecast.current_val,
    predicted_value: forecast.predicted_val,
    horizon_seconds: horizon_s,
    credible_lower: forecast.lower_bound_90,
    credible_upper: forecast.upper_bound_90,
    sample_weight: forecast.sample_weight,
    risk_band: classify_risk(risk),
    risk_score: risk,
    recommendation: rec,
  )
}

pub fn predict_l4_system(
  error_rate_history: List(Float),
  horizon_s: Int,
) -> LayerForecast {
  let forecast = forecast_series_ema(error_rate_history, 0.35, horizon_s)
  let risk = clamp_float(forecast.predicted_val *. 1.5, 0.0, 1.0)
  let rec = case risk >. 0.25 {
    True -> "PreemptiveRestart: Container MTBF breach predicted"
    False -> "Nominal: System processes healthy"
  }
  LayerForecast(
    layer: LayerL4System,
    metric_name: "system_mtbf_risk",
    current_value: forecast.current_val,
    predicted_value: forecast.predicted_val,
    horizon_seconds: horizon_s,
    credible_lower: forecast.lower_bound_90,
    credible_upper: forecast.upper_bound_90,
    sample_weight: forecast.sample_weight,
    risk_band: classify_risk(risk),
    risk_score: risk,
    recommendation: rec,
  )
}

pub fn predict_l5_cognitive(
  fuel_usage_history: List(Float),
  horizon_s: Int,
) -> LayerForecast {
  let forecast = forecast_series_ema(fuel_usage_history, 0.3, horizon_s)
  let risk = case forecast.predicted_val >. 0.9 {
    True -> 0.8
    False -> 0.1
  }
  let rec = case risk >. 0.5 {
    True -> "CompactContext: Agent fuel budget near exhaustion"
    False -> "Nominal: OODA cognition within budget"
  }
  LayerForecast(
    layer: LayerL5Cognitive,
    metric_name: "cognitive_fuel",
    current_value: forecast.current_val,
    predicted_value: forecast.predicted_val,
    horizon_seconds: horizon_s,
    credible_lower: forecast.lower_bound_90,
    credible_upper: forecast.upper_bound_90,
    sample_weight: forecast.sample_weight,
    risk_band: classify_risk(risk),
    risk_score: risk,
    recommendation: rec,
  )
}

pub fn predict_l6_ecosystem(
  consensus_history: List(Float),
  horizon_s: Int,
) -> LayerForecast {
  let forecast = forecast_series_ema(consensus_history, 0.2, horizon_s)
  let risk = case forecast.predicted_val <. 0.67 {
    True -> clamp_float({ 0.67 -. forecast.predicted_val } /. 0.67, 0.0, 1.0)
    False -> 0.0
  }
  let rec = case risk >. 0.2 {
    True -> "QuorumRebalance: Swarm consensus divergence predicted"
    False -> "Nominal: Multi-agent consensus stable"
  }
  LayerForecast(
    layer: LayerL6Ecosystem,
    metric_name: "swarm_consensus",
    current_value: forecast.current_val,
    predicted_value: forecast.predicted_val,
    horizon_seconds: horizon_s,
    credible_lower: forecast.lower_bound_90,
    credible_upper: forecast.upper_bound_90,
    sample_weight: forecast.sample_weight,
    risk_band: classify_risk(risk),
    risk_score: risk,
    recommendation: rec,
  )
}

pub fn predict_l7_federation(
  replication_lag_history: List(Float),
  horizon_s: Int,
) -> LayerForecast {
  let forecast = forecast_series_ema(replication_lag_history, 0.25, horizon_s)
  let risk = case forecast.predicted_val >. 5.0 {
    True -> 0.75
    False -> 0.05
  }
  let rec = case risk >. 0.5 {
    True -> "EnterSplitBrainShield: Cross-cluster partition predicted"
    False -> "Nominal: Federation replication synced"
  }
  LayerForecast(
    layer: LayerL7Federation,
    metric_name: "replication_lag_s",
    current_value: forecast.current_val,
    predicted_value: forecast.predicted_val,
    horizon_seconds: horizon_s,
    credible_lower: forecast.lower_bound_90,
    credible_upper: forecast.upper_bound_90,
    sample_weight: forecast.sample_weight,
    risk_band: classify_risk(risk),
    risk_score: risk,
    recommendation: rec,
  )
}

pub fn predict_l8_mutation(
  mutation_kill_history: List(Float),
  horizon_s: Int,
) -> LayerForecast {
  let forecast = forecast_series_ema(mutation_kill_history, 0.2, horizon_s)
  let risk = case forecast.predicted_val <. 0.9 {
    True -> clamp_float({ 0.9 -. forecast.predicted_val } /. 0.9, 0.0, 1.0)
    False -> 0.0
  }
  let rec = case risk >. 0.1 {
    True -> "EnforceMutationBattery: Predicted test suite mutation leaks"
    False -> "Nominal: Suite mutation kill rate adequate"
  }
  LayerForecast(
    layer: LayerL8Mutation,
    metric_name: "mutation_kill_rate",
    current_value: forecast.current_val,
    predicted_value: forecast.predicted_val,
    horizon_seconds: horizon_s,
    credible_lower: forecast.lower_bound_90,
    credible_upper: forecast.upper_bound_90,
    sample_weight: forecast.sample_weight,
    risk_band: classify_risk(risk),
    risk_score: risk,
    recommendation: rec,
  )
}

pub fn predict_l9_verification(
  solver_time_history: List(Float),
  horizon_s: Int,
) -> LayerForecast {
  let forecast = forecast_series_ema(solver_time_history, 0.3, horizon_s)
  let risk = case forecast.predicted_val >. 10.0 {
    True -> 0.7
    False -> 0.05
  }
  let rec = case risk >. 0.5 {
    True -> "SimplifyAxioms: SMT solver timeout predicted"
    False -> "Nominal: Formal proof verification within bounds"
  }
  LayerForecast(
    layer: LayerL9Verification,
    metric_name: "solver_duration_s",
    current_value: forecast.current_val,
    predicted_value: forecast.predicted_val,
    horizon_seconds: horizon_s,
    credible_lower: forecast.lower_bound_90,
    credible_upper: forecast.upper_bound_90,
    sample_weight: forecast.sample_weight,
    risk_band: classify_risk(risk),
    risk_score: risk,
    recommendation: rec,
  )
}

// -----------------------------------------------------------------------------
// 8. 7-Stage Predictive OODAVR Control Loop (POODAVR)
// -----------------------------------------------------------------------------

pub type PoodavrStage {
  PoodavrObserve
  PoodavrOrient
  PoodavrPredict
  PoodavrDecide
  PoodavrAct
  PoodavrVerify
  PoodavrRecord
}

pub fn poodavr_stage_to_string(stage: PoodavrStage) -> String {
  case stage {
    PoodavrObserve -> "OBSERVE"
    PoodavrOrient -> "ORIENT"
    PoodavrPredict -> "PREDICT"
    PoodavrDecide -> "DECIDE"
    PoodavrAct -> "ACT"
    PoodavrVerify -> "VERIFY"
    PoodavrRecord -> "RECORD"
  }
}

pub type PredictiveOodaCycle {
  PredictiveOodaCycle(
    cycle_id: String,
    stage: PoodavrStage,
    current_forecast: LayerForecast,
    seu_score: Float,
    action_decision: String,
    mitigation_scheduled: Bool,
  )
}

pub fn run_predictive_ooda_evaluation(
  cycle_id: String,
  forecast: LayerForecast,
  action_name: String,
  benefit: Float,
  cost: Float,
) -> PredictiveOodaCycle {
  let probability_success = clamp_float(1.0 -. forecast.risk_score, 0.0, 1.0)
  let seu = calculate_seu(probability_success, benefit, cost)

  let #(decision, mitigate) = case seu >. 0.0 && forecast.risk_score <=. 0.2 {
    True -> #(action_name, False)
    False ->
      case forecast.risk_score >. 0.5 {
        True -> #(forecast.recommendation, True)
        False -> #("DeferAction: SEU negative or risk uncompensated", False)
      }
  }

  PredictiveOodaCycle(
    cycle_id: cycle_id,
    stage: PoodavrDecide,
    current_forecast: forecast,
    seu_score: seu,
    action_decision: decision,
    mitigation_scheduled: mitigate,
  )
}

// -----------------------------------------------------------------------------
// 9. SDLC & SRE Standard Operating Procedures (SOPs)
// -----------------------------------------------------------------------------

pub type SreSopVerdict {
  SreSopTriggered(sop_id: String, action: String, target_horizon: Int)
  SreSopBypassed(sop_id: String, reason: String)
}

pub fn evaluate_sre_capacity_sop(forecast: LayerForecast) -> SreSopVerdict {
  // SOP-SRE-01: Proactive Resource Preemption
  case forecast.predicted_value >. 0.8 && forecast.sample_weight >=. 0.7 {
    True ->
      SreSopTriggered(
        "SOP-SRE-01",
        "PreemptiveAutoscale: Scale up capacity before exhaustion horizon",
        forecast.horizon_seconds,
      )
    False ->
      SreSopBypassed("SOP-SRE-01", "Resource trajectory within nominal bounds")
  }
}

pub fn evaluate_sre_lyapunov_sop(stability: StabilityVerdict) -> SreSopVerdict {
  // SOP-SRE-02: Predictive Circuit Tripping
  case stability {
    UnstableDiverging(growth) if growth >. 0.05 ->
      SreSopTriggered(
        "SOP-SRE-02",
        "TripPrajnaBreaker: Divergent positive Lyapunov drift detected",
        30,
      )
    _ -> SreSopBypassed("SOP-SRE-02", "Dynamical system converging or neutral")
  }
}

pub type SdlcPreflightVerdict {
  SdlcPreflightPass(gate: String, forecast_summary: String)
  SdlcPreflightBlock(gate: String, reason: String)
}

pub fn evaluate_sdlc_mutation_sop(
  forecast: LayerForecast,
) -> SdlcPreflightVerdict {
  // SOP-SDLC-01: Pre-Commit Mutation Adequacy Prediction
  case forecast.predicted_value >=. 0.9 {
    True ->
      SdlcPreflightPass(
        "G-MUTATION-PREDICT",
        "Predicted kill rate >= 90% ("
          <> format_percent(forecast.predicted_value)
          <> ")",
      )
    False ->
      SdlcPreflightBlock(
        "G-MUTATION-PREDICT",
        "Predicted kill rate below 90% threshold ("
          <> format_percent(forecast.predicted_value)
          <> ")",
      )
  }
}

// -----------------------------------------------------------------------------
// 10. Agentic Decision-Making Certificate & Preflight Gate
// -----------------------------------------------------------------------------

pub type AgenticPreflightCertificate {
  PreflightApproved(
    certificate_id: String,
    actor: String,
    action: String,
    seu_score: Float,
    confidence_rating: String,
  )
  PreflightVetoed(
    certificate_id: String,
    actor: String,
    action: String,
    rejection_reason: String,
    risk_score: Float,
  )
}

pub fn verify_agentic_preflight(
  actor: String,
  action: String,
  forecast: LayerForecast,
  benefit: Float,
  cost: Float,
) -> AgenticPreflightCertificate {
  let cert_id =
    "CERT-PRED-"
    <> string.slice(actor, 0, 4)
    <> "-"
    <> string.slice(action, 0, 6)
  // `p` is a derived success proxy (one minus the normalized threshold gap),
  // not an observed frequency and not a calibrated probability. It is usable
  // for ranking through SEU; it must never be reported as an estimative
  // probability, so the certificate states where it came from.
  let p = clamp_float(1.0 -. forecast.risk_score, 0.0, 1.0)
  let seu = calculate_seu(p, benefit, cost)

  case
    forecast.risk_score <=. 0.15 && forecast.sample_weight >=. 0.7 && seu >. 0.0
  {
    True ->
      PreflightApproved(
        certificate_id: cert_id,
        actor: actor,
        action: action,
        seu_score: seu,
        confidence_rating: "derived success proxy 1-risk="
          <> format_percent(p)
          <> " (uncalibrated; "
          <> format_percent(forecast.sample_weight)
          <> " sample weight)",
      )
    False -> {
      let reason = case forecast.risk_score >. 0.15 {
        True ->
          "Excessive predicted risk ("
          <> format_percent(forecast.risk_score)
          <> " > 15%)"
        False ->
          case forecast.sample_weight <. 0.7 {
            True ->
              "Insufficient observations (sample weight < 0.7: fewer than 7 points in the series)"
            False -> "Negative or uncompensated Subjective Expected Utility"
          }
      }
      PreflightVetoed(
        certificate_id: cert_id,
        actor: actor,
        action: action,
        rejection_reason: reason,
        risk_score: forecast.risk_score,
      )
    }
  }
}

// -----------------------------------------------------------------------------
// Helper Pure Functions
// -----------------------------------------------------------------------------

fn calculate_ema(values: List(Float), alpha: Float) -> Float {
  case values {
    [] -> 0.0
    [x, ..xs] ->
      list.fold(xs, x, fn(prev_ema, val) {
        { alpha *. val } +. { { 1.0 -. alpha } *. prev_ema }
      })
  }
}

fn calculate_drift(values: List(Float)) -> Float {
  case values {
    [] | [_] -> 0.0
    _ -> {
      let diffs =
        list.window_by_2(values)
        |> list.map(fn(pair) { pair.1 -. pair.0 })
      let sum = list.fold(diffs, 0.0, fn(acc, d) { acc +. d })
      let count = int.to_float(list.length(diffs))
      case count >. 0.0 {
        True -> sum /. count
        False -> 0.0
      }
    }
  }
}

fn calculate_variance(values: List(Float), mean: Float) -> Float {
  let count = list.length(values)
  case count <= 1 {
    True -> 0.0
    False -> {
      let sum_sq =
        list.fold(values, 0.0, fn(acc, v) {
          let diff = v -. mean
          acc +. { diff *. diff }
        })
      sum_sq /. int.to_float(count - 1)
    }
  }
}

fn clamp_float(val: Float, min: Float, max: Float) -> Float {
  case val <. min {
    True -> min
    False ->
      case val >. max {
        True -> max
        False -> val
      }
  }
}

fn format_percent(val: Float) -> String {
  let pct = int.to_string(float.round(val *. 100.0))
  pct <> "%"
}

// -----------------------------------------------------------------------------
// 11. Full 10-Layer Forecast Aggregation & JSON Serialization
// -----------------------------------------------------------------------------

pub fn predict_all_layers(horizon_seconds: Int) -> List(LayerForecast) {
  [
    predict_l0_constitutional(
      [0.98, 0.99, 0.97, 0.98, 0.99, 0.98, 0.99, 0.98],
      horizon_seconds,
    ),
    predict_l1_atomic(
      [0.12, 0.14, 0.11, 0.13, 0.12, 0.15, 0.13, 0.12],
      horizon_seconds,
    ),
    predict_l2_component(
      [0.55, 0.58, 0.56, 0.6, 0.62, 0.61, 0.63, 0.62],
      horizon_seconds,
    ),
    predict_l3_transaction(
      [0.05, 0.04, 0.06, 0.05, 0.04, 0.05, 0.05, 0.04],
      horizon_seconds,
    ),
    predict_l4_system(
      [0.02, 0.01, 0.03, 0.02, 0.01, 0.02, 0.02, 0.01],
      horizon_seconds,
    ),
    predict_l5_cognitive(
      [0.45, 0.48, 0.5, 0.47, 0.52, 0.49, 0.51, 0.5],
      horizon_seconds,
    ),
    predict_l6_ecosystem(
      [0.15, 0.18, 0.16, 0.17, 0.19, 0.16, 0.18, 0.17],
      horizon_seconds,
    ),
    predict_l7_federation(
      [0.08, 0.09, 0.07, 0.08, 0.1, 0.09, 0.08, 0.09],
      horizon_seconds,
    ),
    predict_l8_mutation(
      [0.94, 0.95, 0.93, 0.96, 0.94, 0.95, 0.96, 0.95],
      horizon_seconds,
    ),
    predict_l9_verification(
      [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0],
      horizon_seconds,
    ),
  ]
}

pub fn layer_forecast_to_json(forecast: LayerForecast) -> json.Json {
  json.object([
    #("layer", json.string(fractal_layer_to_string(forecast.layer))),
    #("metric_name", json.string(forecast.metric_name)),
    #("current_value", json.float(forecast.current_value)),
    #("predicted_value", json.float(forecast.predicted_value)),
    #("horizon_seconds", json.int(forecast.horizon_seconds)),
    #("credible_lower", json.float(forecast.credible_lower)),
    #("credible_upper", json.float(forecast.credible_upper)),
    #("sample_weight", json.float(forecast.sample_weight)),
    #("risk_band", json.string(forecast.risk_band)),
    #("risk_score", json.float(forecast.risk_score)),
    #("recommendation", json.string(forecast.recommendation)),
  ])
}

pub fn all_layers_forecast_json() -> json.Json {
  let forecasts = predict_all_layers(60)
  json.object([
    #("status", json.string("ok")),
    #("engine", json.string("UOS-FRACTAL-FORECAST")),
    #("horizon_seconds", json.int(60)),
    #("layer_count", json.int(list.length(forecasts))),
    #("forecasts", json.array(forecasts, layer_forecast_to_json)),
  ])
}

pub fn preflight_certificate_to_json(
  cert: AgenticPreflightCertificate,
) -> json.Json {
  case cert {
    PreflightApproved(id, actor, action, seu, rating) ->
      json.object([
        #("status", json.string("approved")),
        #("certificate_id", json.string(id)),
        #("actor", json.string(actor)),
        #("action", json.string(action)),
        #("seu_score", json.float(seu)),
        #("confidence_rating", json.string(rating)),
        #("gate", json.string("PASS")),
      ])
    PreflightVetoed(id, actor, action, reason, risk) ->
      json.object([
        #("status", json.string("vetoed")),
        #("certificate_id", json.string(id)),
        #("actor", json.string(actor)),
        #("action", json.string(action)),
        #("rejection_reason", json.string(reason)),
        #("risk_score", json.float(risk)),
        #("gate", json.string("BLOCKED")),
      ])
  }
}

/// Health of the forecasting tier as it can honestly be stated today
/// (evidence-truth check ETC-1, generated/20260907-1650-uos-evidence-truth-checks.json).
///
/// The ten layer predictors in this module exist and are unit-tested, but no live
/// telemetry is wired into them, so no prediction has been observed against reality.
/// Until that wiring exists this endpoint reports `UNKNOWN` with explicit zero
/// observation counts instead of constants that read as measurements. Every
/// field that would need an observation is `unrun` or `null`, never a number.
pub fn forecast_health_json() -> json.Json {
  json.object([
    #("status", json.string("UNKNOWN")),
    #("evidence_grade", json.string("Unknown")),
    #("predictors_implemented", json.int(10)),
    #("layers_observed", json.int(0)),
    #("prediction_coverage", json.string("0/10 layers observed")),
    #("kalman_state", json.string("unrun")),
    #("lyapunov_stability", json.string("unrun")),
    #("brier_calibration", json.null()),
    #("brier_samples", json.int(0)),
    #(
      "advisory",
      json.string(
        "Predictors implemented for L0-L9; no live telemetry is wired, so no forecast has been observed; treat as UNRUN per SYNC-10",
      ),
    ),
  ])
}
