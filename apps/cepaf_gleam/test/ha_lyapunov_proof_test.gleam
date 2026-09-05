/// Lyapunov Proof Tests — formal stability analysis for guard_grid OODA
/// स्थिरता — Stability is the ground of right action (Gita 2.48)
///
/// 15 tests covering:
///   - init: zero state, Marginal verdict, zero samples
///   - energy_function: setpoint zero, above/below setpoint, symmetry
///   - energy_derivative: converging (negative), diverging (positive), at setpoint
///   - update: stable trajectory, unstable trajectory, sample count increment
///   - is_stable: stable state, unstable state, marginal state
///   - convergence_rate: stable returns |λ|, unstable returns 0.0
///   - verdict_to_string: all three variants
///   - to_json: structure verification
///   - summary: non-empty, contains key fields
///
/// Layer: L0_CONSTITUTIONAL
/// STAMP: SC-MATH-001, SC-OODA-001, SC-SIL4-001, SC-SATYA-001
import cepaf_gleam/ha/lyapunov_proof.{
  LyapunovAnalysis, Marginal, Stable, Unstable, convergence_rate,
  energy_derivative, energy_function, init, is_stable, summary, to_json, update,
  verdict_to_string,
}
import gleam/string
import gleeunit/should

// ═══════════════════════════════════════════════════════════════
// init — zero state
// ═══════════════════════════════════════════════════════════════

pub fn init_exponent_zero_test() {
  init().exponent |> should.equal(0.0)
}

pub fn init_energy_zero_test() {
  init().energy |> should.equal(0.0)
}

pub fn init_energy_derivative_zero_test() {
  init().energy_derivative |> should.equal(0.0)
}

pub fn init_verdict_marginal_test() {
  init().verdict |> should.equal(Marginal)
}

pub fn init_samples_zero_test() {
  init().samples |> should.equal(0)
}

// ═══════════════════════════════════════════════════════════════
// energy_function — V(x) = (x − setpoint)²
// ═══════════════════════════════════════════════════════════════

pub fn energy_at_setpoint_is_zero_test() {
  energy_function(1.0, 1.0) |> should.equal(0.0)
}

pub fn energy_above_setpoint_is_positive_test() {
  // V(1.2, 1.0) = (1.2 - 1.0)² = 0.04
  let v = energy_function(1.2, 1.0)
  let ok = v >. 0.0
  ok |> should.be_true()
}

pub fn energy_below_setpoint_is_positive_test() {
  // V(0.8, 1.0) = (0.8 - 1.0)² = 0.04
  let v = energy_function(0.8, 1.0)
  let ok = v >. 0.0
  ok |> should.be_true()
}

pub fn energy_is_symmetric_test() {
  // V(x* + d, x*) = V(x* - d, x*)
  let v_above = energy_function(1.3, 1.0)
  let v_below = energy_function(0.7, 1.0)
  // Both equal 0.09 — compare within tolerance
  let diff = v_above -. v_below
  let ok = diff >. -0.0001 && diff <. 0.0001
  ok |> should.be_true()
}

// ═══════════════════════════════════════════════════════════════
// energy_derivative — dV/dt
// ═══════════════════════════════════════════════════════════════

pub fn energy_derivative_converging_is_negative_test() {
  // health moving from 0.5 toward setpoint 1.0: prev=0.5, now=0.8
  let dv = energy_derivative(0.8, 0.5, 1.0, 1.0)
  // V(0.5,1.0) = 0.25; V(0.8,1.0) = 0.04 → dV < 0
  let ok = dv <. 0.0
  ok |> should.be_true()
}

pub fn energy_derivative_diverging_is_positive_test() {
  // health moving away from setpoint: prev=0.9, now=0.5
  let dv = energy_derivative(0.5, 0.9, 1.0, 1.0)
  // V(0.9) = 0.01; V(0.5) = 0.25 → dV > 0
  let ok = dv >. 0.0
  ok |> should.be_true()
}

pub fn energy_derivative_at_setpoint_is_zero_test() {
  // both observations at setpoint → no change
  let dv = energy_derivative(1.0, 1.0, 1.0, 1.0)
  dv |> should.equal(0.0)
}

// ═══════════════════════════════════════════════════════════════
// update — trajectory processing
// ═══════════════════════════════════════════════════════════════

pub fn update_increments_samples_test() {
  let s0 = init()
  let s1 = update(s0, 0.8, 0.7, 1.0)
  s1.samples |> should.equal(1)
}

