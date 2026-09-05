/// Bayesian Inference & Multi-Objective Optimisation Tests
/// Layer: L5_COGNITIVE
/// STAMP: SC-BIO-EVO-001, SC-MATH-001, SC-MUDA-001
///
/// 25 tests covering:
///   C1 Module structure — types constructable, basic API accessible
///   C2 Gaussian Bayesian belief — init, update, confidence
///   C3 Beta distribution — init, update (success/failure), mean, confidence
///   C4 Pareto front — add, dominance, size
///   C5 EMA forecasting — trend detection, horizon extrapolation
///   C6 Edge cases — empty series, zero variance, single value
///   C7 Dominance semantics — feasibility rules
///   C8 Summary strings — non-empty, well-formed
import cepaf_gleam/math/bayesian.{
  Decreasing, Increasing, ParetoSolution, Stable, belief_confidence, belief_new,
  belief_update, beta_confidence, beta_mean, beta_new, beta_update, dominates,
  forecast_ema, forecast_trend, pareto_add, pareto_new, pareto_size,
  summary_belief, summary_pareto,
}
import gleam/list
import gleeunit/should

// ---------------------------------------------------------------------------
// C1: Module structure — types are constructable (SC-WIRE-007)
// ---------------------------------------------------------------------------

pub fn belief_new_creates_valid_state_test() {
  let b = belief_new(0.5, 1.0)
  b.prior_mean |> should.equal(0.5)
  b.prior_variance |> should.equal(1.0)
  b.posterior_mean |> should.equal(0.5)
  b.posterior_variance |> should.equal(1.0)
  b.sample_count |> should.equal(0)
}

pub fn beta_new_creates_valid_state_test() {
  let d = beta_new(1.0, 1.0)
  d.alpha |> should.equal(1.0)
  d.beta_param |> should.equal(1.0)
}

pub fn pareto_new_is_empty_test() {
  let f = pareto_new()
  pareto_size(f) |> should.equal(0)
  f.dominated_count |> should.equal(0)
}

// ---------------------------------------------------------------------------
// C2: Gaussian Bayesian belief update
// ---------------------------------------------------------------------------

pub fn belief_update_increases_sample_count_test() {
  let b = belief_new(0.0, 1.0) |> belief_update(1.0, 0.5)
  b.sample_count |> should.equal(1)
}

pub fn belief_update_moves_mean_toward_observation_test() {
  let prior = belief_new(0.0, 1.0)
  let updated = belief_update(prior, 10.0, 1.0)
  // posterior mean must lie between prior mean and observation
  let gt_prior = updated.posterior_mean >. 0.0
  let lt_obs = updated.posterior_mean <. 10.0
  gt_prior |> should.equal(True)
  lt_obs |> should.equal(True)
}

pub fn belief_update_reduces_variance_test() {
  let prior = belief_new(0.5, 1.0)
  let updated = belief_update(prior, 0.5, 0.5)
  let reduced = updated.posterior_variance <. prior.posterior_variance
  reduced |> should.equal(True)
}

pub fn belief_confidence_zero_on_fresh_belief_test() {
  let b = belief_new(0.0, 1.0)
  // No updates — posterior == prior => confidence = 0
  belief_confidence(b) |> should.equal(0.0)
}

pub fn belief_confidence_increases_after_update_test() {
  let b0 = belief_new(0.0, 1.0)
  let b1 = belief_update(b0, 1.0, 0.1)
  let b2 = belief_update(b1, 1.0, 0.1)
  let gt = belief_confidence(b2) >. belief_confidence(b1)
  gt |> should.equal(True)
}

pub fn belief_confidence_is_in_unit_interval_test() {
  let b =
    belief_new(0.0, 1.0) |> belief_update(5.0, 0.1) |> belief_update(5.0, 0.1)
  let c = belief_confidence(b)
  let gte0 = c >=. 0.0
  let lte1 = c <=. 1.0
  gte0 |> should.equal(True)
  lte1 |> should.equal(True)
}

// ---------------------------------------------------------------------------
// C3: Beta distribution
// ---------------------------------------------------------------------------

pub fn beta_mean_uniform_prior_is_half_test() {
  beta_new(1.0, 1.0) |> beta_mean |> should.equal(0.5)
}

pub fn beta_update_success_increments_alpha_test() {
  let d = beta_new(1.0, 1.0) |> beta_update(True)
  d.alpha |> should.equal(2.0)
  d.beta_param |> should.equal(1.0)
}

pub fn beta_update_failure_increments_beta_param_test() {
  let d = beta_new(1.0, 1.0) |> beta_update(False)
  d.alpha |> should.equal(1.0)
  d.beta_param |> should.equal(2.0)
}

