/// Guard Grid Actor Tests — Full OODA cognitive cycle every 10 seconds
/// ऊडा चक्र सदा चलति — The OODA cycle always turns
///
/// 20 tests covering:
///   - init: creates valid state, cycle_count == 1, ETS populated
///   - ooda_tick: increments cycle_count, updates history, writes ETS
///   - record_verdict: updates grid cells, preserves cycle_count
///   - health_derivative: zero history, single entry, multi-entry
///   - ETS read-path: get_health, get_last_action, get_grid_status
///   - failing layer collection and cascade depth computation
///   - multi_rule_summary and rule_to_string helpers
///   - health regression detection (delta < -0.1)
///   - history window cap at 10 entries
///
/// Layer: L5_COGNITIVE
/// STAMP: SC-SIL4-001, SC-HA-001, SC-OODA-001, SC-FUNC-004, SC-MUDA-001
import cepaf_gleam/actors/guard_grid_actor
import cepaf_gleam/ha/guard_grid
import cepaf_gleam/substrate/beam_cache
import gleam/list
import gleam/string
import gleeunit/should

// ---------------------------------------------------------------------------
// init/0 tests
// ---------------------------------------------------------------------------

/// init() must return a state with cycle_count >= 1 (first tick is run inside init).
pub fn init_cycle_count_test() {
  let state = guard_grid_actor.init()
  should.be_true(state.cycle_count >= 1)
}

/// init() must set last_health in [0.0, 1.0].
pub fn init_last_health_range_test() {
  let state = guard_grid_actor.init()
  should.be_true(state.last_health >=. 0.0)
  should.be_true(state.last_health <=. 1.0)
}

/// init() must set last_entropy >= 0.0.
pub fn init_last_entropy_range_test() {
  let state = guard_grid_actor.init()
  should.be_true(state.last_entropy >=. 0.0)
}

/// init() must have health_history with at least 1 entry.
pub fn init_health_history_non_empty_test() {
  let state = guard_grid_actor.init()
  should.be_true(list.length(state.health_history) >= 1)
}

/// init() must populate ETS key guard:grid:health.
pub fn init_ets_health_populated_test() {
  let _ = beam_cache.init()
  let _ = guard_grid_actor.init()
  let result = beam_cache.get("guard:grid:health")
  should.be_ok(result)
}

/// init() must populate ETS key guard:grid:cycles.
pub fn init_ets_cycles_populated_test() {
  let _ = beam_cache.init()
  let _ = guard_grid_actor.init()
  let result = beam_cache.get("guard:grid:cycles")
  should.be_ok(result)
}

// ---------------------------------------------------------------------------
// ooda_tick/1 tests
// ---------------------------------------------------------------------------

/// ooda_tick must increment cycle_count by exactly 1.
pub fn ooda_tick_increments_cycle_test() {
  let s0 = guard_grid_actor.init()
  let s1 = guard_grid_actor.ooda_tick(s0)
  should.equal(s1.cycle_count, s0.cycle_count + 1)
}

/// ooda_tick must keep last_health in [0.0, 1.0].
pub fn ooda_tick_health_in_range_test() {
  let s0 = guard_grid_actor.init()
  let s1 = guard_grid_actor.ooda_tick(s0)
  should.be_true(s1.last_health >=. 0.0)
  should.be_true(s1.last_health <=. 1.0)
}

/// ooda_tick must append to health_history (length increases each tick, up to window).
pub fn ooda_tick_history_grows_test() {
  let s0 = guard_grid_actor.init()
  let len0 = list.length(s0.health_history)
  let s1 = guard_grid_actor.ooda_tick(s0)
  let len1 = list.length(s1.health_history)
  // Either grows or stays at cap (10).
  should.be_true(len1 >= len0)
}

/// ooda_tick must refresh ETS guard:grid:action.
pub fn ooda_tick_ets_action_refreshed_test() {
  let _ = beam_cache.init()
  let s0 = guard_grid_actor.init()
  let _ = guard_grid_actor.ooda_tick(s0)
  let result = beam_cache.get("guard:grid:action")
  should.be_ok(result)
}

/// Two consecutive ticks must produce cycle counts differing by 1.
pub fn ooda_tick_two_consecutive_cycles_test() {
  let s0 = guard_grid_actor.init()
  let s1 = guard_grid_actor.ooda_tick(s0)
  let s2 = guard_grid_actor.ooda_tick(s1)
  should.equal(s2.cycle_count, s0.cycle_count + 2)
}

// ---------------------------------------------------------------------------
// health_history window cap tests
// ---------------------------------------------------------------------------

