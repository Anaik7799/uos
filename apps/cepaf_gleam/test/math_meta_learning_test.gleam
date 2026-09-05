/// META-1 Meta-Learning Strategy Pool — 15-test suite
/// Layer: L5_COGNITIVE
/// STAMP: SC-BIO-EVO-006, SC-MATH-001, SC-OODA-001, SC-MUDA-001
///
/// Covers:
///   pool construction + selection_history init         (META-1)
///   best_fitness_select greedy behaviour               (META-2)
///   record_outcome EMA update for success/failure      (META-3)
///   ucb1_score exploration bonus formula               (META-4)
///   thompson_sample Beta mean approximation            (META-5)
///   epsilon_greedy explore vs exploit branch           (META-6)
///   top_k descending sort                              (META-7)
///   prune_underperformers threshold gate               (META-8)
///   summary string content                             (META-9)
///   select/2 dispatcher for each SelectionPolicy       (META-10)
import cepaf_gleam/math/meta_learning.{
  BestFitness, Strategy, ThompsonSampling, UCB1, best_fitness_select,
  epsilon_greedy_select, pool_new, prune_underperformers, record_outcome, select,
  summary, thompson_sample, top_k, ucb1_score,
}
import gleam/list
import gleam/string
import gleeunit/should

// ===========================================================================
// Helpers
// ===========================================================================

fn make_strategy(name: String, fitness: Float) {
  Strategy(
    name: name,
    domain: "test",
    success_count: 5,
    failure_count: 2,
    fitness: fitness,
    last_used: 0,
  )
}

fn sample_pool() {
  pool_new([
    make_strategy("alpha", 0.8),
    make_strategy("beta", 0.5),
    make_strategy("gamma", 0.3),
  ])
}

// ===========================================================================
// pool_new — construction (META-1)
// ===========================================================================

pub fn pool_new_generation_zero_test() {
  let p = pool_new([make_strategy("s1", 0.5)])
  p.generation |> should.equal(0)
}

pub fn pool_new_empty_history_test() {
  let p = pool_new([make_strategy("s1", 0.5)])
  p.selection_history |> should.equal([])
}

pub fn pool_new_preserves_strategy_count_test() {
  let p = sample_pool()
  list.length(p.strategies) |> should.equal(3)
}

// ===========================================================================
// best_fitness_select (META-2)
// ===========================================================================

pub fn best_fitness_returns_highest_test() {
  let p = sample_pool()
  let s = best_fitness_select(p)
  s.name |> should.equal("alpha")
}

pub fn best_fitness_single_element_test() {
  let p = pool_new([make_strategy("only", 0.42)])
  let s = best_fitness_select(p)
  s.name |> should.equal("only")
}

// ===========================================================================
// record_outcome EMA (META-3)
// ===========================================================================

pub fn record_outcome_success_increments_count_test() {
  let p = pool_new([make_strategy("alpha", 0.5)])
  let updated = record_outcome(p, "alpha", True)
  let s = best_fitness_select(updated)
  s.success_count |> should.equal(6)
}

pub fn record_outcome_failure_increments_failure_count_test() {
  let p = pool_new([make_strategy("alpha", 0.5)])
  let updated = record_outcome(p, "alpha", False)
  let s = best_fitness_select(updated)
  s.failure_count |> should.equal(3)
}

pub fn record_outcome_increments_generation_test() {
  let p = sample_pool()
  let updated = record_outcome(p, "alpha", True)
  updated.generation |> should.equal(1)
}

pub fn record_outcome_ema_success_raises_fitness_test() {
  let initial_fitness = 0.5
  let p = pool_new([make_strategy("alpha", initial_fitness)])
  let updated = record_outcome(p, "alpha", True)
  // EMA: 0.1 * 1.0 + 0.9 * 0.5 = 0.1 + 0.45 = 0.55
  let s = best_fitness_select(updated)
  let ok = s.fitness >. initial_fitness
  ok |> should.be_true
}

