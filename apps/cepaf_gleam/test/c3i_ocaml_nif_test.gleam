//// =============================================================================
//// [C3I-SIL6-MSTS] OCaml NIF Integration & Parity Test Suite
//// =============================================================================

import gleeunit/should
import gleam/string
import cepaf_gleam/c3i/ocaml_nif

pub fn ocaml_nif_version_test() {
  let v = ocaml_nif.version()
  string.contains(v, "5.5.0")
  |> should.be_true()

  string.contains(v, "SIL-6-RETE-UL")
  |> should.be_true()
}

pub fn ocaml_nif_rete_nominal_test() {
  case ocaml_nif.evaluate_gate("mesh_running=true,watchdog=true") {
    ocaml_nif.GatePassed(_, raw) -> {
      string.contains(raw, "\"verdict\":\"pass\"")
      |> should.be_true()
    }
    ocaml_nif.GateRejected(reason, _) -> {
      panic as { "Nominal gate unexpectedly rejected: " <> reason }
    }
  }
}

pub fn ocaml_nif_rete_estop_fail_closed_test() {
  case ocaml_nif.evaluate_gate("e_stop=true") {
    ocaml_nif.GateRejected(reason, raw) -> {
      string.contains(reason, "Emergency stop active")
      |> should.be_true()
      string.contains(raw, "SIL6_EmergencyStop_Gate")
      |> should.be_true()
    }
    ocaml_nif.GatePassed(_, _) -> {
      panic as "Emergency stop did not trigger fail-closed gate rejection"
    }
  }
}

pub fn ocaml_nif_rete_high_drift_fail_closed_test() {
  case ocaml_nif.evaluate_gate("high_drift=true") {
    ocaml_nif.GateRejected(reason, raw) -> {
      string.contains(reason, "Cascade failure detected")
      |> should.be_true()
      string.contains(raw, "Cascade_Apoptosis_Gate")
      |> should.be_true()
    }
    ocaml_nif.GatePassed(_, _) -> {
      panic as "High drift did not trigger fail-closed gate rejection"
    }
  }
}

pub fn ocaml_nif_gospel_contract_pass_test() {
  ocaml_nif.verify_contract("fifo_queue", "length=42")
  |> should.be_ok()
}

pub fn ocaml_nif_gospel_contract_violation_test() {
  ocaml_nif.verify_contract("fifo_queue", "length=-5")
  |> should.be_error()
}

pub fn ocaml_nif_zenoh_dispatch_test() {
  let receipt = ocaml_nif.zenoh_dispatch("hermes/control/check", "ping")
  string.contains(receipt, "\"verdict\":\"succeeded\"")
  |> should.be_true()
  string.contains(receipt, "\"receipt_digest\"")
  |> should.be_true()
}

pub fn ocaml_nif_parity_check_test() {
  ocaml_nif.verify_parity("verify_zigvm_hermes_lattice")
  |> should.be_ok()
}

pub fn ocaml_nif_rete_missing_keys_fail_closed_test() {
  case ocaml_nif.evaluate_gate("") {
    ocaml_nif.GateRejected(reason, _) -> {
      string.contains(reason, "FAIL_CLOSED: missing mandatory safety key")
      |> should.be_true()
    }
    ocaml_nif.GatePassed(_, _) -> {
      panic as "Empty facts did not trigger fail-closed missing key rejection"
    }
  }
}

pub fn ocaml_nif_rete_buffer_overflow_fail_closed_test() {
  let giant_payload = string.repeat("padding=very_long_string_entry,", 200)
  case ocaml_nif.evaluate_gate(giant_payload) {
    ocaml_nif.GateRejected(reason, _) -> {
      string.contains(reason, "FAIL_CLOSED: buffer overflow")
      |> should.be_true()
    }
    ocaml_nif.GatePassed(_, _) -> {
      panic as "Buffer overflow did not trigger fail-closed rejection"
    }
  }
}

pub fn ocaml_nif_rete_unknown_key_fail_closed_test() {
  case ocaml_nif.evaluate_gate("mesh_running=true,watchdog=true,unknown_key=true") {
    ocaml_nif.GateRejected(reason, _) -> {
      string.contains(reason, "FAIL_CLOSED: unknown_key 'unknown_key' not in closed RETE fact schema")
      |> should.be_true()
    }
    ocaml_nif.GatePassed(_, _) -> {
      panic as "Unknown key did not trigger fail-closed closed-schema rejection"
    }
  }
}

pub fn ocaml_nif_rete_invalid_boolean_fail_closed_test() {
  case ocaml_nif.evaluate_gate("mesh_running=true,watchdog=true,e_stop=INVALID") {
    ocaml_nif.GateRejected(reason, _) -> {
      string.contains(reason, "FAIL_CLOSED: invalid_value for 'e_stop'")
      |> should.be_true()
    }
    ocaml_nif.GatePassed(_, _) -> {
      panic as "Invalid boolean value did not trigger fail-closed rejection"
    }
  }
}

pub fn ocaml_nif_rete_duplicate_key_fail_closed_test() {
  case ocaml_nif.evaluate_gate("mesh_running=true,watchdog=true,watchdog=false") {
    ocaml_nif.GateRejected(reason, _) -> {
      string.contains(reason, "FAIL_CLOSED: duplicate_key: watchdog")
      |> should.be_true()
    }
    ocaml_nif.GatePassed(_, _) -> {
      panic as "Duplicate key did not trigger fail-closed rejection"
    }
  }
}

