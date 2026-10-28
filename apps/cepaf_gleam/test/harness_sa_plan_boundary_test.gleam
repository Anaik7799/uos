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

pub fn renewal_preserves_exact_owner_attempt_and_literal_arguments_test() {
  bridge.renewal_arguments("p with space", "t", "w; literal", 2, 3_600_000_000_000)
  |> should.equal(Ok(["task", "renew", "p with space", "t", "w; literal", "2", "3600000000000"]))
}

pub fn renewal_rejects_invalid_attempt_and_duration_before_dispatch_test() {
  bridge.renewal_arguments("p", "t", "w", 0, 1) |> should.be_error
  bridge.renewal_arguments("p", "t", "w", -1, 1) |> should.be_error
  bridge.renewal_arguments("p", "t", "w", 1, 0) |> should.be_error
  bridge.renewal_arguments("p", "t", "w", 1, -1) |> should.be_error
  bridge.renewal_arguments("p", "t", "w", 1, 3_600_000_000_001) |> should.be_error
  bridge.renewal_arguments("p", "t", "w", 1, 1)
  |> should.equal(Ok(["task", "renew", "p", "t", "w", "1", "1"]))
}

pub fn renewal_rejects_empty_or_nul_fields_before_dispatch_test() {
  bridge.renewal_arguments("", "t", "w", 1, 1) |> should.be_error
  bridge.renewal_arguments("p", " ", "w", 1, 1) |> should.be_error
  bridge.renewal_arguments("p", "t", "", 1, 1) |> should.be_error
  bridge.renewal_arguments("p\u{0}", "t", "w", 1, 1) |> should.be_error
  bridge.renewal_arguments("p", "t\u{0}", "w", 1, 1) |> should.be_error
  bridge.renewal_arguments("p", "t", "w\u{0}", 1, 1) |> should.be_error
}
