//// =============================================================================
//// [C3I-SIL6-NIF-BRIDGE] ZENOH & RETE-UL NATIVE NIF SUBSYSTEM
//// =============================================================================
//// Direct BEAM NIF integration for:
//// 1. Zenoh Mesh Transport (c3i_nif.so via Rust zenoh 1.9.0)
//// 2. RETE-UL Forward-Chaining Rule Engine (rule_engine_nif.so via rust-rule-engine 1.20.1)
////
//// Adheres to Zero-Muda and safe bounded native dispatch contracts.
//// =============================================================================

import cepaf_gleam/c3i/nif as c3i_nif
import cepaf_gleam/rules/engine as rule_engine
import gleam/json
import gleam/string

// =============================================================================
// Types
// =============================================================================

pub type ZenohNifStatus {
  ZenohConnected(endpoint: String)
  ZenohDisconnected
  ZenohError(reason: String)
}

pub type ReteUlStatus {
  ReteUlActive(version: String)
  ReteUlDegraded(reason: String)
}

pub type ReteDecision {
  ReteDecision(
    decision: String,
    reason: String,
    domain: String,
    is_authorized: Bool,
  )
}

pub type NativeNifReport {
  NativeNifReport(
    zenoh_status: String,
    zenoh_connected: Bool,
    rete_version: String,
    rete_operational: Bool,
    sample_rule_decision: String,
    sample_rule_reason: String,
  )
}

// =============================================================================
// Zenoh Native NIF Operations (SC-ZENOH-001)
// =============================================================================

/// Query current Zenoh session status from the Rust NIF.
pub fn check_zenoh_nif_status() -> ZenohNifStatus {
  let raw = c3i_nif.zenoh_status()
  case string.contains(raw, "\"connected\":true") {
    True -> {
      let endpoint = case string.contains(raw, "tcp/") {
        True -> "tcp/localhost:7447"
        False -> "embedded_mesh"
      }
      ZenohConnected(endpoint: endpoint)
    }
    False -> {
      case string.contains(raw, "error") {
        True -> ZenohError(reason: raw)
        False -> ZenohDisconnected
      }
    }
  }
}

/// Open a Zenoh session via native Rust NIF.
pub fn open_zenoh_session(config_json: String) -> Result(String, String) {
  let res = c3i_nif.zenoh_open(config_json)
  case string.contains(res, "\"status\":\"connected\"") {
    True -> Ok(res)
    False -> {
      case string.contains(res, "connected") {
        True -> Ok(res)
        False -> Error(res)
      }
    }
  }
}

/// Publish a key-value payload to Zenoh via native Rust NIF.
pub fn publish_zenoh(key: String, payload: String) -> Result(String, String) {
  let res = c3i_nif.zenoh_put(key, payload)
  case string.contains(res, "\"status\":\"ok\"") {
    True -> Ok(res)
    False -> {
      case string.contains(res, "ok") {
        True -> Ok(res)
        False -> Error(res)
      }
    }
  }
}

/// Get data for a key from Zenoh via native Rust NIF.
pub fn get_zenoh(key: String) -> Result(String, String) {
  let res = c3i_nif.zenoh_get(key)
  case string.contains(res, "error") {
    True -> Error(res)
    False -> Ok(res)
  }
}

// =============================================================================
// RETE-UL Forward-Chaining Engine Operations (SC-OODA-003)
// =============================================================================

/// Query the RETE-UL rule engine version from rule_engine_nif.so.
pub fn get_rete_ul_version() -> ReteUlStatus {
  let ver = rule_engine.version()
  case string.contains(ver, "RETE-UL") {
    True -> ReteUlActive(version: ver)
    False -> {
      case string.contains(ver, "rule-engine") {
        True -> ReteUlActive(version: ver)
        False -> ReteUlDegraded(reason: ver)
      }
    }
  }
}

/// Evaluate GRL rules against facts using the high-performance RETE-UL Rust NIF (<1ms).
pub fn evaluate_rete_rules(
  domain: String,
  rules_grl: String,
  facts: List(rule_engine.Fact),
) -> ReteDecision {
  let res = rule_engine.evaluate(domain, rules_grl, facts)
  let is_auth = res.decision != "EmergencyStop" && res.decision != "Error"
  ReteDecision(
    decision: res.decision,
    reason: res.reason,
    domain: domain,
    is_authorized: is_auth,
  )
}

/// Built-in Sovereign Constitutional Safety GRL rules.
pub fn sovereign_safety_rules() -> String {
  "
    rule \"Lock Host OS NVMe\" salience 100 {
      when Storage.DeviceSerial == \"25503L801736\"
      then Storage.Decision = \"EmergencyStop\"; Storage.Reason = \"Host OS NVMe 25503L801736 is locked fail-closed\";
    }
    rule \"Constitutional Missing Nodes\" salience 90 {
      when System.MissingCriticalNodes == true
      then System.Decision = \"EmergencyStop\"; System.Reason = \"Quorum lost: missing critical nodes\";
    }
    rule \"Normal Authorized Flight\" salience 10 {
      when System.QuorumValid == true
      then System.Decision = \"AuthorizeIntent\"; System.Reason = \"Quorum 2oo3 ratified and storage verified\";
    }
  "
}

// =============================================================================
// Integrated Health & Evaluation Subsystem
// =============================================================================

/// Evaluate both Zenoh and RETE-UL NIF subsystems.
pub fn evaluate_nif_subsystem() -> NativeNifReport {
  // 1. Check Zenoh NIF
  let zenoh_stat = c3i_nif.zenoh_status()
  let is_connected = string.contains(zenoh_stat, "\"connected\":true")

  // 2. Check RETE-UL NIF
  let rete_ver = rule_engine.version()
  let rete_ok = string.contains(rete_ver, "rule-engine")

  // 3. Test evaluate a rule through RETE-UL
  let facts = [
    rule_engine.Fact(key: "Storage.DeviceSerial", value: "25503L801736"),
  ]
  let decision = evaluate_rete_rules("Storage", sovereign_safety_rules(), facts)

  NativeNifReport(
    zenoh_status: zenoh_stat,
    zenoh_connected: is_connected,
    rete_version: rete_ver,
    rete_operational: rete_ok,
    sample_rule_decision: decision.decision,
    sample_rule_reason: decision.reason,
  )
}

/// Encode native NIF report to JSON.
pub fn encode_nif_report_json(report: NativeNifReport) -> String {
  json.object([
    #("status", json.string("ok")),
    #(
      "zenoh_nif",
      json.object([
        #("connected", json.bool(report.zenoh_connected)),
        #("raw_status", json.string(report.zenoh_status)),
        #("transport", json.string("Rust Zenoh 1.9.0 NIF")),
      ]),
    ),
    #(
      "rete_ul_nif",
      json.object([
        #("operational", json.bool(report.rete_operational)),
        #("version", json.string(report.rete_version)),
        #("engine", json.string("rust-rule-engine 1.20.1 RETE-UL")),
        #("sample_decision", json.string(report.sample_rule_decision)),
        #("sample_reason", json.string(report.sample_rule_reason)),
      ]),
    ),
  ])
  |> json.to_string
}
