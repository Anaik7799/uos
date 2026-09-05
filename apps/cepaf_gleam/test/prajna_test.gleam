// Test all 7 Prajna modules: bio, immune_system, neuro, dark_cockpit,
// circuit_breaker, smart_metrics, orchestrator_cmd

import cepaf_gleam/prajna/bio.{
  Active, Apoptotic, Awakening, Closed, Dormant, EmergencyPerm, Healing,
  MembraneConfig, Open, Selective, Stressed, VitalSigns,
}
import cepaf_gleam/prajna/circuit_breaker.{
  BreakerClosed, BreakerHalfOpen, BreakerOpen,
}
import cepaf_gleam/prajna/dark_cockpit.{
  Alert, Bright, CriticalSeverity, Dark, Dim, EmergencyMode, ErrorSeverity,
  NormalMode, WarningSeverity,
}
import cepaf_gleam/prajna/immune_system.{
  Critical, High, Ignore, Isolate, Log, Low, Medium, Terminate, Threat,
}
import cepaf_gleam/prajna/neuro.{
  Broadcast, Deliver, Drop, Emergency, Forward, Normal,
}
import cepaf_gleam/prajna/orchestrator_cmd.{
  Armed, Created, PrajnaCompleted, PrajnaFailed, RestartCmd, ScaleCmd, StartCmd,
  StatusCmd, StopCmd,
}
import cepaf_gleam/prajna/smart_metrics
import gleam/list
import gleam/option.{None, Some}
import gleeunit/should

// =============================================================================
// bio tests
// =============================================================================

pub fn bio_create_holon_test() {
  let h = bio.create_holon("h-1", "worker", None)
  h.id |> should.equal("h-1")
  h.holon_type |> should.equal("worker")
  h.state |> should.equal(Dormant)
  h.vitals.health_index |> should.equal(1.0)
  h.vitals.stress_index |> should.equal(0.0)
  h.vitals.energy |> should.equal(1.0)
  h.parent_id |> should.equal(None)
}

pub fn bio_create_holon_with_parent_test() {
  let h = bio.create_holon("h-2", "sensor", Some("parent-1"))
  h.parent_id |> should.equal(Some("parent-1"))
}

pub fn bio_transition_valid_dormant_to_awakening_test() {
  let h = bio.create_holon("h-3", "worker", None)
  let result = bio.transition(h, Awakening)
  result |> should.be_ok
  let assert Ok(h2) = result
  h2.state |> should.equal(Awakening)
}

pub fn bio_transition_valid_chain_test() {
  let h = bio.create_holon("h-4", "worker", None)
  let assert Ok(h2) = bio.transition(h, Awakening)
  let assert Ok(h3) = bio.transition(h2, Active)
  let assert Ok(h4) = bio.transition(h3, Stressed)
  let assert Ok(h5) = bio.transition(h4, Healing)
  let assert Ok(h6) = bio.transition(h5, Active)
  h6.state |> should.equal(Active)
}

pub fn bio_transition_invalid_test() {
  let h = bio.create_holon("h-5", "worker", None)
  bio.transition(h, Active) |> should.be_error
}

pub fn bio_transition_active_to_apoptotic_test() {
  let h = bio.create_holon("h-6", "worker", None)
  let assert Ok(h2) = bio.transition(h, Awakening)
  let assert Ok(h3) = bio.transition(h2, Active)
  let assert Ok(h4) = bio.transition(h3, Apoptotic)
  h4.state |> should.equal(Apoptotic)
}

pub fn bio_transition_stressed_to_apoptotic_test() {
  let h = bio.create_holon("h-7", "worker", None)
  let assert Ok(h2) = bio.transition(h, Awakening)
  let assert Ok(h3) = bio.transition(h2, Active)
  let assert Ok(h4) = bio.transition(h3, Stressed)
  let assert Ok(h5) = bio.transition(h4, Apoptotic)
  h5.state |> should.equal(Apoptotic)
}