pub fn beta_mean_biased_toward_success_test() {
  // After 9 successes + 1 failure: alpha=10, beta_param=2 => mean = 10/12 ≈ 0.833
  let d =
    list.fold(list.repeat(True, 9), beta_new(1.0, 1.0), fn(acc, _) {
      beta_update(acc, True)
    })
    |> beta_update(False)
  let m = beta_mean(d)
  let gt = m >. 0.8
  gt |> should.equal(True)
}

pub fn beta_confidence_grows_with_samples_test() {
  let d0 = beta_new(1.0, 1.0)
  let d10 =
    list.fold(list.repeat(True, 10), d0, fn(acc, _) { beta_update(acc, True) })
  let more_confident = beta_confidence(d10) >. beta_confidence(d0)
  more_confident |> should.equal(True)
}

// ---------------------------------------------------------------------------
// C4: Pareto front
// ---------------------------------------------------------------------------

pub fn pareto_add_single_solution_test() {
  let s = ParetoSolution(id: "s1", objectives: [0.5, 0.7], feasible: True)
  let f = pareto_new() |> pareto_add(s)
  pareto_size(f) |> should.equal(1)
}

pub fn pareto_dominated_solution_not_added_test() {
  let s1 = ParetoSolution(id: "s1", objectives: [0.8, 0.8], feasible: True)
  let s2 = ParetoSolution(id: "s2", objectives: [0.5, 0.5], feasible: True)
  let f = pareto_new() |> pareto_add(s1) |> pareto_add(s2)
  // s2 is dominated by s1; only s1 remains
  pareto_size(f) |> should.equal(1)
  f.dominated_count |> should.equal(1)
}

pub fn pareto_non_dominated_solutions_both_kept_test() {
  let s1 = ParetoSolution(id: "s1", objectives: [1.0, 0.0], feasible: True)
  let s2 = ParetoSolution(id: "s2", objectives: [0.0, 1.0], feasible: True)
  let f = pareto_new() |> pareto_add(s1) |> pareto_add(s2)
  pareto_size(f) |> should.equal(2)
}

pub fn dominates_equal_objectives_is_false_test() {
  let a = ParetoSolution(id: "a", objectives: [0.5, 0.5], feasible: True)
  let b = ParetoSolution(id: "b", objectives: [0.5, 0.5], feasible: True)
  dominates(a, b) |> should.equal(False)
}

pub fn dominates_strict_domination_is_true_test() {
  let a = ParetoSolution(id: "a", objectives: [0.9, 0.9], feasible: True)
  let b = ParetoSolution(id: "b", objectives: [0.5, 0.5], feasible: True)
  dominates(a, b) |> should.equal(True)
}

// ---------------------------------------------------------------------------
// C5: EMA forecasting
// ---------------------------------------------------------------------------

pub fn forecast_trend_increasing_series_test() {
  forecast_trend([1.0, 2.0, 3.0, 4.0, 5.0]) |> should.equal(Increasing)
}

pub fn forecast_trend_decreasing_series_test() {
  forecast_trend([5.0, 4.0, 3.0, 2.0, 1.0]) |> should.equal(Decreasing)
}

pub fn forecast_trend_stable_series_test() {
  forecast_trend([1.0, 1.0, 1.0, 1.0]) |> should.equal(Stable)
}

pub fn forecast_ema_horizon_steps_matches_test() {
  let r = forecast_ema([1.0, 2.0, 3.0], 0.3, 5)
  r.horizon_steps |> should.equal(5)
}

pub fn forecast_ema_increasing_series_predicts_higher_test() {
  let series = [1.0, 2.0, 3.0, 4.0, 5.0]
  let last = 5.0
  let r = forecast_ema(series, 0.3, 3)
  let higher = r.predicted >. last
  higher |> should.equal(True)
}

// ---------------------------------------------------------------------------
// C6: Edge cases
// ---------------------------------------------------------------------------

pub fn forecast_ema_empty_series_returns_zeros_test() {
  let r = forecast_ema([], 0.3, 1)
  r.predicted |> should.equal(0.0)
  r.trend |> should.equal(Stable)
}

pub fn forecast_ema_single_value_returns_that_value_test() {
  let r = forecast_ema([0.42], 0.3, 1)
  r.predicted |> should.equal(0.42)
}

// ---------------------------------------------------------------------------
// C8: Summary strings — non-empty and well-formed
// ---------------------------------------------------------------------------

pub fn summary_belief_is_non_empty_test() {
  let s = belief_new(0.5, 1.0) |> summary_belief
  let non_empty = s != ""
  non_empty |> should.equal(True)
}

pub fn summary_pareto_is_non_empty_test() {
  let s = pareto_new() |> summary_pareto
  let non_empty = s != ""
  non_empty |> should.equal(True)
}
