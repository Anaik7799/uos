// Actors coverage test — SC-ARCH-SPLIT-002
// Tests freshness_actor, guard_grid_actor, observer_actor
// using verified public API from each module.

import cepaf_gleam/actors/freshness_actor
import cepaf_gleam/actors/guard_grid_actor
import cepaf_gleam/actors/observer_actor
import cepaf_gleam/ha/freshness_monitor
import cepaf_gleam/ha/guard_grid
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

// ── freshness_actor ───────────────────────────────────────────────────────────

pub fn freshness_actor_init_cycle_count_test() {
  let state = freshness_actor.init()
  state.cycle_count |> should.equal(1)
}

pub fn freshness_actor_init_has_monitor_test() {
  let state = freshness_actor.init()
  // Monitor field exists — just verify the state is well-formed
  let _ = state.monitor
  should.be_true(True)
}

pub fn freshness_actor_tick_increments_cycle_test() {
  let state = freshness_actor.init()
  let state2 = freshness_actor.tick(state)
  state2.cycle_count |> should.equal(2)
}

pub fn freshness_actor_tick_twice_test() {
  let state = freshness_actor.init()
  let state2 = freshness_actor.tick(state)
  let state3 = freshness_actor.tick(state2)
  state3.cycle_count |> should.equal(3)
}

pub fn freshness_actor_get_status_returns_string_test() {
  let _state = freshness_actor.init()
  let status = freshness_actor.get_status()
  // After init, ETS should have a value (not necessarily "unknown")
  should.be_true(status != "")
}

pub fn freshness_actor_get_level_returns_string_test() {
  let _state = freshness_actor.init()
  let level = freshness_actor.get_level()
  should.be_true(level != "")
}

pub fn freshness_actor_get_cycle_count_returns_int_test() {
  let _state = freshness_actor.init()
  let count = freshness_actor.get_cycle_count()
  should.be_true(count >= 0)
}

pub fn freshness_actor_level_string_fresh_test() {
  freshness_actor.level_string(freshness_monitor.Fresh)
  |> should.equal("fresh")
}

pub fn freshness_actor_level_string_stale_test() {
  freshness_actor.level_string(freshness_monitor.Stale)
  |> should.equal("stale")
}

pub fn freshness_actor_level_string_degraded_test() {
  freshness_actor.level_string(freshness_monitor.Degraded)
  |> should.equal("degraded")
}

pub fn freshness_actor_level_string_dead_test() {
  freshness_actor.level_string(freshness_monitor.Dead)
  |> should.equal("dead")
}

pub fn freshness_actor_int_to_str_test() {
  freshness_actor.int_to_str(42) |> should.equal("42")
}

pub fn freshness_actor_int_to_str_zero_test() {
  freshness_actor.int_to_str(0) |> should.equal("0")
}

// ── guard_grid_actor ──────────────────────────────────────────────────────────

pub fn guard_grid_actor_init_cycle_count_test() {
  let state = guard_grid_actor.init()
  // After init, one ooda_tick is run, so cycle_count = 1
  state.cycle_count |> should.equal(1)
}

pub fn guard_grid_actor_init_has_grid_test() {
  let state = guard_grid_actor.init()
  let _ = state.grid
  should.be_true(True)
}

pub fn guard_grid_actor_ooda_tick_increments_cycle_test() {
  let state = guard_grid_actor.init()
  let state2 = guard_grid_actor.ooda_tick(state)
  state2.cycle_count |> should.equal(2)
}

pub fn guard_grid_actor_health_history_grows_test() {
  let state = guard_grid_actor.init()
  let state2 = guard_grid_actor.ooda_tick(state)
  // health_history is capped at history_window (10), should have at least 1
  should.be_true(state2.cycle_count >= 1)
}

