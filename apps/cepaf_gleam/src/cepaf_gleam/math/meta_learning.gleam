//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/math/meta_learning</module>
////     <fsharp-lineage>None — novel meta-learning strategy selection pool (META-1)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////     <mesh-domain>
////       Multi-armed bandit strategy selection for the OODA orient/decide phases.
////       Maintains a pool of named strategies with EMA-smoothed fitness scores.
////       Supports four selection policies:
////
////         BestFitness     — greedy: always pick the highest-fitness strategy
////         EpsilonGreedy ε — exploit with prob (1−ε), explore uniformly at random
////         ThompsonSampling — sample from Beta(α=successes+1, β=failures+1) per arm
////         UCB1             — Upper Confidence Bound: fitness + √(2·ln(N)/n_i)
////
////       Fitness updates use Exponential Moving Average:
////         f_new = α · outcome + (1−α) · f_old    (α = 0.1)
////
////       This allows the pool to track non-stationary strategy performance
////       across OODA evolution cycles without unbounded memory growth.
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>HIGH</criticality>
////     <stamp-controls>SC-BIO-EVO-006, SC-MATH-001, SC-OODA-001, SC-MUDA-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       Multi-armed bandit (Thompson 1933, Auer 2002 UCB1) ↪ Gleam pure value type.
////       All state passed by value; no mutable globals; caller owns persistence.
////     </morphism>
////     <morphism type="surjective" loss="floating-point-precision">
////       IEEE 754 Float64 arithmetic ↠ Erlang float.
////       Beta distribution mean is approximated as α/(α+β) rather than sampled
////       via PRNG — deterministic and safe for SIL-6.
////       Mitigation: Approximation error is bounded by O(1/n) and acceptable for
////       strategy selection guidance; not used for safety actuation.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// META-LEARNING STRATEGY POOL — META-1
//// कर्मण्येवाधिकारस्ते मा फलेषु कदाचन — Your right is to action, never to its fruit (Gita 2.47)
////
//// EMA fitness update:
////   f_new = α · outcome + (1−α) · f_old,   α = 0.1
////
//// UCB1 score:
////   score(i) = f_i + √(2 · ln(N) / max(n_i, 1))
////   where N = total trials, n_i = trials for strategy i
////
//// Thompson sampling (Beta mean approximation):
////   score(i) ≈ (successes_i + 1) / (successes_i + failures_i + 2)
////
//// STAMP: SC-BIO-EVO-006, SC-MATH-001, SC-OODA-001, SC-MUDA-001

import gleam/float
import gleam/int
import gleam/list
import gleam/order

// =============================================================================
// FFI: Erlang math
// =============================================================================

@external(erlang, "math", "log")
fn math_log(x: Float) -> Float

@external(erlang, "math", "sqrt")
fn math_sqrt(x: Float) -> Float

// =============================================================================
// Public types
// =============================================================================

/// A single evolution strategy tracked in the pool.
pub type Strategy {
  Strategy(
    /// Unique identifier for this strategy.
    name: String,
    /// Functional domain this strategy applies to (e.g. "ooda", "fitness").
    domain: String,
    /// Number of times this strategy produced a successful outcome.
    success_count: Int,
    /// Number of times this strategy produced a failed outcome.
    failure_count: Int,
    /// EMA-smoothed fitness score ∈ [0.0, 1.0].
    fitness: Float,
    /// Timestamp (Unix epoch ms) of last selection — 0 if never selected.
    last_used: Int,
  )
}

/// Pool of strategies with selection history and generation counter.
pub type StrategyPool {
  StrategyPool(
    /// All strategies currently registered in the pool.
    strategies: List(Strategy),
    /// Ordered list of strategy names that have been selected (most recent last).
    selection_history: List(String),
    /// Monotonically increasing generation counter incremented on each record_outcome.
    generation: Int,
  )
}

/// Policy that controls how the next strategy is chosen from the pool.
pub type SelectionPolicy {
  /// Always select the strategy with the highest fitness score.
  BestFitness
  /// With probability ε, pick uniformly at random; otherwise pick best fitness.
  EpsilonGreedy(epsilon: Float)
  /// Use Beta distribution mean approximation — balances exploration/exploitation.
  ThompsonSampling
  /// Upper Confidence Bound: rewards uncertain arms to encourage exploration.
  UCB1
}

/// Result returned by `select/2`.
pub type SelectionResult {
  SelectionResult(
    /// The strategy that was chosen.
    selected: Strategy,
    /// Human-readable explanation of why this strategy was chosen.
    reason: String,
    /// True when the selection was exploratory (not purely fitness-greedy).
    exploration: Bool,
  )
}

// =============================================================================
// EMA alpha constant
// =============================================================================

/// Exponential Moving Average smoothing factor for fitness updates.
const ema_alpha: Float = 0.1

// =============================================================================
// Construction
// =============================================================================

