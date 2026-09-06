//// Tests for Zenoh & RETE-UL Native NIF subsystem

import cepaf_gleam/nif/zenoh_rete_bridge as bridge
import cepaf_gleam/rules/engine as rule_engine
import gleam/string
import gleeunit/should

pub fn check_zenoh_nif_status_test() {
  let status = bridge.check_zenoh_nif_status()
  case status {
    bridge.ZenohConnected(_) -> should.be_true(True)
    bridge.ZenohDisconnected -> should.be_true(True)
    bridge.ZenohError(_) -> should.be_true(True)
  }
}

pub fn zenoh_session_lifecycle_test() {
  // Open session
  let open_res = bridge.open_zenoh_session("{}")
  open_res |> should.be_ok()

  // Verify status is connected
  let status = bridge.check_zenoh_nif_status()
  case status {
    bridge.ZenohConnected(ep) -> {
      string.contains(ep, "7447") |> should.be_true()
    }
    _ -> should.fail()
  }

  // Publish a test packet
  let pub_res =
    bridge.publish_zenoh(
      "indrajaal/l0/const/test_nif",
      "{\"status\":\"active\",\"test\":true}",
    )
  pub_res |> should.be_ok()
}

pub fn rete_ul_version_test() {
  let ver = bridge.get_rete_ul_version()
  case ver {
    bridge.ReteUlActive(v) -> {
      string.contains(v, "RETE-UL") |> should.be_true()
      string.contains(v, "1.20.1") |> should.be_true()
    }
    bridge.ReteUlDegraded(r) -> {
      // Fallback string should still contain rule-engine
      string.contains(r, "rule") |> should.be_true()
    }
  }
}

pub fn rete_ul_safety_decision_locked_nvme_test() {
  let facts = [
    rule_engine.Fact(key: "Storage.DeviceSerial", value: "25503L801736"),
  ]
  let decision =
    bridge.evaluate_rete_rules(
      "Storage",
      bridge.sovereign_safety_rules(),
      facts,
    )

  decision.decision |> should.equal("EmergencyStop")
  string.contains(decision.reason, "25503L801736 is locked")
  |> should.be_true()
  decision.is_authorized |> should.be_false()
}

pub fn rete_ul_safety_decision_authorized_test() {
  let facts = [rule_engine.Fact(key: "System.QuorumValid", value: "true")]
  let decision =
    bridge.evaluate_rete_rules("System", bridge.sovereign_safety_rules(), facts)

  decision.decision |> should.equal("AuthorizeIntent")
  string.contains(decision.reason, "Quorum 2oo3 ratified")
  |> should.be_true()
  decision.is_authorized |> should.be_true()
}

pub fn evaluate_nif_subsystem_report_test() {
  let report = bridge.evaluate_nif_subsystem()
  report.rete_operational |> should.be_true()
  report.sample_rule_decision |> should.equal("EmergencyStop")

  let json_str = bridge.encode_nif_report_json(report)
  string.contains(json_str, "\"status\":\"ok\"") |> should.be_true()
  string.contains(json_str, "RETE-UL") |> should.be_true()
  string.contains(json_str, "zenoh_nif") |> should.be_true()
}
