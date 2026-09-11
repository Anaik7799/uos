import gleeunit/should
import main.{
  Doctor, Gate, SelfcheckMirage, SelfcheckMirageMigration, SelfcheckMirageProd,
  SelfcheckMirageTenders, execute,
}

pub fn unknown_gate_returns_exit_code_1_test() {
  execute(Gate("UNKNOWN_GATE_FOR_TEST"))
  |> should.equal(1)
}

pub fn known_gate_returns_exit_code_0_test() {
  execute(Gate("G-CHECKLIST"))
  |> should.equal(0)
}

pub fn doctor_returns_exit_code_1_when_unverifiable_cycles_exist_test() {
  execute(Doctor)
  |> should.equal(1)
}

pub fn mirage_gates_return_exit_code_0_when_verified_test() {
  execute(Gate("G-MIRAGE"))
  |> should.equal(0)
  execute(Gate("G-MIRAGE-MIGRATE"))
  |> should.equal(0)
  execute(Gate("G-MIRAGE-PROD"))
  |> should.equal(0)
  execute(Gate("G-MIRAGE-TENDERS"))
  |> should.equal(0)
}

pub fn mirage_selfchecks_return_exit_code_0_when_verified_test() {
  execute(SelfcheckMirage)
  |> should.equal(0)
  execute(SelfcheckMirageMigration)
  |> should.equal(0)
  execute(SelfcheckMirageProd)
  |> should.equal(0)
  execute(SelfcheckMirageTenders)
  |> should.equal(0)
}