/// Create a new strategy pool from an initial list of strategies.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <formal-proof>
///     <P> strategies is a non-empty list of distinct Strategy records. </P>
///     <C> pool_new(strategies) </C>
///     <Q> Returns StrategyPool with generation=0, empty history. </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn pool_new(strategies: List(Strategy)) -> StrategyPool {
  StrategyPool(strategies: strategies, selection_history: [], generation: 0)
}

// =============================================================================
// Selection dispatcher
// =============================================================================

/// Select the next strategy according to the given policy.
/// Returns an updated pool (history appended) and the selection result.
pub fn select(
  pool: StrategyPool,
  policy: SelectionPolicy,
) -> #(StrategyPool, SelectionResult) {
  case pool.strategies {
    [] -> #(
      pool,
      SelectionResult(
        selected: Strategy(
          name: "none",
          domain: "none",
          success_count: 0,
          failure_count: 0,
          fitness: 0.0,
          last_used: 0,
        ),
        reason: "pool is empty",
        exploration: False,
      ),
    )
    _ -> {
      let result = case policy {
        BestFitness -> {
          let s = best_fitness_select(pool)
          SelectionResult(
            selected: s,
            reason: "best fitness = " <> float_to_string_2dp(s.fitness),
            exploration: False,
          )
        }
        EpsilonGreedy(epsilon) -> epsilon_greedy_select(pool, epsilon)
        ThompsonSampling -> thompson_select(pool)
        UCB1 -> ucb1_select(pool)
      }
      let updated_pool =
        StrategyPool(
          ..pool,
          selection_history: list.append(pool.selection_history, [
            result.selected.name,
          ]),
        )
      #(updated_pool, result)
    }
  }
}

// =============================================================================
// Outcome recording
// =============================================================================

/// Record the outcome of using a strategy, updating its EMA fitness.
///
/// EMA update:
///   f_new = α · outcome_value + (1−α) · f_old
///   where outcome_value = 1.0 on success, 0.0 on failure.
pub fn record_outcome(
  pool: StrategyPool,
  name: String,
  success: Bool,
) -> StrategyPool {
  let outcome = case success {
    True -> 1.0
    False -> 0.0
  }
  let updated =
    list.map(pool.strategies, fn(s) {
      case s.name == name {
        False -> s
        True -> {
          let new_fitness =
            float.add(
              float.multiply(ema_alpha, outcome),
              float.multiply(1.0 -. ema_alpha, s.fitness),
            )
          let new_success = case success {
            True -> s.success_count + 1
            False -> s.success_count
          }
          let new_failure = case success {
            True -> s.failure_count
            False -> s.failure_count + 1
          }
          Strategy(
            ..s,
            fitness: new_fitness,
            success_count: new_success,
            failure_count: new_failure,
          )
        }
      }
    })
  StrategyPool(..pool, strategies: updated, generation: pool.generation + 1)
}

// =============================================================================
// UCB1 scoring
// =============================================================================

/// Compute the UCB1 score for a single strategy.
///
///   score = fitness + √(2 · ln(total) / max(trials, 1))
///
/// where trials = success_count + failure_count.
pub fn ucb1_score(strategy: Strategy, total: Int) -> Float {
  let trials = strategy.success_count + strategy.failure_count
  let n = case trials > 0 {
    True -> int.to_float(trials)
    False -> 1.0
  }
  let n_total = case total > 0 {
    True -> int.to_float(total)
    False -> 1.0
  }
  let exploration_bonus = math_sqrt(2.0 *. math_log(n_total) /. n)
  strategy.fitness +. exploration_bonus
}

// =============================================================================
// Thompson sampling
// =============================================================================

/// Compute the Beta distribution mean approximation for a strategy.
///
///   score ≈ (successes + 1) / (successes + failures + 2)
///
/// This is the mean of Beta(α=successes+1, β=failures+1) — deterministic,
/// no PRNG required, suitable for SIL-6 deterministic execution.
pub fn thompson_sample(strategy: Strategy) -> Float {
  let alpha = int.to_float(strategy.success_count) +. 1.0
  let beta = int.to_float(strategy.failure_count) +. 1.0
  alpha /. { alpha +. beta }
}

// =============================================================================
// Epsilon-greedy selection
// =============================================================================

/// Select a strategy using the ε-greedy policy.
///
/// Uses a deterministic "exploration index" derived from selection_history
/// length modulo pool size as the pseudo-random choice — ensures
/// reproducibility and avoids non-determinism in SIL-6 context.
pub fn epsilon_greedy_select(
  pool: StrategyPool,
  epsilon: Float,
) -> SelectionResult {
  let n_strategies = list.length(pool.strategies)
  let history_len = list.length(pool.selection_history)
  // Deterministic exploration trigger: explore when history_len mod period < epsilon * period
  let period = 100
  let threshold = float.round(epsilon *. int.to_float(period))
  let explore = { history_len % period } < threshold
  case explore {
    True -> {
      // Round-robin exploration using history length
      let idx = history_len % n_strategies
      let s = list_at(pool.strategies, idx)
      SelectionResult(
        selected: s,
        reason: "epsilon-greedy: explore (idx=" <> int.to_string(idx) <> ")",
        exploration: True,
      )
    }
    False -> {
      let s = best_fitness_select(pool)
      SelectionResult(
        selected: s,
        reason: "epsilon-greedy: exploit fitness="
          <> float_to_string_2dp(s.fitness),
        exploration: False,
      )
    }
  }
}

