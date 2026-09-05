//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/math/bayesian</module>
////     <fsharp-lineage>None — novel Bayesian inference module (L5_COGNITIVE)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////     <mesh-domain>
////       Bayesian belief updating, Beta distribution tracking, Pareto
////       multi-objective optimisation front, and exponential-moving-average
////       time-series forecasting.  All functions are pure value transforms —
////       no side-effects, no mutable state.
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>HIGH</criticality>
////     <stamp-controls>SC-BIO-EVO-001, SC-MATH-001, SC-MUDA-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       Conjugate Gaussian update ↪ Gleam pure value type BayesianBelief.
////       Caller owns persistence; no globals.
////     </morphism>
////     <morphism type="injective">
////       Beta-Bernoulli conjugate model ↪ BetaDistribution (alpha / beta_param).
////       Naming: `beta_param` avoids clash with Gleam built-in `bool`.
////     </morphism>
////     <morphism type="surjective" loss="floating-point-precision">
////       IEEE 754 Float64 arithmetic — suitable for OODA advisory; not for
////       safety actuation (SC-SIL4-001).
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// BAYESIAN INFERENCE & MULTI-OBJECTIVE OPTIMISATION
//// बायेसियन अनुमान — ज्ञानेन तु तदज्ञानं नाशितम् (Gita 5.16)
////
//// STAMP: SC-BIO-EVO-001, SC-MATH-001, SC-MUDA-001

import gleam/float
import gleam/int
import gleam/list

// =============================================================================
// Gaussian Bayesian Belief (गाउसियन बायेसियन विश्वास)
// =============================================================================

/// Conjugate Gaussian belief state.
///
/// Tracks a distribution over an unknown mean μ with known noise.
/// The posterior is also Gaussian — closed-form update equations apply.
pub type BayesianBelief {
  BayesianBelief(
    /// Prior mean estimate μ₀
    prior_mean: Float,
    /// Prior variance σ₀²  (uncertainty about the mean before data)
    prior_variance: Float,
    /// Current posterior mean — updated on each `belief_update` call
    posterior_mean: Float,
    /// Current posterior variance — shrinks with each observation
    posterior_variance: Float,
    /// Number of observations incorporated
    sample_count: Int,
    /// Evidence strength ∈ [0, 1] — how much the data has narrowed the belief
    evidence_strength: Float,
  )
}

/// Create a fresh belief centred at `mean` with `variance` uncertainty.
///
/// Posterior fields are initialised to the prior — no data seen yet.
pub fn belief_new(mean: Float, variance: Float) -> BayesianBelief {
  BayesianBelief(
    prior_mean: mean,
    prior_variance: variance,
    posterior_mean: mean,
    posterior_variance: variance,
    sample_count: 0,
    evidence_strength: 0.0,
  )
}

/// Incorporate a new `observation` with measurement `noise` variance.
///
/// Conjugate Gaussian update (Bishop 2006, §2.3.3):
///   posterior_mean = (prior_var · obs + noise · prior_mean) / (prior_var + noise)
///   posterior_var  = (prior_var · noise) / (prior_var + noise)
///
/// Evidence strength = 1 − (posterior_var / prior_var), clamped to [0, 1].
pub fn belief_update(
  belief: BayesianBelief,
  observation: Float,
  noise: Float,
) -> BayesianBelief {
  let pv = belief.posterior_variance
  let denom = pv +. noise
  let new_mean = case denom <. 1.0e-15 {
    True -> observation
    False -> { pv *. observation +. noise *. belief.posterior_mean } /. denom
  }
  let new_var = case denom <. 1.0e-15 {
    True -> 0.0
    False -> { pv *. noise } /. denom
  }
  let strength = case belief.prior_variance >. 1.0e-15 {
    False -> 1.0
    True -> {
      let raw = 1.0 -. new_var /. belief.prior_variance
      clamp(raw, 0.0, 1.0)
    }
  }
  BayesianBelief(
    ..belief,
    posterior_mean: new_mean,
    posterior_variance: new_var,
    sample_count: belief.sample_count + 1,
    evidence_strength: strength,
  )
}

/// Confidence ∈ [0, 1] — how much the posterior has tightened relative to prior.
///
/// 0.0 = prior unchanged (no evidence).
/// 1.0 = posterior variance collapsed to zero (perfect certainty).
pub fn belief_confidence(belief: BayesianBelief) -> Float {
  case belief.prior_variance >. 1.0e-15 {
    False -> 1.0
    True ->
      clamp(1.0 -. belief.posterior_variance /. belief.prior_variance, 0.0, 1.0)
  }
}

/// Human-readable summary of a belief state.
pub fn summary_belief(belief: BayesianBelief) -> String {
  let conf = belief_confidence(belief)
  "BayesianBelief{mean="
  <> float_2dp(belief.posterior_mean)
  <> " var="
  <> float_2dp(belief.posterior_variance)
  <> " n="
  <> int.to_string(belief.sample_count)
  <> " conf="
  <> float_2dp(conf)
  <> "}"
}

