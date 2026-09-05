import gleeunit/should
import cepaf_gleam/verification/fractal_web_check_engine.{
  CheckFail, CheckPass, Critical, LustreWeb, WebCheckSpec,
  check_suite_passed, evaluate_check_suite, evaluate_single_check,
}

pub fn evaluate_passing_check_test() {
  let spec =
    WebCheckSpec(
      id: "CHK-08-C1C8",
      name: "C1-C8 Gold Standard",
      surface: LustreWeb,
      layer: 4,
      severity: Critical,
      predicate: fn() { True },
    )
  let result = evaluate_single_check(spec)
  should.equal(result.check_id, "CHK-08-C1C8")
  should.equal(result.status, CheckPass)
}

pub fn evaluate_failing_check_test() {
  let spec =
    WebCheckSpec(
      id: "CHK-05-MUDA",
      name: "Zero Muda Purity",
      surface: LustreWeb,
      layer: 0,
      severity: Critical,
      predicate: fn() { False },
    )
  let result = evaluate_single_check(spec)
  should.equal(result.status, CheckFail)
}

pub fn evaluate_check_suite_aggregate_test() {
  let specs = [
    WebCheckSpec(
      id: "CHK-01-TIME",
      name: "Timestamp Rule",
      surface: LustreWeb,
      layer: 1,
      severity: Critical,
      predicate: fn() { True },
    ),
    WebCheckSpec(
      id: "CHK-02-TAIL",
      name: "Tailscale Link",
      surface: LustreWeb,
      layer: 1,
      severity: Critical,
      predicate: fn() { True },
    ),
  ]
  let evaluations = evaluate_check_suite(specs)
  should.equal(check_suite_passed(evaluations), True)
}