pub fn bio_is_healthy_true_test() {
  let h = bio.create_holon("h-8", "worker", None)
  let assert Ok(h2) = bio.transition(h, Awakening)
  let assert Ok(h3) = bio.transition(h2, Active)
  bio.is_healthy(h3) |> should.be_true
}

pub fn bio_is_healthy_false_dormant_test() {
  let h = bio.create_holon("h-9", "worker", None)
  bio.is_healthy(h) |> should.be_false
}

pub fn bio_can_pass_closed_test() {
  let membrane = MembraneConfig(Closed, [])
  bio.can_pass(membrane, "src", "msg") |> should.be_false
}

pub fn bio_can_pass_open_test() {
  let membrane = MembraneConfig(Open, [])
  bio.can_pass(membrane, "src", "msg") |> should.be_true
}

pub fn bio_can_pass_open_blocked_test() {
  let membrane = MembraneConfig(Open, ["bad-src"])
  bio.can_pass(membrane, "bad-src", "msg") |> should.be_false
}

pub fn bio_can_pass_selective_allowed_test() {
  let membrane = MembraneConfig(Selective(["health", "status"]), [])
  bio.can_pass(membrane, "any", "health") |> should.be_true
}

pub fn bio_can_pass_selective_denied_test() {
  let membrane = MembraneConfig(Selective(["health"]), [])
  bio.can_pass(membrane, "any", "data") |> should.be_false
}

pub fn bio_can_pass_emergency_perm_pass_test() {
  let membrane = MembraneConfig(EmergencyPerm, [])
  bio.can_pass(membrane, "any", "emergency") |> should.be_true
}

pub fn bio_can_pass_emergency_perm_deny_test() {
  let membrane = MembraneConfig(EmergencyPerm, [])
  bio.can_pass(membrane, "any", "normal") |> should.be_false
}

pub fn bio_default_membrane_test() {
  let m = bio.default_membrane_config()
  m.permeability |> should.equal(Open)
  m.blocked_sources |> should.equal([])
}

// =============================================================================
// immune_system tests
// =============================================================================

pub fn immune_assess_threat_critical_test() {
  let vitals = VitalSigns(0.1, 0.95, 0.5)
  immune_system.assess_threat(vitals) |> should.equal(Critical)
}

pub fn immune_assess_threat_high_test() {
  let vitals = VitalSigns(0.3, 0.75, 0.5)
  immune_system.assess_threat(vitals) |> should.equal(High)
}

pub fn immune_assess_threat_medium_test() {
  let vitals = VitalSigns(0.5, 0.55, 0.5)
  immune_system.assess_threat(vitals) |> should.equal(Medium)
}

pub fn immune_assess_threat_low_test() {
  let vitals = VitalSigns(0.7, 0.35, 0.5)
  immune_system.assess_threat(vitals) |> should.equal(Low)
}

pub fn immune_assess_threat_none_test() {
  let vitals = VitalSigns(0.9, 0.1, 0.5)
  immune_system.assess_threat(vitals) |> should.equal(immune_system.None)
}

pub fn immune_recommend_action_none_test() {
  immune_system.recommend_action(immune_system.None) |> should.equal(Ignore)
}

pub fn immune_recommend_action_low_test() {
  immune_system.recommend_action(immune_system.Low) |> should.equal(Log)
}

pub fn immune_recommend_action_medium_test() {
  immune_system.recommend_action(Medium)
  |> should.equal(immune_system.Alert)
}

pub fn immune_recommend_action_high_test() {
  immune_system.recommend_action(High) |> should.equal(Isolate)
}

pub fn immune_recommend_action_critical_test() {
  immune_system.recommend_action(Critical) |> should.equal(Terminate)
}

pub fn immune_mara_recommend_empty_test() {
  let resp = immune_system.mara_recommend([])
  resp.action |> should.equal(Ignore)
  resp.threats_assessed |> should.equal(0)
  resp.reason |> should.equal("No threats detected")
}