// =============================================================================
// Beta Distribution (बीटा वितरण)
// =============================================================================

/// Beta distribution parameterised by pseudo-counts α and β.
///
/// Models the probability that a Bernoulli event has success rate p.
/// Conjugate prior for Binomial likelihood — update is a single increment.
///
/// NOTE: field is `beta_param` (not `beta`) to avoid shadowing the Gleam
/// standard-library function `float.to_string` which has no conflict but
/// matches the documented naming convention.
pub type BetaDistribution {
  BetaDistribution(
    /// α — pseudo-count of successes + 1 (starts at 1 for uniform prior)
    alpha: Float,
    /// β — pseudo-count of failures + 1
    beta_param: Float,
  )
}

/// Create a Beta(α, β) distribution.  Use α=β=1.0 for a uniform prior.
pub fn beta_new(alpha: Float, beta_param: Float) -> BetaDistribution {
  BetaDistribution(alpha: alpha, beta_param: beta_param)
}

/// Update the Beta distribution given a Bernoulli trial outcome.
///
/// Success → α += 1.  Failure → β += 1.
pub fn beta_update(dist: BetaDistribution, success: Bool) -> BetaDistribution {
  case success {
    True -> BetaDistribution(..dist, alpha: dist.alpha +. 1.0)
    False -> BetaDistribution(..dist, beta_param: dist.beta_param +. 1.0)
  }
}

/// Expected value E[p] = α / (α + β).
pub fn beta_mean(dist: BetaDistribution) -> Float {
  let total = dist.alpha +. dist.beta_param
  case total <. 1.0e-15 {
    True -> 0.5
    False -> dist.alpha /. total
  }
}

/// Confidence ∈ [0, 1] based on effective sample size.
///
/// Approaches 1 as the total pseudo-count grows relative to a reference of 10.
pub fn beta_confidence(dist: BetaDistribution) -> Float {
  let n = dist.alpha +. dist.beta_param
  n /. { n +. 10.0 }
}

// =============================================================================
// Pareto Front (पेरेतो मोर्चा)
// =============================================================================

/// A candidate solution in a multi-objective optimisation problem.
///
/// `objectives` is a list of objective values, each to be MAXIMISED.
/// `feasible` indicates whether the solution satisfies all constraints.
pub type ParetoSolution {
  ParetoSolution(id: String, objectives: List(Float), feasible: Bool)
}

/// The current Pareto-optimal front.
pub type ParetoFront {
  ParetoFront(
    solutions: List(ParetoSolution),
    /// Count of solutions that were dominated and therefore discarded
    dominated_count: Int,
  )
}

/// Empty Pareto front — no solutions yet.
pub fn pareto_new() -> ParetoFront {
  ParetoFront(solutions: [], dominated_count: 0)
}

/// Add `solution` to the front, removing any solutions it dominates.
///
/// A solution is kept iff it is not dominated by any existing solution.
/// Non-feasible solutions are accepted but never dominate feasible ones.
pub fn pareto_add(front: ParetoFront, solution: ParetoSolution) -> ParetoFront {
  // Check whether any existing solution dominates the new one
  let dominated_by_existing =
    list.any(front.solutions, fn(s) { dominates(s, solution) })
  case dominated_by_existing {
    True -> ParetoFront(..front, dominated_count: front.dominated_count + 1)
    False -> {
      // Remove existing solutions that the new solution dominates
      let kept = list.filter(front.solutions, fn(s) { !dominates(solution, s) })
      let newly_dominated = list.length(front.solutions) - list.length(kept)
      ParetoFront(
        solutions: list.append(kept, [solution]),
        dominated_count: front.dominated_count + newly_dominated,
      )
    }
  }
}

/// Returns True iff solution `a` dominates solution `b`.
///
/// Dominance (maximisation): a ≽ b iff
///   ∀ i: a.objectives[i] ≥ b.objectives[i]   AND
///   ∃ i: a.objectives[i] >  b.objectives[i]   AND
///   a.feasible OR NOT b.feasible
///
/// A non-feasible solution cannot dominate a feasible one.
pub fn dominates(a: ParetoSolution, b: ParetoSolution) -> Bool {
  // Non-feasible cannot dominate feasible
  case a.feasible, b.feasible {
    False, True -> False
    _, _ -> {
      let pairs = list.zip(a.objectives, b.objectives)
      let all_gte = list.all(pairs, fn(p) { p.0 >=. p.1 })
      let any_gt = list.any(pairs, fn(p) { p.0 >. p.1 })
      all_gte && any_gt
    }
  }
}

/// Number of non-dominated solutions in the front.
pub fn pareto_size(front: ParetoFront) -> Int {
  list.length(front.solutions)
}

/// Human-readable summary of the Pareto front.
pub fn summary_pareto(front: ParetoFront) -> String {
  "ParetoFront{size="
  <> int.to_string(pareto_size(front))
  <> " dominated="
  <> int.to_string(front.dominated_count)
  <> "}"
}