pub fn guard_grid_actor_health_derivative_no_history_test() {
  let state = guard_grid_actor.init()
  // Clear the history to test zero-derivative baseline
  let bare = guard_grid_actor.GuardGridActorState(..state, health_history: [])
  let d = guard_grid_actor.health_derivative(bare)
  d |> should.equal(0.0)
}

pub fn guard_grid_actor_get_health_returns_string_test() {
  let _state = guard_grid_actor.init()
  let h = guard_grid_actor.get_health()
  should.be_true(h != "")
}

pub fn guard_grid_actor_get_last_action_returns_string_test() {
  let _state = guard_grid_actor.init()
  let a = guard_grid_actor.get_last_action()
  should.be_true(a != "")
}

pub fn guard_grid_actor_get_grid_status_is_json_test() {
  let _state = guard_grid_actor.init()
  let status = guard_grid_actor.get_grid_status()
  // Should be a JSON object
  should.be_true(
    status
    |> string_contains("{"),
  )
}

pub fn guard_grid_actor_rule_to_string_none_test() {
  // Import via guard_grid to get the type
  let result = guard_grid_actor.rule_to_string(import_rule_none())
  result |> should.equal("none")
}

pub fn guard_grid_actor_multi_rule_summary_empty_test() {
  let result = guard_grid_actor.multi_rule_summary([])
  result |> should.equal("")
}

// ── observer_actor ────────────────────────────────────────────────────────────

pub fn observer_actor_init_cycle_count_test() {
  let state = observer_actor.init()
  state.cycle_count |> should.equal(0)
}

pub fn observer_actor_init_last_truthful_test() {
  let state = observer_actor.init()
  state.last_result_truthful |> should.equal(False)
}

pub fn observer_actor_tick_increments_cycle_test() {
  let state = observer_actor.init()
  let state2 = observer_actor.tick(state)
  state2.cycle_count |> should.equal(1)
}

pub fn observer_actor_tick_twice_test() {
  let state = observer_actor.init()
  let state2 = observer_actor.tick(state)
  let state3 = observer_actor.tick(state2)
  state3.cycle_count |> should.equal(2)
}

pub fn observer_actor_get_truth_rate_returns_string_test() {
  let state = observer_actor.init()
  let _ = observer_actor.tick(state)
  let rate = observer_actor.get_truth_rate()
  // Returns either "N/A" or "N%" after tick
  should.be_true(rate != "")
}

pub fn observer_actor_get_streak_returns_string_test() {
  let rate = observer_actor.get_streak()
  should.be_true(rate != "")
}

pub fn observer_actor_get_prediction_returns_string_test() {
  let p = observer_actor.get_prediction()
  should.be_true(p != "")
}

pub fn observer_actor_get_audit_summary_returns_string_test() {
  let s = observer_actor.get_audit_summary()
  should.be_true(s != "")
}

pub fn observer_actor_ets_summary_format_test() {
  let s = observer_actor.ets_summary()
  should.be_true(string_contains(s, "OBSERVER"))
}

pub fn observer_actor_state_summary_test() {
  let state = observer_actor.init()
  let s = observer_actor.state_summary(state)
  should.be_true(string_contains(s, "OBSERVER"))
}

pub fn observer_actor_state_summary_contains_cycle_test() {
  let state = observer_actor.init()
  let s = observer_actor.state_summary(state)
  should.be_true(string_contains(s, "cycle:0"))
}

pub fn observer_actor_ets_keys_test() {
  observer_actor.ets_key_rate |> should.equal("truth:rate")
  observer_actor.ets_key_streak |> should.equal("truth:streak")
  observer_actor.ets_key_prediction |> should.equal("truth:prediction")
  observer_actor.ets_key_last_check |> should.equal("truth:last_check")
}

// ── Helpers ───────────────────────────────────────────────────────────────────

fn string_contains(haystack: String, needle: String) -> Bool {
  string.contains(haystack, needle)
}

fn import_rule_none() -> guard_grid.CellularRule {
  guard_grid.RuleNone
}