pub fn update_stable_trajectory_test() {
  // Monotonically improving health → should be Stable after several updates
  let s0 = init()
  let s1 = update(s0, 0.6, 0.4, 1.0)
  let s2 = update(s1, 0.75, 0.6, 1.0)
  let s3 = update(s2, 0.88, 0.75, 1.0)
  // verdict should be Stable (converging toward 1.0)
  s3.verdict |> should.equal(Stable)
}

pub fn update_unstable_trajectory_test() {
  // Health deteriorating: 0.9 → 0.7 → 0.5
  let s0 = init()
  let s1 = update(s0, 0.7, 0.9, 1.0)
  let s2 = update(s1, 0.5, 0.7, 1.0)
  // Energy is growing → Unstable
  s2.verdict |> should.equal(Unstable)
}

pub fn update_energy_nonnegative_test() {
  // Lyapunov energy must always be >= 0 (positive-definite)
  let s1 = update(init(), 0.3, 0.5, 1.0)
  let ok = s1.energy >=. 0.0
  ok |> should.be_true()
}

// ═══════════════════════════════════════════════════════════════
// is_stable / convergence_rate
// ═══════════════════════════════════════════════════════════════

pub fn is_stable_stable_state_test() {
  // Manually construct a stable state: λ < 0, dV/dt < 0
  let stable =
    LyapunovAnalysis(
      exponent: -0.5,
      energy: 0.04,
      energy_derivative: -0.02,
      verdict: Stable,
      samples: 5,
    )
  is_stable(stable) |> should.be_true()
}

pub fn is_stable_unstable_state_test() {
  let unstable =
    LyapunovAnalysis(
      exponent: 0.3,
      energy: 0.09,
      energy_derivative: 0.05,
      verdict: Unstable,
      samples: 3,
    )
  is_stable(unstable) |> should.be_false()
}

pub fn is_stable_marginal_state_test() {
  is_stable(init()) |> should.be_false()
}

pub fn convergence_rate_stable_is_positive_test() {
  let stable =
    LyapunovAnalysis(
      exponent: -0.42,
      energy: 0.04,
      energy_derivative: -0.01,
      verdict: Stable,
      samples: 10,
    )
  let r = convergence_rate(stable)
  let ok = r >. 0.0
  ok |> should.be_true()
}

pub fn convergence_rate_unstable_is_zero_test() {
  let unstable =
    LyapunovAnalysis(
      exponent: 0.3,
      energy: 0.09,
      energy_derivative: 0.05,
      verdict: Unstable,
      samples: 3,
    )
  convergence_rate(unstable) |> should.equal(0.0)
}

// ═══════════════════════════════════════════════════════════════
// verdict_to_string
// ═══════════════════════════════════════════════════════════════

pub fn verdict_stable_string_test() {
  verdict_to_string(Stable) |> should.equal("stable")
}

pub fn verdict_unstable_string_test() {
  verdict_to_string(Unstable) |> should.equal("unstable")
}

pub fn verdict_marginal_string_test() {
  verdict_to_string(Marginal) |> should.equal("marginal")
}

// ═══════════════════════════════════════════════════════════════
// to_json — structure verification
// ═══════════════════════════════════════════════════════════════

pub fn to_json_contains_exponent_key_test() {
  let j = to_json(init())
  string.contains(j, "\"exponent\"") |> should.be_true()
}

pub fn to_json_contains_energy_key_test() {
  let j = to_json(init())
  string.contains(j, "\"energy\"") |> should.be_true()
}

pub fn to_json_contains_verdict_key_test() {
  let j = to_json(init())
  string.contains(j, "\"verdict\"") |> should.be_true()
}

pub fn to_json_contains_samples_key_test() {
  let j = to_json(init())
  string.contains(j, "\"samples\"") |> should.be_true()
}

pub fn to_json_is_object_test() {
  let j = to_json(init())
  let starts = string.starts_with(j, "{")
  let ends = string.ends_with(j, "}")
  { starts && ends } |> should.be_true()
}

// ═══════════════════════════════════════════════════════════════
// summary — human-readable string
// ═══════════════════════════════════════════════════════════════

pub fn summary_nonempty_test() {
  let s = summary(init())
  { string.length(s) > 0 } |> should.be_true()
}

pub fn summary_contains_verdict_test() {
  let s = summary(init())
  string.contains(s, "verdict=") |> should.be_true()
}

pub fn summary_contains_samples_test() {
  let s = summary(init())
  string.contains(s, "samples=") |> should.be_true()
}