// =============================================================================
// Trend & EMA Forecasting (प्रवृत्ति एवं ईएमए पूर्वानुमान)
// =============================================================================

/// Qualitative direction of a time series.
pub type Trend {
  Increasing
  Decreasing
  Stable
}

/// Result of a time-series forecast.
pub type ForecastResult {
  ForecastResult(
    /// Point estimate at `horizon_steps` steps ahead
    predicted: Float,
    /// 95 % lower confidence bound (± 1 σ heuristic)
    lower_bound: Float,
    /// 95 % upper confidence bound
    upper_bound: Float,
    /// Qualitative trend detected in the series tail
    trend: Trend,
    /// Number of steps ahead this forecast covers
    horizon_steps: Int,
  )
}

/// Extrapolate `series` using Exponential Moving Average.
///
/// 1. Compute EMA with smoothing parameter `alpha` ∈ (0, 1].
/// 2. Estimate per-step drift as the mean difference of the last 3 EMA values.
/// 3. Project `horizon` steps ahead by adding `horizon × drift` to EMA tail.
/// 4. Confidence interval = ± stddev(series) × sqrt(horizon).
///
/// Returns a conservative forecast when the series is empty or too short.
pub fn forecast_ema(
  series: List(Float),
  alpha: Float,
  horizon: Int,
) -> ForecastResult {
  case series {
    [] ->
      ForecastResult(
        predicted: 0.0,
        lower_bound: 0.0,
        upper_bound: 0.0,
        trend: Stable,
        horizon_steps: horizon,
      )
    [single] ->
      ForecastResult(
        predicted: single,
        lower_bound: single,
        upper_bound: single,
        trend: Stable,
        horizon_steps: horizon,
      )
    _ -> {
      let ema_values = compute_ema(series, alpha)
      let last_ema = list.last(ema_values) |> result_unwrap_float(0.0)
      let drift = estimate_drift(ema_values)
      let h_f = int.to_float(horizon)
      let predicted = last_ema +. drift *. h_f
      let sigma = series_stddev(series)
      let margin = sigma *. float_sqrt(h_f)
      let t = forecast_trend(series)
      ForecastResult(
        predicted: predicted,
        lower_bound: predicted -. margin,
        upper_bound: predicted +. margin,
        trend: t,
        horizon_steps: horizon,
      )
    }
  }
}

/// Determine trend from the last 3 values of `series`.
///
/// Increasing:  last > first of tail by more than 1 % of the mean.
/// Decreasing:  last < first of tail by more than 1 % of the mean.
/// Stable:      within 1 % of mean.
pub fn forecast_trend(series: List(Float)) -> Trend {
  case list.length(series) < 2 {
    True -> Stable
    False -> {
      let tail = list.drop(series, int.max(list.length(series) - 3, 0))
      let first = list.first(tail) |> result_unwrap_float(0.0)
      let last = list.last(tail) |> result_unwrap_float(0.0)
      let avg = { first +. last } /. 2.0
      let threshold = case avg <. 1.0e-10 {
        True -> 1.0e-10
        False -> avg *. 0.01
      }
      case last -. first >. threshold {
        True -> Increasing
        False ->
          case first -. last >. threshold {
            True -> Decreasing
            False -> Stable
          }
      }
    }
  }
}

// =============================================================================
// Internal helpers (आंतरिक सहायक)
// =============================================================================

/// Compute the full EMA sequence for `series` with smoothing `alpha`.
fn compute_ema(series: List(Float), alpha: Float) -> List(Float) {
  let safe_alpha = clamp(alpha, 1.0e-6, 1.0)
  case series {
    [] -> []
    [h, ..rest] ->
      list.fold(rest, [h], fn(acc, x) {
        let prev = list.last(acc) |> result_unwrap_float(x)
        let new_ema = safe_alpha *. x +. { 1.0 -. safe_alpha } *. prev
        list.append(acc, [new_ema])
      })
  }
}

/// Estimate per-step drift as the mean of consecutive differences in the tail.
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

/// Population standard deviation of `values`.
fn series_stddev(values: List(Float)) -> Float {
  let n = list.length(values)
  case n < 2 {
    True -> 0.0
    False -> {
      let mean_val =
        list.fold(values, 0.0, fn(a, v) { a +. v }) /. int.to_float(n)
      let variance =
        list.fold(values, 0.0, fn(a, v) {
          let d = v -. mean_val
          a +. d *. d
        })
        /. int.to_float(n)
      float_sqrt(variance)
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

/// Square root via Erlang math module.
@external(erlang, "math", "sqrt")
fn float_sqrt(x: Float) -> Float

/// Unwrap a Float Result, returning `default` on error.
fn result_unwrap_float(r: Result(Float, e), default: Float) -> Float {
  case r {
    Ok(v) -> v
    Error(_) -> default
  }
}

/// Format a Float as a String (delegates to float.to_string).
fn float_2dp(x: Float) -> String {
  float.to_string(x)
}
