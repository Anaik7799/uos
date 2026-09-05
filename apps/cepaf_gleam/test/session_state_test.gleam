// =============================================================================
// session_state_test.gleam — Session State Serialization Tests (DUR-2)
// =============================================================================
// Tests for ha/session_state.gleam
//
// Coverage categories addressed:
//   C1 Page Structure  — from_app_state() returns valid zero-state
//   C2 Status Badges   — summary() reflects all fields
//   C3 Data Grids      — to_json() produces parseable output
//   C4 Timeline        — timestamp_ms roundtrips correctly
//   C5 Interactive     — from_json(to_json(s)) == Ok(s) round-trip
//   C6 Media/Rich      — health_to_millis/millis_to_health conversion
//   C7 AI Advisory     — from_json gracefully rejects malformed input
//   C8 Action Button   — checkpoint_count survives serialization
//
// STAMP: SC-FUNC-004, SC-HA-001, SC-MUDA-001, SC-ARCH-SPLIT-002
// Layer: L3_TRANSACTION
// =============================================================================

import cepaf_gleam/ha/session_state
import gleam/string
import gleeunit/should

// =============================================================================
// C1 — from_app_state structure
// =============================================================================

pub fn init_session_id_preserved_test() {
  session_state.from_app_state("sess-001", 1_000_000)
  |> fn(s) { s.session_id }
  |> should.equal("sess-001")
}

pub fn init_timestamp_ms_preserved_test() {
  session_state.from_app_state("s", 99_999)
  |> fn(s) { s.timestamp_ms }
  |> should.equal(99_999)
}

pub fn init_freshness_cycle_zero_test() {
  session_state.from_app_state("s", 0)
  |> fn(s) { s.freshness_cycle }
  |> should.equal(0)
}

pub fn init_observer_cycle_zero_test() {
  session_state.from_app_state("s", 0)
  |> fn(s) { s.observer_cycle }
  |> should.equal(0)
}

pub fn init_guard_grid_cycle_zero_test() {
  session_state.from_app_state("s", 0)
  |> fn(s) { s.guard_grid_cycle }
  |> should.equal(0)
}

pub fn init_health_score_millis_nominal_test() {
  // nominal health = 1000 (= 1.0 = 100%)
  session_state.from_app_state("s", 0)
  |> fn(s) { s.health_score_millis }
  |> should.equal(1000)
}

pub fn init_cockpit_mode_dark_test() {
  session_state.from_app_state("s", 0)
  |> fn(s) { s.cockpit_mode }
  |> should.equal("dark")
}

pub fn init_checkpoint_count_zero_test() {
  session_state.from_app_state("s", 0)
  |> fn(s) { s.checkpoint_count }
  |> should.equal(0)
}

// =============================================================================
// C3 — to_json produces valid output
// =============================================================================

pub fn to_json_contains_session_id_test() {
  let s = session_state.from_app_state("my-session", 12_345)
  let json = session_state.to_json(s)
  json
  |> string.contains("my-session")
  |> should.be_true()
}

pub fn to_json_contains_timestamp_test() {
  let s = session_state.from_app_state("s", 98_765)
  let json = session_state.to_json(s)
  json
  |> string.contains("98765")
  |> should.be_true()
}

pub fn to_json_contains_cockpit_mode_test() {
  let s = session_state.from_app_state("s", 0)
  let json = session_state.to_json(s)
  json
  |> string.contains("dark")
  |> should.be_true()
}

pub fn to_json_is_non_empty_test() {
  let s = session_state.from_app_state("x", 1)
  session_state.to_json(s)
  |> string.length()
  |> fn(n) { n > 0 }
  |> should.be_true()
}

pub fn to_json_starts_with_brace_test() {
  let s = session_state.from_app_state("x", 1)
  session_state.to_json(s)
  |> string.starts_with("{")
  |> should.be_true()
}

pub fn to_json_ends_with_brace_test() {
  let s = session_state.from_app_state("x", 1)
  session_state.to_json(s)
  |> string.ends_with("}")
  |> should.be_true()
}

// =============================================================================
// C5 — round-trip: from_json(to_json(s)) == Ok(s)
// =============================================================================

pub fn roundtrip_session_id_test() {
  let s = session_state.from_app_state("roundtrip-id", 42_000)
  let json = session_state.to_json(s)
  case session_state.from_json(json) {
    Ok(recovered) -> recovered.session_id |> should.equal("roundtrip-id")
    Error(_) -> should.fail()
  }
}

pub fn roundtrip_timestamp_ms_test() {
  let s = session_state.from_app_state("s", 1_700_000_000_000)
  let json = session_state.to_json(s)
  case session_state.from_json(json) {
    Ok(r) -> r.timestamp_ms |> should.equal(1_700_000_000_000)
    Error(_) -> should.fail()
  }
}

pub fn roundtrip_health_score_millis_test() {
  let base = session_state.from_app_state("s", 0)
  let s = session_state.SerializedState(..base, health_score_millis: 720)
  let json = session_state.to_json(s)
  case session_state.from_json(json) {
    Ok(r) -> r.health_score_millis |> should.equal(720)
    Error(_) -> should.fail()
  }
}

pub fn roundtrip_checkpoint_count_test() {
  let base = session_state.from_app_state("s", 0)
  let s = session_state.SerializedState(..base, checkpoint_count: 17)
  let json = session_state.to_json(s)
  case session_state.from_json(json) {
    Ok(r) -> r.checkpoint_count |> should.equal(17)
    Error(_) -> should.fail()
  }
}

pub fn roundtrip_cockpit_mode_test() {
  let base = session_state.from_app_state("s", 0)
  let s = session_state.SerializedState(..base, cockpit_mode: "emergency")
  let json = session_state.to_json(s)
  case session_state.from_json(json) {
    Ok(r) -> r.cockpit_mode |> should.equal("emergency")
    Error(_) -> should.fail()
  }
}

// =============================================================================
// C6 — health_to_millis / millis_to_health
// =============================================================================

pub fn health_to_millis_nominal_test() {
  session_state.health_to_millis(1.0)
  |> should.equal(1000)
}

pub fn health_to_millis_zero_test() {
  session_state.health_to_millis(0.0)
  |> should.equal(0)
}

pub fn millis_to_health_nominal_test() {
  let h = session_state.millis_to_health(1000)
  // 1000 / 1000.0 = 1.0
  h
  |> should.equal(1.0)
}

pub fn millis_to_health_partial_test() {
  let h = session_state.millis_to_health(500)
  h
  |> should.equal(0.5)
}

// =============================================================================
// C7 — from_json rejects malformed input
// =============================================================================

pub fn from_json_empty_string_returns_error_test() {
  session_state.from_json("")
  |> should.be_error()
}

pub fn from_json_partial_json_returns_error_test() {
  session_state.from_json("{\"session_id\":\"only-one-field\"}")
  |> should.be_error()
}

// =============================================================================
// C2 — summary()
// =============================================================================

pub fn summary_contains_session_id_test() {
  let s = session_state.from_app_state("my-sess", 0)
  session_state.summary(s)
  |> string.contains("my-sess")
  |> should.be_true()
}

pub fn summary_contains_cockpit_mode_test() {
  let s = session_state.from_app_state("s", 0)
  session_state.summary(s)
  |> string.contains("dark")
  |> should.be_true()
}

pub fn summary_is_non_empty_test() {
  let s = session_state.from_app_state("s", 1)
  session_state.summary(s)
  |> string.length()
  |> fn(n) { n > 0 }
  |> should.be_true()
}
