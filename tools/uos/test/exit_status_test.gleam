import gleeunit/should
import main.{Doctor, Gate, execute}

pub fn unknown_gate_returns_exit_code_1_test() {
  execute(Gate("UNKNOWN_GATE_FOR_TEST"))
  |> should.equal(1)
}

pub fn artifact_gate_cannot_claim_verification_test() {
  execute(Gate("G-CHECKLIST"))
  |> should.equal(1)
}

pub fn doctor_returns_exit_code_1_when_unverifiable_cycles_exist_test() {
  execute(Doctor)
  |> should.equal(1)
}

pub fn mirage_gates_fail_closed_without_behavioral_and_formal_evidence_test() {
  execute(Gate("G-MIRAGE"))
  |> should.equal(1)
  execute(Gate("G-MIRAGE-MIGRATE"))
  |> should.equal(1)
  execute(Gate("mirage-migration"))
  |> should.equal(1)
  execute(Gate("G-MIRAGE-PROD"))
  |> should.equal(1)
  execute(Gate("mirage-prod"))
  |> should.equal(1)
  execute(Gate("G-MIRAGE-TENDERS"))
  |> should.equal(1)
}
