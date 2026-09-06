//// =============================================================================
//// [UOS-FPP-INTENT-TEST] NASA JPL F Prime Denotational Intent Test Suite
//// =============================================================================
//// Formally tests the Denotational Intent Gatekeeper & Flight Safety Interlocks:
//// 1. Authorized flight intent execution & 128-bit W3C trace emission
//// 2. Hardware storage safety interlock denial (OS NVMe 25503L801736)
//// 3. Precondition guard verification & refusal
//// 4. Intent verdict JSON serialization
//// =============================================================================

import cepaf_gleam/fpp/dmc_tcm.{hard_denied_system_os_serial}
import cepaf_gleam/fpp/intent.{
  DispatchFlightCommand, FlightIntent, IntentAuthorized, IntentRejected,
  UpdateFlightParameter, encode_intent_verdict_json, evaluate_flight_intent,
}
import gleam/string
import gleeunit/should

pub fn fpp_intent_authorization_test() {
  let valid_intent =
    FlightIntent(
      intent_id: "INT-FLIGHT-001",
      actor: "flight_director",
      verb: DispatchFlightCommand(opcode: 0x701, args: []),
      target_instance: "harness_config",
      target_device_serial: "SAFE_STORAGE_NVME",
      precondition_guard: True,
      formal_proof_ref: "PROOF-FPP-VERIFY-001",
    )

  let verdict = evaluate_flight_intent(valid_intent)
  case verdict {
    IntentAuthorized(trace_id, id, action, conserved) -> {
      id |> should.equal("INT-FLIGHT-001")
      trace_id |> should.equal("4bf92f3577b34da6a3ce929d0e0e4736")
      action |> string.contains("harness_config") |> should.be_true
      conserved |> should.be_true
    }
    IntentRejected(_, _, _) -> False |> should.be_true
  }
}

pub fn fpp_intent_hardware_interlock_refusal_test() {
  let dangerous_intent =
    FlightIntent(
      intent_id: "INT-MALICIOUS-002",
      actor: "untrusted_agent",
      verb: UpdateFlightParameter(param_id: 99, value: "WIPE"),
      target_instance: "control_plane",
      target_device_serial: hard_denied_system_os_serial,
      precondition_guard: True,
      formal_proof_ref: "NONE",
    )

  let verdict = evaluate_flight_intent(dangerous_intent)
  case verdict {
    IntentAuthorized(_, _, _, _) -> False |> should.be_true
    IntentRejected(id, code, reason) -> {
      id |> should.equal("INT-MALICIOUS-002")
      code |> should.equal(403)
      reason |> string.contains("25503L801736") |> should.be_true
      reason |> string.contains("hardware-locked") |> should.be_true
    }
  }
}

pub fn fpp_intent_precondition_guard_refusal_test() {
  let failed_precond_intent =
    FlightIntent(
      intent_id: "INT-GUARD-003",
      actor: "operator",
      verb: DispatchFlightCommand(opcode: 0x100, args: []),
      target_instance: "inventory",
      target_device_serial: "SAFE_STORAGE_NVME",
      precondition_guard: False,
      formal_proof_ref: "PROOF-FPP-003",
    )

  let verdict = evaluate_flight_intent(failed_precond_intent)
  case verdict {
    IntentAuthorized(_, _, _, _) -> False |> should.be_true
    IntentRejected(id, code, reason) -> {
      id |> should.equal("INT-GUARD-003")
      code |> should.equal(412)
      reason |> string.contains("Precondition guard failed") |> should.be_true
    }
  }
}

pub fn fpp_intent_json_serialization_test() {
  let valid_intent =
    FlightIntent(
      intent_id: "INT-JSON-004",
      actor: "flight_director",
      verb: DispatchFlightCommand(opcode: 0x701, args: []),
      target_instance: "harness_config",
      target_device_serial: "SAFE_STORAGE_NVME",
      precondition_guard: True,
      formal_proof_ref: "PROOF-FPP-004",
    )

  let verdict = evaluate_flight_intent(valid_intent)
  let json_str = encode_intent_verdict_json(verdict)

  json_str |> string.contains("\"status\":\"authorized\"") |> should.be_true
  json_str |> string.contains("\"status_code\":200") |> should.be_true
  json_str
  |> string.contains("\"contract\":\"SC-FPP-INTENT-001\"")
  |> should.be_true
  json_str |> string.contains("INT-JSON-004") |> should.be_true
}
