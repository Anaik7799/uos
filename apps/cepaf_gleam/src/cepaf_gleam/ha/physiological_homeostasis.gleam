//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/physiological_homeostasis</module>
////     <lineage>Pure Gleam adaptation of Indrajaal.Adaptation.HomeostasisController & Cortex.Homeostasis</lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L2_HEALTH</layer>
////     <layer>L4_SYSTEM</layer>
////     <layer>L6_ECOSYSTEM</layer>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-HOM-001, SC-HOM-002, SC-HOM-003, SC-MATH-003, SC-SIL6-001</stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================
////
//// PHYSIOLOGICAL HOMEOSTASIS CONTROLLER
//// Maintains system equilibrium across multi-variable physiological setpoints:
//// 1. CPU Utilization (setpoint: 60.0%)
//// 2. Memory Utilization (setpoint: 70.0%)
//// 3. Request Latency (setpoint: 100.0 ms)
//// 4. Error Rate (setpoint: 0.5%)
////
//// Implements Ziegler-Nichols tuned PID with anti-windup clamping and stress classification.

import gleam/float
import gleam/list

// ---------------------------------------------------------------------------
// 1. Domain Types
// ---------------------------------------------------------------------------

pub type PhysiologicalVariable {
  CpuUtilization
  MemoryUtilization
  RequestLatency
  ErrorRate
}

pub fn variable_to_string(v: PhysiologicalVariable) -> String {
  case v {
    CpuUtilization -> "cpu_pct"
    MemoryUtilization -> "memory_pct"
    RequestLatency -> "latency_ms"
    ErrorRate -> "error_rate_pct"
  }
}

pub type StressLevel {
  StressLow
  StressOptimal
  StressHigh
  StressCritical
}

pub fn stress_to_string(s: StressLevel) -> String {
  case s {
    StressLow -> "LOW"
    StressOptimal -> "OPTIMAL"
    StressHigh -> "HIGH"
    StressCritical -> "CRITICAL"
  }
}

pub type StressTrend {
  TrendStable
  TrendRising
  TrendFalling
}

pub fn trend_to_string(t: StressTrend) -> String {
  case t {
    TrendStable -> "STABLE"
    TrendRising -> "RISING"
    TrendFalling -> "FALLING"
  }
}

pub type VariablePidState {
  VariablePidState(
    variable: PhysiologicalVariable,
    setpoint: Float,
    measurement: Float,
    error: Float,
    integral: Float,
    derivative: Float,
    control_signal: Float,
    kp: Float,
    ki: Float,
    kd: Float,
    stress: StressLevel,
  )
}

pub type PhysiologicalState {
  PhysiologicalState(
    variables: List(VariablePidState),
    composite_stress: Float,
    stress_trend: StressTrend,
    is_homeostatic: Bool,
    timestamp_us: Int,
  )
}

// ---------------------------------------------------------------------------
// 2. Default Setpoints & Tuning (SC-MATH-003: Ziegler-Nichols tuning)
// ---------------------------------------------------------------------------

const integral_clamp = 10.0

pub fn default_variables() -> List(VariablePidState) {
  [
    VariablePidState(
      variable: CpuUtilization,
      setpoint: 60.0,
      measurement: 45.0,
      error: -15.0,
      integral: 0.0,
      derivative: 0.0,
      control_signal: 0.0,
      kp: 0.6,
      ki: 0.01,
      kd: 0.05,
      stress: StressOptimal,
    ),
    VariablePidState(
      variable: MemoryUtilization,
      setpoint: 70.0,
      measurement: 52.0,
      error: -18.0,
      integral: 0.0,
      derivative: 0.0,
      control_signal: 0.0,
      kp: 0.6,
      ki: 0.01,
      kd: 0.05,
      stress: StressOptimal,
    ),
    VariablePidState(
      variable: RequestLatency,
      setpoint: 100.0,
      measurement: 48.0,
      error: -52.0,
      integral: 0.0,
      derivative: 0.0,
      control_signal: 0.0,
      kp: 0.4,
      ki: 0.005,
      kd: 0.02,
      stress: StressOptimal,
    ),
    VariablePidState(
      variable: ErrorRate,
      setpoint: 0.5,
      measurement: 0.02,
      error: -0.48,
      integral: 0.0,
      derivative: 0.0,
      control_signal: 0.0,
      kp: 1.5,
      ki: 0.05,
      kd: 0.1,
      stress: StressLow,
    ),
  ]
}

