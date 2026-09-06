import gleeunit/should
import main.{Doctor, Gate, execute}

pub fn unknown_gate_returns_exit_code_1_test() {
  execute(Gate("UNKNOWN_GATE_FOR_TEST"))
  |> should.equal(1)
}

pub fn known_gate_returns_exit_code_0_test() {
  execute(Gate("G-CHECKLIST"))
  |> should.equal(0)
}

pub fn doctor_returns_exit_code_0_test() {
  execute(Doctor)
  |> should.equal(0)
}
