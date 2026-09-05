/// Canary Controller tests — F09 (Canary Deployment via Zenoh)
/// Layer: L7_FEDERATION
/// SC-ULTRA-001 Focus 10: HA Seamless Upgrades, Focus 1: Decentralized Ignition
/// STAMP: SC-HA-001, SC-SIL4-011, SC-FUNC-003
import cepaf_gleam/ha/canary_controller.{
  CanaryExpanding, CanaryHalfway, CanaryIdle, CanaryMajority, CanaryPromoting,
  CanaryRollingBack, CanaryStarted,
}
import gleam/string
import gleeunit/should

// ---------------------------------------------------------------------------
// init/2
// ---------------------------------------------------------------------------

pub fn init_sets_canary_version_test() {
  let state = canary_controller.init("v2", "v1")
  state.canary_version |> should.equal("v2")
}

pub fn init_sets_stable_version_test() {
  let state = canary_controller.init("v2", "v1")
  state.stable_version |> should.equal("v1")
}

pub fn init_starts_idle_test() {
  let state = canary_controller.init("v2", "v1")
  state.phase |> should.equal(CanaryIdle)
}

pub fn init_traffic_pct_is_zero_test() {
  let state = canary_controller.init("v2", "v1")
  state.traffic_pct |> should.equal(0)
}

pub fn init_counters_are_zero_test() {
  let state = canary_controller.init("v2", "v1")
  state.health_checks_passed |> should.equal(0)
  state.health_checks_failed |> should.equal(0)
}

pub fn init_promotion_threshold_is_99pct_test() {
  let state = canary_controller.init("v2", "v1")
  state.promotion_threshold |> should.equal(0.99)
}

// ---------------------------------------------------------------------------
// advance/1 — forward transitions
// ---------------------------------------------------------------------------

pub fn advance_idle_to_started_test() {
  let state = canary_controller.init("v2", "v1") |> canary_controller.advance()
  state.phase |> should.equal(CanaryStarted)
  state.traffic_pct |> should.equal(5)
}

pub fn advance_started_to_expanding_test() {
  let state =
    canary_controller.init("v2", "v1")
    |> canary_controller.advance()
    |> canary_controller.advance()
  state.phase |> should.equal(CanaryExpanding)
  state.traffic_pct |> should.equal(25)
}

pub fn advance_expanding_to_halfway_test() {
  let state =
    canary_controller.init("v2", "v1")
    |> canary_controller.advance()
    |> canary_controller.advance()
    |> canary_controller.advance()
  state.phase |> should.equal(CanaryHalfway)
  state.traffic_pct |> should.equal(50)
}

pub fn advance_halfway_to_majority_test() {
  let state =
    canary_controller.init("v2", "v1")
    |> canary_controller.advance()
    |> canary_controller.advance()
    |> canary_controller.advance()
    |> canary_controller.advance()
  state.phase |> should.equal(CanaryMajority)
  state.traffic_pct |> should.equal(75)
}

pub fn advance_majority_to_promoting_test() {
  let state =
    canary_controller.init("v2", "v1")
    |> canary_controller.advance()
    |> canary_controller.advance()
    |> canary_controller.advance()
    |> canary_controller.advance()
    |> canary_controller.advance()
  state.phase |> should.equal(CanaryPromoting)
  state.traffic_pct |> should.equal(100)
}

pub fn advance_promoting_is_noop_test() {
  let promoting =
    canary_controller.init("v2", "v1")
    |> canary_controller.advance()
    |> canary_controller.advance()
    |> canary_controller.advance()
    |> canary_controller.advance()
    |> canary_controller.advance()
  let after = canary_controller.advance(promoting)
  after.phase |> should.equal(CanaryPromoting)
}

pub fn advance_rolling_back_is_noop_test() {
  let rb =
    canary_controller.init("v2", "v1")
    |> canary_controller.trigger_rollback()
  let after = canary_controller.advance(rb)
  after.phase |> should.equal(CanaryRollingBack)
}

// ---------------------------------------------------------------------------
// record_health/2
// ---------------------------------------------------------------------------

pub fn record_health_passed_increments_passed_test() {
  let state =
    canary_controller.init("v2", "v1")
    |> canary_controller.record_health(True)
  state.health_checks_passed |> should.equal(1)
  state.health_checks_failed |> should.equal(0)
}

pub fn record_health_failed_increments_failed_test() {
  let state =
    canary_controller.init("v2", "v1")
    |> canary_controller.record_health(False)
  state.health_checks_passed |> should.equal(0)
  state.health_checks_failed |> should.equal(1)
}

pub fn record_health_multiple_accumulates_test() {
  let state =
    canary_controller.init("v2", "v1")
    |> canary_controller.record_health(True)
    |> canary_controller.record_health(True)
    |> canary_controller.record_health(True)
    |> canary_controller.record_health(False)
  state.health_checks_passed |> should.equal(3)
  state.health_checks_failed |> should.equal(1)
}

// ---------------------------------------------------------------------------
// should_promote/1
// ---------------------------------------------------------------------------