pub fn immune_mara_recommend_mixed_test() {
  let threats = [
    Threat(
      "t1",
      immune_system.ResourceExhaustion,
      High,
      "node-1",
      "High load",
      "now",
    ),
    Threat(
      "t2",
      immune_system.NetworkAnomaly,
      immune_system.Low,
      "node-2",
      "Latency",
      "now",
    ),
  ]
  let resp = immune_system.mara_recommend(threats)
  resp.threats_assessed |> should.equal(2)
  resp.action |> should.equal(Isolate)
}

// =============================================================================
// neuro tests
// =============================================================================

pub fn neuro_create_message_test() {
  let msg =
    neuro.create_message("m-1", "node-a", "node-b", Normal, "hello", "now")
  msg.id |> should.equal("m-1")
  msg.ttl |> should.equal(10)
  msg.source |> should.equal("node-a")
}

pub fn neuro_route_local_test() {
  let msg =
    neuro.create_message("m-2", "node-a", "node-b", Normal, "data", "now")
  neuro.route(msg, "node-b") |> should.equal(Deliver)
}

pub fn neuro_route_broadcast_test() {
  let msg = neuro.create_message("m-3", "node-a", "*", Normal, "data", "now")
  neuro.route(msg, "node-b") |> should.equal(Broadcast)
}

pub fn neuro_route_forward_test() {
  let msg =
    neuro.create_message("m-4", "node-a", "node-c", Normal, "data", "now")
  neuro.route(msg, "node-b") |> should.equal(Forward("node-c"))
}

pub fn neuro_route_drop_expired_test() {
  let msg =
    neuro.create_message("m-5", "node-a", "node-b", Emergency, "data", "now")
  let expired = neuro.SpineMessage(..msg, ttl: 0)
  neuro.route(expired, "node-b") |> should.equal(Drop("TTL expired"))
}

pub fn neuro_decrement_ttl_test() {
  let msg = neuro.create_message("m-6", "a", "b", Normal, "x", "now")
  let decremented = neuro.decrement_ttl(msg)
  decremented.ttl |> should.equal(9)
}

pub fn neuro_is_expired_test() {
  let msg = neuro.create_message("m-7", "a", "b", Normal, "x", "now")
  neuro.is_expired(msg) |> should.be_false
  let expired = neuro.SpineMessage(..msg, ttl: 0)
  neuro.is_expired(expired) |> should.be_true
}

// =============================================================================
// dark_cockpit tests
// =============================================================================

pub fn dark_cockpit_initial_state_test() {
  let state = dark_cockpit.initial_state()
  state.mode |> should.equal(Dark)
  state.alerts |> should.equal([])
  state.last_update |> should.equal("")
}

pub fn dark_cockpit_determine_mode_dark_test() {
  dark_cockpit.determine_mode([]) |> should.equal(Dark)
}

pub fn dark_cockpit_determine_mode_dim_test() {
  let alerts = [
    Alert("a1", WarningSeverity, "warn", "src", "now", False),
  ]
  dark_cockpit.determine_mode(alerts) |> should.equal(Dim)
}

pub fn dark_cockpit_determine_mode_normal_test() {
  let alerts = [
    Alert("a1", ErrorSeverity, "err1", "src", "now", False),
  ]
  dark_cockpit.determine_mode(alerts) |> should.equal(NormalMode)
}

pub fn dark_cockpit_determine_mode_bright_test() {
  let alerts = [
    Alert("a1", ErrorSeverity, "err1", "src", "now", False),
    Alert("a2", ErrorSeverity, "err2", "src", "now", False),
    Alert("a3", ErrorSeverity, "err3", "src", "now", False),
  ]
  dark_cockpit.determine_mode(alerts) |> should.equal(Bright)
}

