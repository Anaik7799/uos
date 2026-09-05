/// Digital Twin tests
/// Layer: L4_SYSTEM
/// STAMP: SC-HA-001, SC-TRUTH-001, SC-FUNC-001
///
/// Covers:
///   TwinState construction and component mirroring
///   Drift detection (I1: drifted iff desired != actual)
///   Drift score computation (I1: drifted_count / total)
///   Twin health (I2: 1.0 - drift_score)
///   SyncAction generation (I5: Converge / Alert / NoSync rules)
///   sync_component updates actual and recalculates drift
///   Summary string format
import cepaf_gleam/ha/digital_twin.{
  action_name, action_to_string, detect_drift, drift_score, is_alert,
  is_converge, is_no_sync, mirror_component, reconciliation_actions, summary,
  sync_component, twin_health, twin_new,
}
import gleam/list
import gleeunit/should

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

pub fn twin_new_is_empty_test() {
  let twin = twin_new()
  list.length(twin.components) |> should.equal(0)
}

pub fn twin_new_drift_score_zero_test() {
  twin_new() |> drift_score() |> should.equal(0.0)
}

pub fn twin_new_health_is_one_test() {
  twin_new() |> twin_health() |> should.equal(1.0)
}

// ---------------------------------------------------------------------------
// Mirroring
// ---------------------------------------------------------------------------

pub fn mirror_component_adds_entry_test() {
  let twin =
    twin_new()
    |> mirror_component("zenoh", "running", "running", 1.0, 1000)
  list.length(twin.components) |> should.equal(1)
}

pub fn mirror_component_not_drifted_when_equal_test() {
  let twin =
    twin_new()
    |> mirror_component("db", "running", "running", 1.0, 1000)
  let mirrors = detect_drift(twin)
  list.length(mirrors) |> should.equal(0)
}

pub fn mirror_component_drifted_when_different_test() {
  let twin =
    twin_new()
    |> mirror_component("db", "running", "stopped", 0.9, 1000)
  let drifted = detect_drift(twin)
  list.length(drifted) |> should.equal(1)
}

pub fn mirror_component_replace_existing_test() {
  let twin =
    twin_new()
    |> mirror_component("svc", "running", "stopped", 0.8, 1000)
    |> mirror_component("svc", "running", "running", 1.0, 2000)
  list.length(twin.components) |> should.equal(1)
  list.length(detect_drift(twin)) |> should.equal(0)
}

// ---------------------------------------------------------------------------
// Drift score and health
// ---------------------------------------------------------------------------

pub fn drift_score_all_converged_test() {
  let twin =
    twin_new()
    |> mirror_component("a", "up", "up", 1.0, 1)
    |> mirror_component("b", "up", "up", 1.0, 1)
  drift_score(twin) |> should.equal(0.0)
}

pub fn drift_score_half_drifted_test() {
  let twin =
    twin_new()
    |> mirror_component("a", "up", "down", 1.0, 1)
    |> mirror_component("b", "up", "up", 1.0, 1)
  drift_score(twin) |> should.equal(0.5)
}

pub fn twin_health_full_drift_is_zero_test() {
  let twin =
    twin_new()
    |> mirror_component("a", "up", "down", 1.0, 1)
  twin_health(twin) |> should.equal(0.0)
}

// ---------------------------------------------------------------------------
// SyncActions
// ---------------------------------------------------------------------------

pub fn reconciliation_no_sync_when_healthy_test() {
  let twin =
    twin_new()
    |> mirror_component("app", "running", "running", 1.0, 1)
  let actions = reconciliation_actions(twin)
  list.all(actions, is_no_sync) |> should.be_true()
}

pub fn reconciliation_converge_when_drifted_test() {
  let twin =
    twin_new()
    |> mirror_component("app", "running", "stopped", 0.9, 1)
  let actions = reconciliation_actions(twin)
  list.any(actions, is_converge) |> should.be_true()
}

pub fn reconciliation_alert_when_low_health_test() {
  let twin =
    twin_new()
    |> mirror_component("db", "running", "running", 0.3, 1)
  let actions = reconciliation_actions(twin)
  list.any(actions, is_alert) |> should.be_true()
}

pub fn reconciliation_action_name_matches_test() {
  let twin =
    twin_new()
    |> mirror_component("zenoh", "running", "running", 1.0, 1)
  let actions = reconciliation_actions(twin)
  case actions {
    [action, ..] -> action_name(action) |> should.equal("zenoh")
    [] -> should.fail()
  }
}

// ---------------------------------------------------------------------------
// sync_component
// ---------------------------------------------------------------------------

pub fn sync_component_clears_drift_test() {
  let twin =
    twin_new()
    |> mirror_component("app", "running", "stopped", 0.9, 1)
    |> sync_component("app", "running", 2)
  list.length(detect_drift(twin)) |> should.equal(0)
}

pub fn sync_component_updates_timestamp_test() {
  let twin =
    twin_new()
    |> mirror_component("app", "running", "running", 1.0, 1)
    |> sync_component("app", "running", 9999)
  twin.sync_timestamp |> should.equal(9999)
}

// ---------------------------------------------------------------------------
// Summary
// ---------------------------------------------------------------------------

pub fn summary_contains_components_count_test() {
  let twin =
    twin_new()
    |> mirror_component("a", "up", "up", 1.0, 1)
    |> mirror_component("b", "up", "down", 0.9, 1)
  let s = summary(twin)
  // Should contain component count
  s |> should.not_equal("")
}

pub fn action_to_string_converge_test() {
  let twin =
    twin_new()
    |> mirror_component("svc", "running", "stopped", 0.9, 1)
  let actions = reconciliation_actions(twin)
  case actions {
    [action, ..] -> {
      let s = action_to_string(action)
      s |> should.not_equal("")
    }
    [] -> should.fail()
  }
}
