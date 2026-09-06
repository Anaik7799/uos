import gleeunit/should
import main.{Doctor, Evidence, Gate, execute, file_exists, parse_args}

pub fn unknown_gate_returns_exit_code_1_test() {
  execute(Gate("UNKNOWN_GATE_FOR_TEST"))
  |> should.equal(1)
}

pub fn document_only_gate_returns_exit_code_1_test() {
  execute(Gate("G-CHECKLIST"))
  |> should.equal(1)
}

pub fn doctor_without_fresh_receipts_returns_exit_code_1_test() {
  execute(Doctor)
  |> should.equal(1)
}

pub fn evidence_fixture_command_is_parsed_test() {
  parse_args(["verification-evaluate", "--fixture", "fixture.json"])
  |> should.equal(Evidence("fixture.json"))
}

pub fn candidate_file_checks_do_not_borrow_canonical_root_test() {
  file_exists("apps/cepaf_gleam/gleam.toml")
  |> should.be_false()
}