pub fn record_outcome_ema_failure_lowers_fitness_test() {
  let initial_fitness = 0.5
  let p = pool_new([make_strategy("alpha", initial_fitness)])
  let updated = record_outcome(p, "alpha", False)
  // EMA: 0.1 * 0.0 + 0.9 * 0.5 = 0.0 + 0.45 = 0.45
  let s = best_fitness_select(updated)
  let ok = s.fitness <. initial_fitness
  ok |> should.be_true
}

// ===========================================================================
// ucb1_score (META-4)
// ===========================================================================

pub fn ucb1_score_exceeds_fitness_test() {
  let s = make_strategy("s", 0.5)
  let score = ucb1_score(s, 100)
  let ok = score >. 0.5
  ok |> should.be_true
}

pub fn ucb1_score_with_total_one_test() {
  let s = make_strategy("s", 0.3)
  // Should not crash with total=1
  let score = ucb1_score(s, 1)
  let ok = score >=. 0.0
  ok |> should.be_true
}

// ===========================================================================
// thompson_sample (META-5)
// ===========================================================================

pub fn thompson_sample_range_test() {
  let s = make_strategy("s", 0.5)
  let score = thompson_sample(s)
  let ok = score >. 0.0 && score <. 1.0
  ok |> should.be_true
}

pub fn thompson_sample_more_successes_higher_score_test() {
  let winner =
    Strategy(
      name: "w",
      domain: "d",
      success_count: 90,
      failure_count: 5,
      fitness: 0.5,
      last_used: 0,
    )
  let loser =
    Strategy(
      name: "l",
      domain: "d",
      success_count: 5,
      failure_count: 90,
      fitness: 0.5,
      last_used: 0,
    )
  let ok = thompson_sample(winner) >. thompson_sample(loser)
  ok |> should.be_true
}

// ===========================================================================
// top_k (META-7)
// ===========================================================================

pub fn top_k_returns_correct_count_test() {
  let p = sample_pool()
  let result = top_k(p, 2)
  list.length(result) |> should.equal(2)
}

pub fn top_k_first_is_best_test() {
  let p = sample_pool()
  let result = top_k(p, 3)
  case result {
    [first, ..] -> first.name |> should.equal("alpha")
    [] -> should.fail()
  }
}

// ===========================================================================
// prune_underperformers (META-8)
// ===========================================================================

pub fn prune_removes_low_fitness_test() {
  let p = sample_pool()
  let pruned = prune_underperformers(p, 0.5)
  list.length(pruned.strategies) |> should.equal(2)
}

pub fn prune_keeps_all_above_threshold_test() {
  let p = pool_new([make_strategy("a", 0.9), make_strategy("b", 0.8)])
  let pruned = prune_underperformers(p, 0.5)
  list.length(pruned.strategies) |> should.equal(2)
}

// ===========================================================================
// summary (META-9)
// ===========================================================================

pub fn summary_contains_gen_test() {
  let p = sample_pool()
  let s = summary(p)
  string.contains(s, "gen=0") |> should.be_true
}

pub fn summary_contains_strategy_count_test() {
  let p = sample_pool()
  let s = summary(p)
  string.contains(s, "strategies=3") |> should.be_true
}

// ===========================================================================
// select/2 dispatcher (META-10)
// ===========================================================================

pub fn select_best_fitness_appends_history_test() {
  let p = sample_pool()
  let #(updated, result) = select(p, BestFitness)
  result.selected.name |> should.equal("alpha")
  result.exploration |> should.be_false
  list.length(updated.selection_history) |> should.equal(1)
}

pub fn select_ucb1_returns_exploration_true_test() {
  let p = sample_pool()
  let #(_, result) = select(p, UCB1)
  result.exploration |> should.be_true
}

pub fn select_thompson_returns_exploration_true_test() {
  let p = sample_pool()
  let #(_, result) = select(p, ThompsonSampling)
  result.exploration |> should.be_true
}

pub fn select_empty_pool_returns_none_test() {
  let p = pool_new([])
  let #(_, result) = select(p, BestFitness)
  result.selected.name |> should.equal("none")
}

pub fn select_epsilon_greedy_exploit_test() {
  // epsilon=0.0 means always exploit
  let p = sample_pool()
  let result = epsilon_greedy_select(p, 0.0)
  result.exploration |> should.be_false
  result.selected.name |> should.equal("alpha")
}
