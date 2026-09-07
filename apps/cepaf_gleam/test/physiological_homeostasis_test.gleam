import cepaf_gleam/ha/physiological_homeostasis.{
  CpuUtilization, ErrorRate, MemoryUtilization, RequestLatency,
  StressCritical, StressHigh, StressLow, StressOptimal,
  TrendRising, TrendStable, classify_stress,
  default_variables, initial_physiological_state, step_variable,
  update_physiological_telemetry,
}
import gleam/list
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn default_variables_count_test() {
  let vars = default_variables()
  list.length(vars) |> should.equal(4)
}

pub fn stress_classification_test() {
  classify_stress(CpuUtilization, 25.0) |> should.equal(StressLow)
  classify_stress(CpuUtilization, 50.0) |> should.equal(StressOptimal)
  classify_stress(CpuUtilization, 78.0) |> should.equal(StressHigh)
  classify_stress(CpuUtilization, 95.0) |> should.equal(StressCritical)

  classify_stress(RequestLatency, 15.0) |> should.equal(StressLow)
  classify_stress(RequestLatency, 80.0) |> should.equal(StressOptimal)
  classify_stress(RequestLatency, 250.0) |> should.equal(StressHigh)
  classify_stress(RequestLatency, 600.0) |> should.equal(StressCritical)
}

pub fn step_variable_pid_anti_windup_test() {
  let vars = default_variables()
  let assert Ok(cpu_var) = list.find(vars, fn(v) { v.variable == CpuUtilization })

  // High load for sustained period should clamp integral to 10.0
  let s1 = step_variable(cpu_var, 95.0, 10.0)
  s1.integral |> should.equal(10.0)
  s1.stress |> should.equal(StressCritical)
  { s1.control_signal >. 0.0 } |> should.equal(True)
}

pub fn physiological_telemetry_trend_and_homeostasis_test() {
  let s0 = initial_physiological_state(1000)
  s0.is_homeostatic |> should.equal(True)
  s0.stress_trend |> should.equal(TrendStable)

  // Ingest nominal observations
  let s1 =
    update_physiological_telemetry(
      s0,
      [#(CpuUtilization, 40.0), #(MemoryUtilization, 50.0), #(RequestLatency, 45.0), #(ErrorRate, 0.01)],
      1.0,
      2000,
    )
  s1.is_homeostatic |> should.equal(True)

  // Ingest critical observation
  let s2 =
    update_physiological_telemetry(
      s1,
      [#(CpuUtilization, 98.0)],
      1.0,
      3000,
    )
  s2.is_homeostatic |> should.equal(False)
  s2.stress_trend |> should.equal(TrendRising)
}
