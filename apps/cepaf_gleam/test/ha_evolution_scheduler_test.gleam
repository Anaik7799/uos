/// Evolution Scheduler tests — F42 (Autonomous Evolution Scheduling)
/// Layer: L7_FEDERATION
/// SC-ULTRA-001 Focus 9: OpenClaw Ecosystem Integration / Focus 4: Homomorphic UI
/// STAMP: SC-HA-001, SC-GLM-UI-003, SC-MUDA-001, SC-ULTRA-001
///
/// बहूनि मे व्यतीतानि जन्मानि — Many births have passed (Gita 4.5)
import cepaf_gleam/ha/evolution_scheduler.{
  EvolutionFailed, EvolutionNotRun, EvolutionSkipped, EvolutionSuccess,
}
import gleam/list
import gleam/string
import gleeunit/should

// ---------------------------------------------------------------------------
// C1: init — schedule defaults
// ---------------------------------------------------------------------------

pub fn init_sets_interval_hours_test() {
  let s = evolution_scheduler.init(6, 0)
  s.interval_hours |> should.equal(6)
}

pub fn init_enabled_by_default_test() {
  let s = evolution_scheduler.init(6, 0)
  s.enabled |> should.be_true()
}

pub fn init_runs_completed_zero_test() {
  let s = evolution_scheduler.init(6, 0)
  s.runs_completed |> should.equal(0)
}

pub fn init_last_result_not_run_test() {
  let s = evolution_scheduler.init(6, 0)
  s.last_result |> should.equal(EvolutionNotRun)
}

pub fn init_last_run_timestamp_zero_test() {
  let s = evolution_scheduler.init(6, 0)
  s.last_run_timestamp |> should.equal(0)
}

pub fn init_next_run_is_interval_from_now_test() {
  // 6 hours = 21600 seconds; current_time = 1_000_000
  let s = evolution_scheduler.init(6, 1_000_000)
  s.next_run_timestamp |> should.equal(1_021_600)
}

// ---------------------------------------------------------------------------
// C2: should_run
// ---------------------------------------------------------------------------

pub fn should_run_false_before_deadline_test() {
  let s = evolution_scheduler.init(6, 1_000_000)
  evolution_scheduler.should_run(s, 1_000_000) |> should.be_false()
}

pub fn should_run_true_at_deadline_test() {
  let s = evolution_scheduler.init(6, 1_000_000)
  // next_run = 1_021_600
  evolution_scheduler.should_run(s, 1_021_600) |> should.be_true()
}

pub fn should_run_true_after_deadline_test() {
  let s = evolution_scheduler.init(6, 1_000_000)
  evolution_scheduler.should_run(s, 1_100_000) |> should.be_true()
}

pub fn should_run_false_when_disabled_test() {
  let s =
    evolution_scheduler.init(6, 1_000_000)
    |> evolution_scheduler.set_enabled(False)
  evolution_scheduler.should_run(s, 2_000_000) |> should.be_false()
}

// ---------------------------------------------------------------------------
// C3: record_run
// ---------------------------------------------------------------------------

pub fn record_run_success_increments_count_test() {
  let s =
    evolution_scheduler.init(6, 0)
    |> evolution_scheduler.record_run(EvolutionSuccess(3, 45), 21_600)
  s.runs_completed |> should.equal(1)
}

pub fn record_run_failure_does_not_increment_count_test() {
  let s =
    evolution_scheduler.init(6, 0)
    |> evolution_scheduler.record_run(EvolutionFailed("zenoh_down"), 21_600)
  s.runs_completed |> should.equal(0)
}

pub fn record_run_skipped_does_not_increment_count_test() {
  let s =
    evolution_scheduler.init(6, 0)
    |> evolution_scheduler.record_run(EvolutionSkipped("high_cpu"), 21_600)
  s.runs_completed |> should.equal(0)
}

pub fn record_run_advances_next_timestamp_test() {
  let s =
    evolution_scheduler.init(6, 0)
    |> evolution_scheduler.record_run(
      EvolutionSuccess(1, 15),
      // current_time = 21_600 (first interval done)
      21_600,
    )
  // next = 21_600 + 6 * 3600 = 43_200
  s.next_run_timestamp |> should.equal(43_200)
}

pub fn record_run_updates_last_result_test() {
  let result = EvolutionSuccess(5, 90)
  let s =
    evolution_scheduler.init(6, 0)
    |> evolution_scheduler.record_run(result, 21_600)
  s.last_result |> should.equal(result)
}

pub fn record_run_updates_last_run_timestamp_test() {
  let s =
    evolution_scheduler.init(6, 0)
    |> evolution_scheduler.record_run(EvolutionSuccess(1, 10), 21_600)
  s.last_run_timestamp |> should.equal(21_600)
}