pub fn dark_cockpit_determine_mode_emergency_test() {
  let alerts = [
    Alert("a1", CriticalSeverity, "critical", "src", "now", False),
  ]
  dark_cockpit.determine_mode(alerts) |> should.equal(EmergencyMode)
}

pub fn dark_cockpit_add_alert_test() {
  let state = dark_cockpit.initial_state()
  let alert = Alert("a1", WarningSeverity, "watch out", "src", "now", False)
  let new_state = dark_cockpit.add_alert(state, alert)
  list.length(new_state.alerts) |> should.equal(1)
  new_state.mode |> should.equal(Dim)
}

pub fn dark_cockpit_acknowledge_alert_test() {
  let state = dark_cockpit.initial_state()
  let alert = Alert("a1", ErrorSeverity, "err", "src", "now", False)
  let state2 = dark_cockpit.add_alert(state, alert)
  state2.mode |> should.equal(NormalMode)
  let state3 = dark_cockpit.acknowledge_alert(state2, "a1")
  state3.mode |> should.equal(Dark)
}

// =============================================================================
// circuit_breaker tests
// =============================================================================

pub fn circuit_breaker_create_test() {
  let b = circuit_breaker.create("test-cb", 3, 2, 5000)
  b.name |> should.equal("test-cb")
  b.state |> should.equal(BreakerClosed)
  b.failure_count |> should.equal(0)
  b.failure_threshold |> should.equal(3)
}

pub fn circuit_breaker_record_failure_until_open_test() {
  let b = circuit_breaker.create("cb", 3, 2, 5000)
  let b1 = circuit_breaker.record_failure(b, 1000)
  b1.failure_count |> should.equal(1)
  circuit_breaker.is_allowed(b1) |> should.be_true

  let b2 = circuit_breaker.record_failure(b1, 2000)
  b2.failure_count |> should.equal(2)

  let b3 = circuit_breaker.record_failure(b2, 3000)
  b3.failure_count |> should.equal(3)
  case b3.state {
    BreakerOpen(_) -> should.be_true(True)
    _ -> should.fail()
  }
  circuit_breaker.is_allowed(b3) |> should.be_false
}

pub fn circuit_breaker_record_success_in_half_open_test() {
  let b = circuit_breaker.create("cb", 1, 2, 1000)
  let b1 = circuit_breaker.record_failure(b, 1000)
  // Now open
  circuit_breaker.is_allowed(b1) |> should.be_false

  // Transition to half-open after timeout
  let b2 = circuit_breaker.attempt_half_open(b1, 3000)
  b2.state |> should.equal(BreakerHalfOpen)
  circuit_breaker.is_allowed(b2) |> should.be_true

  // Record successes to close
  let b3 = circuit_breaker.record_success(b2)
  let b4 = circuit_breaker.record_success(b3)
  b4.state |> should.equal(BreakerClosed)
}

pub fn circuit_breaker_is_allowed_test() {
  let b = circuit_breaker.create("cb", 3, 2, 5000)
  circuit_breaker.is_allowed(b) |> should.be_true
}

// =============================================================================
// smart_metrics tests
// =============================================================================

pub fn smart_metrics_detect_anomaly_insufficient_data_test() {
  smart_metrics.detect_anomaly([1.0], 2.0)
  |> should.be_error
}

pub fn smart_metrics_detect_anomaly_normal_test() {
  let values = [1.0, 1.1, 0.9, 1.0, 1.05]
  let result = smart_metrics.detect_anomaly(values, 3.0)
  result |> should.be_ok
  let assert Ok(is_anomaly) = result
  is_anomaly |> should.be_false
}

pub fn smart_metrics_detect_anomaly_outlier_test() {
  // Many similar values then a large outlier, with a low threshold
  let values = [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 50.0]
  let result = smart_metrics.detect_anomaly(values, 2.0)
  result |> should.be_ok
  let assert Ok(is_anomaly) = result
  is_anomaly |> should.be_true
}

