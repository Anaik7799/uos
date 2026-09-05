// =============================================================================
// request_guard_risk_test.gleam — risk-adaptive oversight tests
// STAMP: SC-SIL4-001, SC-SAFETY-001
// =============================================================================

import cepaf_gleam/ha/request_guard.{
  Block, Critical, High, Low, Medium, Proceed, classify_risk, risk_from_string,
  risk_gate, risk_to_string,
}
import gleeunit/should

// ---------------------------------------------------------------------------
// classify_risk — path classification
// ---------------------------------------------------------------------------

pub fn classify_risk_emergency_trigger_test() {
  classify_risk("/api/v1/emergency/trigger")
  |> should.equal(Critical)
}

pub fn classify_risk_guardian_respond_test() {
  classify_risk("/api/v1/guardian/respond")
  |> should.equal(Critical)
}

pub fn classify_risk_planning_add_test() {
  classify_risk("/api/v1/planning/add")
  |> should.equal(High)
}

pub fn classify_risk_podman_restart_test() {
  classify_risk("/api/v1/podman/restart")
  |> should.equal(High)
}

pub fn classify_risk_podman_stop_test() {
  classify_risk("/api/v1/podman/stop")
  |> should.equal(High)
}

pub fn classify_risk_reload_test() {
  classify_risk("/api/v1/reload")
  |> should.equal(High)
}

pub fn classify_risk_health_test() {
  classify_risk("/health")
  |> should.equal(Low)
}

pub fn classify_risk_dashboard_test() {
  classify_risk("/api/v1/dashboard")
  |> should.equal(Low)
}

pub fn classify_risk_pages_test() {
  classify_risk("/api/v1/pages")
  |> should.equal(Low)
}

pub fn classify_risk_unknown_defaults_to_medium_test() {
  classify_risk("/api/v1/some/unknown/path")
  |> should.equal(Medium)
}

pub fn classify_risk_root_defaults_to_medium_test() {
  classify_risk("/")
  |> should.equal(Medium)
}

// ---------------------------------------------------------------------------
// risk_gate — Low risk always proceeds
// ---------------------------------------------------------------------------

pub fn risk_gate_low_healthy_proceeds_test() {
  risk_gate("/health", 1.0)
  |> should.equal(Proceed)
}

pub fn risk_gate_low_degraded_still_proceeds_test() {
  risk_gate("/health", 0.0)
  |> should.equal(Proceed)
}

pub fn risk_gate_low_dashboard_proceeds_test() {
  risk_gate("/api/v1/dashboard", 0.1)
  |> should.equal(Proceed)
}

// ---------------------------------------------------------------------------
// risk_gate — Medium risk (threshold 0.5)
// ---------------------------------------------------------------------------

pub fn risk_gate_medium_above_threshold_proceeds_test() {
  risk_gate("/api/v1/metrics", 0.6)
  |> should.equal(Proceed)
}

pub fn risk_gate_medium_at_threshold_proceeds_test() {
  // health = 0.5 is not < 0.5, so Proceed
  risk_gate("/api/v1/metrics", 0.5)
  |> should.equal(Proceed)
}

pub fn risk_gate_medium_below_threshold_blocks_test() {
  let result = risk_gate("/api/v1/metrics", 0.4)
  case result {
    Block(reason) ->
      reason
      |> should.equal("Medium-risk endpoint blocked — system health below 50%")
    Proceed -> should.fail()
  }
}

// ---------------------------------------------------------------------------
// risk_gate — High risk (threshold 0.7)
// ---------------------------------------------------------------------------

pub fn risk_gate_high_above_threshold_proceeds_test() {
  risk_gate("/api/v1/podman/restart", 0.8)
  |> should.equal(Proceed)
}

pub fn risk_gate_high_at_threshold_proceeds_test() {
  // health = 0.7 is not < 0.7
  risk_gate("/api/v1/podman/restart", 0.7)
  |> should.equal(Proceed)
}

pub fn risk_gate_high_below_threshold_blocks_test() {
  let result = risk_gate("/api/v1/podman/restart", 0.5)
  case result {
    Block(reason) ->
      reason
      |> should.equal("High-risk mutation blocked — system health below 70%")
    Proceed -> should.fail()
  }
}

pub fn risk_gate_high_reload_below_threshold_blocks_test() {
  let result = risk_gate("/api/v1/reload", 0.0)
  case result {
    Block(_) -> should.be_ok(Ok(Nil))
    Proceed -> should.fail()
  }
}

// ---------------------------------------------------------------------------
// risk_gate — Critical risk (threshold 0.9)
// ---------------------------------------------------------------------------

pub fn risk_gate_critical_above_threshold_proceeds_test() {
  risk_gate("/api/v1/emergency/trigger", 0.95)
  |> should.equal(Proceed)
}

pub fn risk_gate_critical_at_threshold_proceeds_test() {
  // health = 0.9 is not < 0.9
  risk_gate("/api/v1/emergency/trigger", 0.9)
  |> should.equal(Proceed)
}

pub fn risk_gate_critical_below_threshold_blocks_test() {
  let result = risk_gate("/api/v1/emergency/trigger", 0.89)
  case result {
    Block(reason) ->
      reason
      |> should.equal(
        "Critical L0 action blocked — system health must be above 90%",
      )
    Proceed -> should.fail()
  }
}

pub fn risk_gate_critical_guardian_below_threshold_blocks_test() {
  let result = risk_gate("/api/v1/guardian/respond", 0.5)
  case result {
    Block(_) -> should.be_ok(Ok(Nil))
    Proceed -> should.fail()
  }
}

// ---------------------------------------------------------------------------
// risk_to_string
// ---------------------------------------------------------------------------

pub fn risk_to_string_low_test() {
  risk_to_string(Low)
  |> should.equal("low")
}

pub fn risk_to_string_medium_test() {
  risk_to_string(Medium)
  |> should.equal("medium")
}

pub fn risk_to_string_high_test() {
  risk_to_string(High)
  |> should.equal("high")
}

pub fn risk_to_string_critical_test() {
  risk_to_string(Critical)
  |> should.equal("critical")
}

// ---------------------------------------------------------------------------
// risk_from_string — round-trip property
// ---------------------------------------------------------------------------

pub fn risk_from_string_low_test() {
  risk_from_string("low")
  |> should.equal(Ok(Low))
}

pub fn risk_from_string_medium_test() {
  risk_from_string("medium")
  |> should.equal(Ok(Medium))
}

pub fn risk_from_string_high_test() {
  risk_from_string("high")
  |> should.equal(Ok(High))
}

pub fn risk_from_string_critical_test() {
  risk_from_string("critical")
  |> should.equal(Ok(Critical))
}

pub fn risk_from_string_unknown_is_error_test() {
  risk_from_string("unknown")
  |> should.equal(Error(Nil))
}

pub fn risk_from_string_uppercase_normalised_test() {
  risk_from_string("HIGH")
  |> should.equal(Ok(High))
}

// ---------------------------------------------------------------------------
// round-trip: risk_to_string |> risk_from_string
// ---------------------------------------------------------------------------

pub fn risk_roundtrip_low_test() {
  risk_to_string(Low)
  |> risk_from_string()
  |> should.equal(Ok(Low))
}

pub fn risk_roundtrip_critical_test() {
  risk_to_string(Critical)
  |> risk_from_string()
  |> should.equal(Ok(Critical))
}