// ---------------------------------------------------------------------------
// C4: last_run_failed helper
// ---------------------------------------------------------------------------

pub fn last_run_failed_false_on_success_test() {
  let s =
    evolution_scheduler.init(6, 0)
    |> evolution_scheduler.record_run(EvolutionSuccess(1, 1), 0)
  evolution_scheduler.last_run_failed(s) |> should.be_false()
}

pub fn last_run_failed_true_on_failure_test() {
  let s =
    evolution_scheduler.init(6, 0)
    |> evolution_scheduler.record_run(EvolutionFailed("timeout"), 0)
  evolution_scheduler.last_run_failed(s) |> should.be_true()
}

pub fn last_run_failed_false_on_skipped_test() {
  let s =
    evolution_scheduler.init(6, 0)
    |> evolution_scheduler.record_run(EvolutionSkipped("low_battery"), 0)
  evolution_scheduler.last_run_failed(s) |> should.be_false()
}

// ---------------------------------------------------------------------------
// C5: next_evolution_plan — picks highest priority first
// ---------------------------------------------------------------------------

pub fn next_evolution_plan_returns_p0_test() {
  let plan = evolution_scheduler.next_evolution_plan()
  plan.priority |> should.equal("P0")
}

pub fn next_evolution_plan_target_is_dashboard_test() {
  // dashboard is the first P0 in backlog (highest PageRank)
  let plan = evolution_scheduler.next_evolution_plan()
  plan.target_page |> should.equal("dashboard")
}

pub fn next_evolution_plan_strategy_is_template_test() {
  let plan = evolution_scheduler.next_evolution_plan()
  plan.strategy |> should.equal("template")
}

pub fn next_evolution_plan_has_positive_estimate_test() {
  let plan = evolution_scheduler.next_evolution_plan()
  { plan.estimated_time_seconds > 0 } |> should.be_true()
}

// ---------------------------------------------------------------------------
// C6: all_plans backlog
// ---------------------------------------------------------------------------

pub fn all_plans_has_15_entries_test() {
  list.length(evolution_scheduler.all_plans()) |> should.equal(15)
}

pub fn all_plans_contains_cockpit_test() {
  let names = list.map(evolution_scheduler.all_plans(), fn(p) { p.target_page })
  list.contains(names, "cockpit") |> should.be_true()
}

pub fn all_plans_contains_verification_test() {
  let names = list.map(evolution_scheduler.all_plans(), fn(p) { p.target_page })
  list.contains(names, "verification") |> should.be_true()
}

pub fn all_plans_unique_pages_test() {
  let names = list.map(evolution_scheduler.all_plans(), fn(p) { p.target_page })
  let unique = list.unique(names)
  list.length(unique) |> should.equal(list.length(names))
}

// ---------------------------------------------------------------------------
// C7: to_json
// ---------------------------------------------------------------------------

pub fn to_json_contains_interval_hours_test() {
  let s = evolution_scheduler.init(6, 0)
  string.contains(evolution_scheduler.to_json(s), "interval_hours")
  |> should.be_true()
}

pub fn to_json_contains_runs_completed_test() {
  let s = evolution_scheduler.init(6, 0)
  string.contains(evolution_scheduler.to_json(s), "runs_completed")
  |> should.be_true()
}

pub fn to_json_contains_not_run_test() {
  let s = evolution_scheduler.init(6, 0)
  string.contains(evolution_scheduler.to_json(s), "not_run")
  |> should.be_true()
}

pub fn plan_to_json_contains_target_page_test() {
  let plan = evolution_scheduler.next_evolution_plan()
  string.contains(evolution_scheduler.plan_to_json(plan), "target_page")
  |> should.be_true()
}

// ---------------------------------------------------------------------------
// C8: summary helper
// ---------------------------------------------------------------------------

pub fn summary_contains_enabled_test() {
  let s = evolution_scheduler.init(6, 0)
  string.contains(evolution_scheduler.summary(s), "enabled")
  |> should.be_true()
}

pub fn summary_contains_runs_test() {
  let s = evolution_scheduler.init(6, 0)
  string.contains(evolution_scheduler.summary(s), "runs=")
  |> should.be_true()
}

pub fn seconds_until_next_run_positive_before_deadline_test() {
  let s = evolution_scheduler.init(6, 1_000_000)
  let remaining = evolution_scheduler.seconds_until_next_run(s, 1_000_000)
  { remaining > 0 } |> should.be_true()
}

pub fn seconds_until_next_run_negative_when_overdue_test() {
  let s = evolution_scheduler.init(6, 1_000_000)
  // Well past deadline
  let remaining = evolution_scheduler.seconds_until_next_run(s, 2_000_000)
  { remaining < 0 } |> should.be_true()
}