pub fn smart_metrics_z_score_test() {
  // z_score(10.0, 5.0, 2.5) = (10-5)/2.5 = 2.0
  smart_metrics.z_score(10.0, 5.0, 2.5) |> should.equal(2.0)
}

pub fn smart_metrics_z_score_zero_std_dev_test() {
  smart_metrics.z_score(10.0, 5.0, 0.0) |> should.equal(0.0)
}

pub fn smart_metrics_moving_average_test() {
  let values = [1.0, 2.0, 3.0, 4.0, 5.0]
  let result = smart_metrics.moving_average(values, 3)
  // Window 3: [1,2,3]=2.0, [2,3,4]=3.0, [3,4,5]=4.0
  list.length(result) |> should.equal(3)
  let assert [first, second, third] = result
  first |> should.equal(2.0)
  second |> should.equal(3.0)
  third |> should.equal(4.0)
}

pub fn smart_metrics_moving_average_bad_window_test() {
  smart_metrics.moving_average([1.0, 2.0], 0) |> should.equal([])
  smart_metrics.moving_average([1.0, 2.0], 5) |> should.equal([])
}

// =============================================================================
// orchestrator_cmd tests
// =============================================================================

pub fn orchestrator_requires_two_key_stop_test() {
  orchestrator_cmd.requires_two_key(StopCmd) |> should.be_true
}

pub fn orchestrator_requires_two_key_start_test() {
  orchestrator_cmd.requires_two_key(StartCmd) |> should.be_false
}

pub fn orchestrator_requires_two_key_restart_test() {
  orchestrator_cmd.requires_two_key(RestartCmd) |> should.be_true
}

pub fn orchestrator_requires_two_key_status_test() {
  orchestrator_cmd.requires_two_key(StatusCmd) |> should.be_false
}

pub fn orchestrator_requires_two_key_scale_test() {
  orchestrator_cmd.requires_two_key(ScaleCmd(5)) |> should.be_true
}

pub fn orchestrator_create_command_test() {
  let cmd =
    orchestrator_cmd.create_command("c-1", StopCmd, "node-1", "admin", "now")
  cmd.id |> should.equal("c-1")
  cmd.status |> should.equal(Created)
  cmd.issued_by |> should.equal("admin")
  cmd.armed_by |> should.equal("")
}

pub fn orchestrator_arm_two_key_different_operator_test() {
  let cmd =
    orchestrator_cmd.create_command("c-2", StopCmd, "node-1", "admin", "now")
  let result = orchestrator_cmd.arm(cmd, "operator")
  result |> should.be_ok
  let assert Ok(armed_cmd) = result
  armed_cmd.status |> should.equal(Armed)
  armed_cmd.armed_by |> should.equal("operator")
}

pub fn orchestrator_arm_two_key_same_operator_test() {
  let cmd =
    orchestrator_cmd.create_command("c-3", StopCmd, "node-1", "admin", "now")
  orchestrator_cmd.arm(cmd, "admin") |> should.be_error
}

pub fn orchestrator_confirm_test() {
  let cmd =
    orchestrator_cmd.create_command("c-4", StartCmd, "node-1", "admin", "now")
  let assert Ok(armed) = orchestrator_cmd.arm(cmd, "admin")
  let assert Ok(executing) = orchestrator_cmd.confirm(armed)
  executing.status |> should.equal(orchestrator_cmd.Executing)
}

pub fn orchestrator_complete_success_test() {
  let cmd =
    orchestrator_cmd.create_command("c-5", StartCmd, "node-1", "admin", "now")
  let completed = orchestrator_cmd.complete(cmd, True, "")
  completed.status |> should.equal(PrajnaCompleted)
}

pub fn orchestrator_complete_failure_test() {
  let cmd =
    orchestrator_cmd.create_command("c-6", StartCmd, "node-1", "admin", "now")
  let failed = orchestrator_cmd.complete(cmd, False, "timeout")
  failed.status |> should.equal(PrajnaFailed("timeout"))
}
