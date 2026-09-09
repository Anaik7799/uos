import cepaf_gleam/planning/sa_plan_bridge as bridge
import gleeunit/should

pub fn completion_preserves_attempt_and_literal_arguments_test() {
  bridge.completion_arguments(
    "plan with space",
    "task",
    "worker",
    7,
    "receipt; $(not-a-command)\nline",
  )
  |> should.equal(
    Ok([
      "task",
      "complete",
      "plan with space",
      "task",
      "worker",
      "7",
      "receipt; $(not-a-command)\nline",
    ]),
  )
}

pub fn missing_or_nonpositive_attempt_never_dispatches_test() {
  bridge.completion_arguments("p", "t", "w", 0, "receipt") |> should.be_error
  bridge.completion_arguments("p", "t", "w", -1, "receipt") |> should.be_error
}

pub fn embedded_nul_never_reaches_a_process_test() {
  bridge.run_sa_plan_cli(["status\u{0}"])
  |> should.equal(Error("sa-plan argument bound"))
}

pub fn actual_command_failure_is_an_error_test() {
  bridge.run_sa_plan_cli(["unsupported-harness-verification-verb"])
  |> should.be_error
}

pub fn shell_metacharacters_remain_a_single_literal_argument_test() {
  bridge.run_sa_plan_cli([
    "plan",
    "show",
    "uos-absent; printf UOS_COMMAND_INJECTION",
  ])
  |> should.be_error
}
