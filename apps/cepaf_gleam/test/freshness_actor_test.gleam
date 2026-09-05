// =============================================================================
// freshness_actor_test.gleam — OTP Freshness Monitor Actor Tests
// =============================================================================
//
// Tests the FreshnessActorState lifecycle:
//   init/0         — first check cycle + ETS population
//   tick/1         — subsequent cycle + ETS update + cycle_count increment
//   get_status/0   — ETS read-path
//   get_level/0    — ETS read-path
//   get_cycle_count/0 — ETS read-path with int parsing
//   level_string/1 — pure mapping for all four StalenessLevel variants
//   int_to_str/1   — pure int formatter
//
// Layer:  L0_CONSTITUTIONAL
// STAMP:  SC-SIL4-001, SC-DMS-001, SC-FUNC-002, SC-FUNC-004, SC-MUDA-001
//
// सदा जाग्रत — Always awake
// =============================================================================

import cepaf_gleam/actors/freshness_actor
import cepaf_gleam/ha/freshness_monitor
import cepaf_gleam/substrate/beam_cache
import gleam/int
import gleam/string
import gleeunit/should

// =============================================================================
// init/0 — first cycle bootstrap
// =============================================================================

pub fn init_returns_actor_state_test() {
  // init() must return a FreshnessActorState without crashing.
  let state = freshness_actor.init()
  // cycle_count starts at 1 after the first check.
  state.cycle_count |> should.equal(1)
}

pub fn init_populates_ets_status_test() {
  // After init(), the ETS key freshness:status must be set.
  let _ = freshness_actor.init()
  let status = freshness_actor.get_status()
  // Must not be the fallback "unknown" value.
  status |> should.not_equal("unknown")
}

pub fn init_populates_ets_level_test() {
  // After init(), freshness:level must hold one of the known values.
  let _ = freshness_actor.init()
  let level = freshness_actor.get_level()
  let valid =
    level == "fresh"
    || level == "stale"
    || level == "degraded"
    || level == "dead"
  valid |> should.be_true()
}

pub fn init_populates_ets_cycles_test() {
  // After init(), freshness:cycles must be "1".
  let _ = freshness_actor.init()
  let count = freshness_actor.get_cycle_count()
  count |> should.equal(1)
}

// =============================================================================
// tick/1 — subsequent cycles
// =============================================================================

pub fn tick_increments_cycle_count_test() {
  let state = freshness_actor.init()
  let state2 = freshness_actor.tick(state)
  state2.cycle_count |> should.equal(2)
}

pub fn tick_twice_increments_to_three_test() {
  let state = freshness_actor.init()
  let state2 = freshness_actor.tick(state)
  let state3 = freshness_actor.tick(state2)
  state3.cycle_count |> should.equal(3)
}

pub fn tick_updates_ets_cycles_test() {
  let state = freshness_actor.init()
  let _state2 = freshness_actor.tick(state)
  // ETS freshness:cycles must now be >= 2.
  let count = freshness_actor.get_cycle_count()
  { count >= 2 } |> should.be_true()
}

pub fn tick_preserves_valid_level_test() {
  let state = freshness_actor.init()
  let _state2 = freshness_actor.tick(state)
  let level = freshness_actor.get_level()
  let valid =
    level == "fresh"
    || level == "stale"
    || level == "degraded"
    || level == "dead"
  valid |> should.be_true()
}

pub fn tick_status_is_non_empty_test() {
  let state = freshness_actor.init()
  let _state2 = freshness_actor.tick(state)
  let status = freshness_actor.get_status()
  { string.length(status) > 0 } |> should.be_true()
}

// =============================================================================
// get_status/0 — fallback when ETS not initialised
// =============================================================================

pub fn get_status_returns_unknown_without_init_test() {
  // Remove the key to simulate a cold ETS, then verify fallback.
  let _ = beam_cache.init()
  let _ = beam_cache.delete("freshness:status")
  freshness_actor.get_status() |> should.equal("unknown")
}

// =============================================================================
// get_level/0 — fallback path
// =============================================================================

pub fn get_level_returns_unknown_without_init_test() {
  let _ = beam_cache.init()
  let _ = beam_cache.delete("freshness:level")
  freshness_actor.get_level() |> should.equal("unknown")
}

// =============================================================================
// get_cycle_count/0 — fallback and parse
// =============================================================================

pub fn get_cycle_count_returns_zero_without_init_test() {
  let _ = beam_cache.init()
  let _ = beam_cache.delete("freshness:cycles")
  freshness_actor.get_cycle_count() |> should.equal(0)
}

pub fn get_cycle_count_returns_zero_on_corrupt_value_test() {
  let _ = beam_cache.init()
  let _ = beam_cache.put("freshness:cycles", "not-a-number")
  freshness_actor.get_cycle_count() |> should.equal(0)
}

// =============================================================================
// level_string/1 — pure mapping, all four variants
// =============================================================================

pub fn level_string_fresh_test() {
  freshness_actor.level_string(freshness_monitor.Fresh)
  |> should.equal("fresh")
}

pub fn level_string_stale_test() {
  freshness_actor.level_string(freshness_monitor.Stale)
  |> should.equal("stale")
}

pub fn level_string_degraded_test() {
  freshness_actor.level_string(freshness_monitor.Degraded)
  |> should.equal("degraded")
}

pub fn level_string_dead_test() {
  freshness_actor.level_string(freshness_monitor.Dead)
  |> should.equal("dead")
}

// =============================================================================
// int_to_str/1 — pure formatter
// =============================================================================

pub fn int_to_str_zero_test() {
  freshness_actor.int_to_str(0) |> should.equal("0")
}

pub fn int_to_str_positive_test() {
  freshness_actor.int_to_str(42) |> should.equal("42")
}

pub fn int_to_str_roundtrips_test() {
  let n = 9999
  let s = freshness_actor.int_to_str(n)
  case int.parse(s) {
    Ok(parsed) -> parsed |> should.equal(n)
    Error(_) -> should.fail()
  }
}

// =============================================================================
// ETS integration — status_string mirrors freshness_monitor format
// =============================================================================

pub fn status_string_contains_checks_test() {
  let state = freshness_actor.init()
  let status = freshness_monitor.status_string(state.monitor)
  // The canonical status_string always contains "checks:"
  status |> string.contains("checks:") |> should.be_true()
}

pub fn status_string_contains_stale_count_test() {
  let state = freshness_actor.init()
  let status = freshness_monitor.status_string(state.monitor)
  status |> string.contains("stale_count:") |> should.be_true()
}