// =============================================================================
// Best-fitness selection
// =============================================================================

/// Select the strategy with the highest fitness score.
/// On tie, returns the first in list order.
pub fn best_fitness_select(pool: StrategyPool) -> Strategy {
  case pool.strategies {
    [] ->
      Strategy(
        name: "none",
        domain: "none",
        success_count: 0,
        failure_count: 0,
        fitness: 0.0,
        last_used: 0,
      )
    [first, ..rest] ->
      list.fold(rest, first, fn(best, s) {
        case s.fitness >. best.fitness {
          True -> s
          False -> best
        }
      })
  }
}

// =============================================================================
// Top-K
// =============================================================================

/// Return the top-k strategies by fitness, descending.
pub fn top_k(pool: StrategyPool, k: Int) -> List(Strategy) {
  pool.strategies
  |> list.sort(fn(a, b) {
    case a.fitness >. b.fitness {
      True -> order.Lt
      False ->
        case a.fitness <. b.fitness {
          True -> order.Gt
          False -> order.Eq
        }
    }
  })
  |> list.take(k)
}

// =============================================================================
// Pruning
// =============================================================================

/// Remove strategies with fitness below min_fitness from the pool.
pub fn prune_underperformers(
  pool: StrategyPool,
  min_fitness: Float,
) -> StrategyPool {
  let kept = list.filter(pool.strategies, fn(s) { s.fitness >=. min_fitness })
  StrategyPool(..pool, strategies: kept)
}

// =============================================================================
// Summary
// =============================================================================

/// Produce a human-readable summary of pool state.
pub fn summary(pool: StrategyPool) -> String {
  let n = list.length(pool.strategies)
  let total_trials =
    list.fold(pool.strategies, 0, fn(acc, s) {
      acc + s.success_count + s.failure_count
    })
  let best = best_fitness_select(pool)
  "StrategyPool(gen="
  <> int.to_string(pool.generation)
  <> " strategies="
  <> int.to_string(n)
  <> " total_trials="
  <> int.to_string(total_trials)
  <> " best=["
  <> best.name
  <> " f="
  <> float_to_string_2dp(best.fitness)
  <> "])"
}

// =============================================================================
// Private helpers
// =============================================================================

fn thompson_select(pool: StrategyPool) -> SelectionResult {
  case pool.strategies {
    [] ->
      SelectionResult(
        selected: Strategy(
          name: "none",
          domain: "none",
          success_count: 0,
          failure_count: 0,
          fitness: 0.0,
          last_used: 0,
        ),
        reason: "pool empty",
        exploration: False,
      )
    [first, ..rest] -> {
      let best =
        list.fold(rest, first, fn(best, s) {
          case thompson_sample(s) >. thompson_sample(best) {
            True -> s
            False -> best
          }
        })
      SelectionResult(
        selected: best,
        reason: "thompson: beta_mean="
          <> float_to_string_2dp(thompson_sample(best)),
        exploration: True,
      )
    }
  }
}

fn ucb1_select(pool: StrategyPool) -> SelectionResult {
  let total =
    list.fold(pool.strategies, 0, fn(acc, s) {
      acc + s.success_count + s.failure_count
    })
  case pool.strategies {
    [] ->
      SelectionResult(
        selected: Strategy(
          name: "none",
          domain: "none",
          success_count: 0,
          failure_count: 0,
          fitness: 0.0,
          last_used: 0,
        ),
        reason: "pool empty",
        exploration: False,
      )
    [first, ..rest] -> {
      let best =
        list.fold(rest, first, fn(best, s) {
          case ucb1_score(s, total) >. ucb1_score(best, total) {
            True -> s
            False -> best
          }
        })
      SelectionResult(
        selected: best,
        reason: "ucb1: score=" <> float_to_string_2dp(ucb1_score(best, total)),
        exploration: True,
      )
    }
  }
}

fn list_at(items: List(Strategy), idx: Int) -> Strategy {
  case list.drop(items, idx) {
    [s, ..] -> s
    [] ->
      Strategy(
        name: "none",
        domain: "none",
        success_count: 0,
        failure_count: 0,
        fitness: 0.0,
        last_used: 0,
      )
  }
}

fn float_to_string_2dp(f: Float) -> String {
  let truncated = float.truncate(f *. 100.0)
  let whole = truncated / 100
  let frac = int.absolute_value(truncated % 100)
  int.to_string(whole) <> "." <> pad2(frac)
}

fn pad2(n: Int) -> String {
  case n < 10 {
    True -> "0" <> int.to_string(n)
    False -> int.to_string(n)
  }
}