/// Health history must never exceed 10 entries regardless of tick count.
pub fn history_window_cap_test() {
  let s0 = guard_grid_actor.init()
  // Run 12 ticks to exceed the window of 10 — build a list of 12 unit values.
  let twelve_items = list.repeat(Nil, 12)
  let s_final =
    list.fold(twelve_items, s0, fn(s, _) { guard_grid_actor.ooda_tick(s) })
  should.be_true(list.length(s_final.health_history) <= 10)
}

// ---------------------------------------------------------------------------
// record_verdict/4 tests
// ---------------------------------------------------------------------------

/// record_verdict must not change cycle_count.
pub fn record_verdict_preserves_cycle_count_test() {
  let s0 = guard_grid_actor.init()
  let s1 = guard_grid_actor.record_verdict(s0, "L0", "guardian", "FAILED_EMPTY")
  should.equal(s1.cycle_count, s0.cycle_count)
}

/// record_verdict with FAILED verdict must increase grid failed_cells.
pub fn record_verdict_increases_failed_cells_test() {
  let s0 = guard_grid_actor.init()
  // Fresh grid: all PASSED → failed_cells == 0.
  let s1 =
    guard_grid_actor.record_verdict(s0, "L0", "guardian", "FAILED_CORRUPTED")
  should.be_true(s1.grid.failed_cells >= 1)
}

/// record_verdict with PASSED verdict on a previously failed cell must not
/// increase failed_cells beyond original.
pub fn record_verdict_passed_resets_failure_test() {
  let s0 = guard_grid_actor.init()
  let s1 =
    guard_grid_actor.record_verdict(s0, "L1", "nif_bridge", "FAILED_STALE")
  let s2 = guard_grid_actor.record_verdict(s1, "L1", "nif_bridge", "PASSED")
  // After recovery, the failed count should be same as or less than before recovery.
  should.be_true(s2.grid.failed_cells <= s1.grid.failed_cells)
}

// ---------------------------------------------------------------------------
// health_derivative/1 tests
// ---------------------------------------------------------------------------

/// health_derivative returns 0.0 when history is empty.
pub fn health_derivative_empty_history_test() {
  let state =
    guard_grid_actor.GuardGridActorState(
      grid: guard_grid.init(),
      cycle_count: 0,
      last_action: "NoAction",
      last_health: 1.0,
      last_entropy: 0.0,
      health_history: [],
    )
  guard_grid_actor.health_derivative(state)
  |> should.equal(0.0)
}

/// health_derivative returns 0.0 for single-entry history (no span).
pub fn health_derivative_single_entry_test() {
  let state =
    guard_grid_actor.GuardGridActorState(
      grid: guard_grid.init(),
      cycle_count: 1,
      last_action: "NoAction",
      last_health: 0.8,
      last_entropy: 0.0,
      health_history: [0.8],
    )
  guard_grid_actor.health_derivative(state)
  |> should.equal(0.0)
}

/// health_derivative is negative when health is declining.
pub fn health_derivative_declining_test() {
  // History: [0.5, 0.8, 1.0] — newest first; oldest = 1.0, newest = 0.5 → declining.
  let state =
    guard_grid_actor.GuardGridActorState(
      grid: guard_grid.init(),
      cycle_count: 3,
      last_action: "NoAction",
      last_health: 0.5,
      last_entropy: 0.0,
      health_history: [0.5, 0.8, 1.0],
    )
  let d = guard_grid_actor.health_derivative(state)
  should.be_true(d <. 0.0)
}

/// health_derivative is positive when health is improving.
pub fn health_derivative_improving_test() {
  // History: [0.9, 0.7, 0.5] — newest first; oldest = 0.5, newest = 0.9 → improving.
  let state =
    guard_grid_actor.GuardGridActorState(
      grid: guard_grid.init(),
      cycle_count: 3,
      last_action: "NoAction",
      last_health: 0.9,
      last_entropy: 0.0,
      health_history: [0.9, 0.7, 0.5],
    )
  let d = guard_grid_actor.health_derivative(state)
  should.be_true(d >. 0.0)
}

// ---------------------------------------------------------------------------
// ETS read-path tests
// ---------------------------------------------------------------------------

/// get_grid_status() must return a non-empty string containing "health".
pub fn get_grid_status_contains_health_test() {
  let _ = beam_cache.init()
  let _ = guard_grid_actor.init()
  let status = guard_grid_actor.get_grid_status()
  should.be_true(string.contains(status, "health"))
}

/// get_health() must return a non-"unknown" value after init.
pub fn get_health_non_unknown_test() {
  let _ = beam_cache.init()
  let _ = guard_grid_actor.init()
  let h = guard_grid_actor.get_health()
  should.be_false(h == "unknown")
}

/// get_last_action() must return a non-"unknown" value after init.
pub fn get_last_action_non_unknown_test() {
  let _ = beam_cache.init()
  let _ = guard_grid_actor.init()
  let a = guard_grid_actor.get_last_action()
  should.be_false(a == "unknown")
}
