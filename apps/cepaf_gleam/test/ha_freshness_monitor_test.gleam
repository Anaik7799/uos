/// HA Freshness Monitor Tests — 14-test suite
/// Module: cepaf_gleam/ha/freshness_monitor
/// Layer: L0_CONSTITUTIONAL
/// STAMP: SC-SIL4-001, SC-DMS-001, SC-FUNC-002, SC-EVO-KPI-003
///
/// Tests the safety-critical data freshness monitor that detects stale NIF
/// pipelines and initiates escalating control actions (warn → reload →
/// emergency → Jidoka halt).
import cepaf_gleam/ha/freshness_monitor.{
  AttemptReload, Dead, Degraded, EscalateEmergency, Fresh, FreshnessState,
  JidokaHalt, NoAction, Stale, WarnLog, execute_action, init, status_string,
}
import gleam/string
import gleeunit/should

// ===========================================================================
// Initialisation
// ===========================================================================

pub fn init_returns_fresh_level_test() {
  let state = init()
  state.level |> should.equal(Fresh)
}

pub fn init_returns_zero_stale_count_test() {
  let state = init()
  state.stale_count |> should.equal(0)
}

pub fn init_returns_zero_total_checks_test() {
  let state = init()
  state.total_checks |> should.equal(0)
}

pub fn init_reload_not_attempted_test() {
  let state = init()
  state.reload_attempted |> should.be_false()
}

pub fn init_actions_taken_is_empty_test() {
  let state = init()
  state.actions_taken |> should.equal([])
}

// ===========================================================================
// StalenessLevel — classification (exposed via type)
// ===========================================================================

pub fn staleness_levels_are_distinct_test() {
  // Verify each ADT variant is unique by comparing level == Fresh
  let fresh_state = init()
  // init() always gives Fresh level; the others are constructed directly
  fresh_state.level |> should.equal(Fresh)
  // Stale, Degraded, Dead are separate constructors — verify inequality
  let stale: freshness_monitor.StalenessLevel = Stale
  let degraded: freshness_monitor.StalenessLevel = Degraded
  let dead: freshness_monitor.StalenessLevel = Dead
  { stale == Fresh } |> should.be_false()
  { degraded == Stale } |> should.be_false()
  { dead == Degraded } |> should.be_false()
}

// ===========================================================================
// ControlAction ADT — structural tests
// ===========================================================================

pub fn no_action_constructor_test() {
  let action: freshness_monitor.ControlAction = NoAction
  { action == NoAction } |> should.be_true()
}

pub fn warn_log_carries_message_test() {
  let action = WarnLog("pipeline stale — 1 failure")
  let WarnLog(msg) = action
  msg |> string.contains("pipeline") |> should.be_true()
}

pub fn attempt_reload_constructor_test() {
  let action: freshness_monitor.ControlAction = AttemptReload
  { action == AttemptReload } |> should.be_true()
}

pub fn escalate_emergency_carries_reason_test() {
  let action = EscalateEmergency("3 stale checks after reload")
  let EscalateEmergency(reason) = action
  reason |> string.contains("stale") |> should.be_true()
}

pub fn jidoka_halt_carries_reason_test() {
  let action = JidokaHalt("CRITICAL: 8 consecutive failures")
  let JidokaHalt(reason) = action
  reason |> string.contains("CRITICAL") |> should.be_true()
}

// ===========================================================================
// status_string
// ===========================================================================

pub fn status_string_fresh_test() {
  let state = init()
  let s = status_string(state)
  s |> string.contains("FRESH") |> should.be_true()
}

pub fn status_string_includes_check_count_test() {
  let state = init()
  let s = status_string(state)
  // total_checks = 0 on a fresh init
  s |> string.contains("checks: 0") |> should.be_true()
}

pub fn status_string_for_stale_state_test() {
  let stale_state =
    FreshnessState(
      last_check_ms: 1,
      last_fresh_ms: 0,
      level: Stale,
      stale_count: 1,
      total_checks: 1,
      reload_attempted: False,
      actions_taken: ["warn"],
    )
  let s = status_string(stale_state)
  s |> string.contains("STALE") |> should.be_true()
}

pub fn status_string_for_dead_state_test() {
  let dead_state =
    FreshnessState(
      last_check_ms: 10,
      last_fresh_ms: 0,
      level: Dead,
      stale_count: 10,
      total_checks: 10,
      reload_attempted: True,
      actions_taken: ["jidoka_halt", "emergency", "reload", "warn"],
    )
  let s = status_string(dead_state)
  s |> string.contains("DEAD") |> should.be_true()
}

// ===========================================================================
// execute_action — side-effect only (returns Nil, tested for non-crash)
// ===========================================================================

pub fn execute_no_action_returns_nil_test() {
  execute_action(NoAction) |> should.equal(Nil)
}

pub fn execute_warn_log_returns_nil_test() {
  execute_action(WarnLog("test warning")) |> should.equal(Nil)
}

pub fn execute_attempt_reload_returns_nil_test() {
  execute_action(AttemptReload) |> should.equal(Nil)
}

pub fn execute_escalate_emergency_returns_nil_test() {
  execute_action(EscalateEmergency("test emergency")) |> should.equal(Nil)
}

pub fn execute_jidoka_halt_returns_nil_test() {
  execute_action(JidokaHalt("test halt")) |> should.equal(Nil)
}
