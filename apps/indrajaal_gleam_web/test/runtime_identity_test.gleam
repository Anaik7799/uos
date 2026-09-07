import gleam/string
import gleeunit/should
import indrajaal/runtime_identity as runtime

fn vm(otp: String) -> runtime.Vm {
  runtime.Vm(otp, "observed-erts", "123", "run-1", 100, 200, 1)
}

fn config() -> runtime.Configuration {
  runtime.Configuration(
    "c08ec3942e12c41d2ac60c3ab4e954969e3983ae",
    "web-primary",
    "primary",
    True,
  )
}

pub fn wrong_otp_cannot_start_or_be_ready_test() {
  let report = runtime.from_observation(vm("27"), config())
  report.runtime_ready |> should.be_false()
  runtime.startup_check(report) |> should.be_error()
}

pub fn managed_missing_candidate_cannot_start_test() {
  let invalid = runtime.Configuration(..config(), candidate: "")
  runtime.from_observation(vm("29"), invalid)
  |> runtime.startup_check
  |> should.be_error()
}

pub fn candidate_and_role_are_bounded_test() {
  runtime.valid_candidate("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa;")
  |> should.be_false()
  runtime.valid_candidate("A08ec3942e12c41d2ac60c3ab4e954969e3983ae")
  |> should.be_false()
  runtime.configured(runtime.Configuration(..config(), role: "administrator"))
  |> should.be_false()
  runtime.configured(runtime.Configuration(..config(), instance: "../primary"))
  |> should.be_false()
}

pub fn supported_managed_identity_is_not_admission_test() {
  let report = runtime.from_observation(vm("29"), config())
  report.runtime_ready |> should.be_true()
  runtime.startup_check(report) |> should.equal(Ok(Nil))
  runtime.to_json(report)
  |> string.contains("\"application_admitted\":false")
  |> should.be_true()
}

pub fn real_vm_identity_is_stable_and_time_is_observed_test() {
  let before = runtime.observe()
  let after = runtime.observe()
  before.vm.otp |> should.equal("29")
  before.vm.os_pid |> string.is_empty |> should.be_false()
  before.vm.run_id |> should.equal(after.vm.run_id)
  { after.vm.uptime_ms >= before.vm.uptime_ms } |> should.be_true()
  { before.vm.started_utc_us > 0 } |> should.be_true()
}
