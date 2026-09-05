import gleeunit
import gleeunit/should
import main.{Doctor, Gate, Help, Status, DmcCheck, TcmCheck, TimestampCheck, parse_args, matches_timestamp_format}

pub fn main() {
  gleeunit.main()
}

pub fn parse_status_test() {
  parse_args(["status"])
  |> should.equal(Status)
}

pub fn parse_gate_test() {
  parse_args(["gate", "G-BOOT1"])
  |> should.equal(Gate("G-BOOT1"))
}

pub fn parse_doctor_test() {
  parse_args(["doctor"])
  |> should.equal(Doctor)
}

pub fn parse_dmc_check_test() {
  parse_args(["dmc-check"])
  |> should.equal(DmcCheck)
}

pub fn parse_tcm_check_test() {
  parse_args(["tcm-check"])
  |> should.equal(TcmCheck)
}

pub fn parse_timestamp_check_test() {
  parse_args(["timestamp-check"])
  |> should.equal(TimestampCheck)
}

pub fn timestamp_regex_valid_test() {
  matches_timestamp_format("20260905-1725-task-journal.md")
  |> should.be_true()
}

pub fn timestamp_regex_invalid_test() {
  matches_timestamp_format("task-journal.md")
  |> should.be_false()
}

pub fn parse_help_test() {
  parse_args(["unknown"])
  |> should.equal(Help)
}