pub fn initial_physiological_state(now_us: Int) -> PhysiologicalState {
  let vars = default_variables()
  let composite = calculate_composite_stress(vars)
  PhysiologicalState(
    variables: vars,
    composite_stress: composite,
    stress_trend: TrendStable,
    is_homeostatic: True,
    timestamp_us: now_us,
  )
}

// ---------------------------------------------------------------------------
// 3. Controller Algorithms
// ---------------------------------------------------------------------------

pub fn classify_stress(variable: PhysiologicalVariable, measurement: Float) -> StressLevel {
  case variable {
    CpuUtilization ->
      case True {
        _ if measurement >. 90.0 -> StressCritical
        _ if measurement >. 75.0 -> StressHigh
        _ if measurement >=. 30.0 -> StressOptimal
        _ -> StressLow
      }
    MemoryUtilization ->
      case True {
        _ if measurement >. 90.0 -> StressCritical
        _ if measurement >. 80.0 -> StressHigh
        _ if measurement >=. 40.0 -> StressOptimal
        _ -> StressLow
      }
    RequestLatency ->
      case True {
        _ if measurement >. 500.0 -> StressCritical
        _ if measurement >. 200.0 -> StressHigh
        _ if measurement >=. 20.0 -> StressOptimal
        _ -> StressLow
      }
    ErrorRate ->
      case True {
        _ if measurement >. 5.0 -> StressCritical
        _ if measurement >. 1.5 -> StressHigh
        _ if measurement >=. 0.1 -> StressOptimal
        _ -> StressLow
      }
  }
}

pub fn step_variable(
  prev: VariablePidState,
  new_measurement: Float,
  dt_seconds: Float,
) -> VariablePidState {
  let dt = case dt_seconds <=. 0.0 {
    True -> 0.001
    False -> dt_seconds
  }

  // Error is positive when measurement exceeds setpoint
  let error = new_measurement -. prev.setpoint

  // Anti-windup integral clamping (SC-HOM-002)
  let raw_integral = prev.integral +. { error *. dt }
  let integral = case raw_integral >. integral_clamp {
    True -> integral_clamp
    False -> case raw_integral <. -0.0 -. integral_clamp {
      True -> -0.0 -. integral_clamp
      False -> raw_integral
    }
  }

  let derivative = { error -. prev.error } /. dt
  let control = { prev.kp *. error } +. { prev.ki *. integral } +. { prev.kd *. derivative }
  let stress = classify_stress(prev.variable, new_measurement)

  VariablePidState(
    ..prev,
    measurement: new_measurement,
    error: error,
    integral: integral,
    derivative: derivative,
    control_signal: control,
    stress: stress,
  )
}

pub fn calculate_composite_stress(variables: List(VariablePidState)) -> Float {
  let total_weight = 1.0
  // Weights: CPU 0.25, Memory 0.25, Latency 0.25, Error 0.25
  let weighted_sum =
    list.fold(variables, 0.0, fn(acc, v) {
      let norm = case v.variable {
        CpuUtilization -> v.measurement /. 100.0
        MemoryUtilization -> v.measurement /. 100.0
        RequestLatency -> float.min(1.0, v.measurement /. 500.0)
        ErrorRate -> float.min(1.0, v.measurement /. 5.0)
      }
      acc +. { norm *. 0.25 }
    })
  weighted_sum /. total_weight
}

pub fn update_physiological_telemetry(
  state: PhysiologicalState,
  measurements: List(#(PhysiologicalVariable, Float)),
  dt_seconds: Float,
  now_us: Int,
) -> PhysiologicalState {
  let updated_vars =
    list.map(state.variables, fn(v_state) {
      case list.find(measurements, fn(m) { m.0 == v_state.variable }) {
        Ok(#(_, val)) -> step_variable(v_state, val, dt_seconds)
        Error(_) -> v_state
      }
    })

  let new_composite = calculate_composite_stress(updated_vars)
  let delta = new_composite -. state.composite_stress
  let trend = case True {
    _ if delta >. 0.02 -> TrendRising
    _ if delta <. -0.02 -> TrendFalling
    _ -> TrendStable
  }

  let has_critical =
    list.any(updated_vars, fn(v) {
      case v.stress {
        StressCritical -> True
        _ -> False
      }
    })

  let is_homeostatic = !has_critical && new_composite <=. 0.70

  PhysiologicalState(
    variables: updated_vars,
    composite_stress: new_composite,
    stress_trend: trend,
    is_homeostatic: is_homeostatic,
    timestamp_us: now_us,
  )
}