pub fn should_promote_false_when_not_promoting_test() {
  let state = canary_controller.init("v2", "v1") |> canary_controller.advance()
  canary_controller.should_promote(state) |> should.be_false()
}

pub fn should_promote_false_when_no_checks_test() {
  let state =
    canary_controller.init("v2", "v1")
    |> canary_controller.advance()
    |> canary_controller.advance()
    |> canary_controller.advance()
    |> canary_controller.advance()
    |> canary_controller.advance()
  canary_controller.should_promote(state) |> should.be_false()
}

pub fn should_promote_true_when_high_pass_rate_test() {
  // 99 passes, 1 fail → 99% pass_rate == 0.99 == promotion_threshold → True
  let base =
    canary_controller.init("v2", "v1")
    |> canary_controller.advance()
    |> canary_controller.advance()
    |> canary_controller.advance()
    |> canary_controller.advance()
    |> canary_controller.advance()
  let state =
    canary_controller.CanaryState(
      ..base,
      health_checks_passed: 99,
      health_checks_failed: 1,
    )
  // Phase is CanaryPromoting after 5 advances; 0.99 >= 0.99 threshold → promote
  canary_controller.should_promote(state) |> should.be_true()
}

pub fn should_promote_true_when_all_pass_test() {
  let base =
    canary_controller.init("v2", "v1")
    |> canary_controller.advance()
    |> canary_controller.advance()
    |> canary_controller.advance()
    |> canary_controller.advance()
    |> canary_controller.advance()
  let state =
    canary_controller.CanaryState(
      ..base,
      health_checks_passed: 100,
      health_checks_failed: 0,
    )
  canary_controller.should_promote(state) |> should.be_true()
}

// ---------------------------------------------------------------------------
// should_rollback/1
// ---------------------------------------------------------------------------

pub fn should_rollback_false_when_no_checks_test() {
  let state = canary_controller.init("v2", "v1")
  canary_controller.should_rollback(state) |> should.be_false()
}

pub fn should_rollback_true_when_phase_rolling_back_test() {
  let state =
    canary_controller.init("v2", "v1")
    |> canary_controller.trigger_rollback()
  canary_controller.should_rollback(state) |> should.be_true()
}

pub fn should_rollback_true_when_fail_rate_high_test() {
  // 5 fails out of 10 = 50% — well above 1% threshold
  let state =
    canary_controller.CanaryState(
      ..canary_controller.init("v2", "v1"),
      health_checks_passed: 5,
      health_checks_failed: 5,
    )
  canary_controller.should_rollback(state) |> should.be_true()
}

pub fn should_rollback_false_when_fail_rate_low_test() {
  // 1 fail out of 1000 = 0.1% — below 1% threshold
  let state =
    canary_controller.CanaryState(
      ..canary_controller.init("v2", "v1"),
      health_checks_passed: 999,
      health_checks_failed: 1,
    )
  canary_controller.should_rollback(state) |> should.be_false()
}

// ---------------------------------------------------------------------------
// trigger_rollback/1
// ---------------------------------------------------------------------------

pub fn trigger_rollback_sets_phase_test() {
  let state =
    canary_controller.init("v2", "v1")
    |> canary_controller.advance()
    |> canary_controller.trigger_rollback()
  state.phase |> should.equal(CanaryRollingBack)
}

pub fn trigger_rollback_zeros_traffic_test() {
  let state =
    canary_controller.init("v2", "v1")
    |> canary_controller.advance()
    |> canary_controller.advance()
    |> canary_controller.trigger_rollback()
  state.traffic_pct |> should.equal(0)
}

// ---------------------------------------------------------------------------
// to_json/1
// ---------------------------------------------------------------------------

pub fn to_json_contains_canary_version_test() {
  let state = canary_controller.init("v22.6.0", "v22.5.0")
  let j = canary_controller.to_json(state)
  string.contains(j, "v22.6.0") |> should.be_true()
}

pub fn to_json_contains_phase_test() {
  let state = canary_controller.init("v2", "v1") |> canary_controller.advance()
  let j = canary_controller.to_json(state)
  string.contains(j, "started") |> should.be_true()
}

pub fn to_json_contains_traffic_pct_test() {
  let state = canary_controller.init("v2", "v1") |> canary_controller.advance()
  let j = canary_controller.to_json(state)
  string.contains(j, "traffic_pct") |> should.be_true()
}

// ---------------------------------------------------------------------------
// describe_phase/1
// ---------------------------------------------------------------------------

pub fn describe_phase_idle_test() {
  let state = canary_controller.init("v2", "v1")
  let desc = canary_controller.describe_phase(state)
  string.contains(desc, "idle") |> should.be_true()
  string.contains(desc, "0%") |> should.be_true()
}

pub fn describe_phase_started_test() {
  let state = canary_controller.init("v2", "v1") |> canary_controller.advance()
  let desc = canary_controller.describe_phase(state)
  string.contains(desc, "started") |> should.be_true()
  string.contains(desc, "5%") |> should.be_true()
}
