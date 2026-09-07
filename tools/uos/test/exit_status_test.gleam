import gleeunit/should
import main.{Doctor, Gate, SelfcheckMirage, SelfcheckMirageMigration, SelfcheckMirageProd, execute}

pub fn unknown_gate_returns_exit_code_1_test() {
  execute(Gate("UNKNOWN_GATE_FOR_TEST"))
  |> should.equal(1)
}

pub fn known_gate_returns_exit_code_0_test() {
  execute(Gate("G-CHECKLIST"))
  |> should.equal(0)
}

pub fn doctor_fails_closed_while_mirage_is_not_verified_test() {
  execute(Doctor)
  |> should.equal(1)
}

pub fn mirage_gates_fail_closed_without_behavioral_and_formal_evidence_test() {
  execute(Gate("G-MIRAGE"))
  |> should.equal(1)
  execute(Gate("G-MIRAGE-MIGRATE"))
  |> should.equal(1)
  execute(Gate("G-MIRAGE-PROD"))
  |> should.equal(1)
}

pub fn mirage_selfchecks_fail_closed_without_behavioral_and_formal_evidence_test() {
  execute(SelfcheckMirage)
  |> should.equal(1)
  execute(SelfcheckMirageMigration)
  |> should.equal(1)
  execute(SelfcheckMirageProd)
  |> should.equal(1)
}
