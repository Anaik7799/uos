//// Runtime observations shared by HTTP, Lustre and the terminal.
//// Release metadata is declared configuration, never an admission certificate.

import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/string
import lustre/element.{type Element, text}
import lustre/element/html

pub type Vm {
  Vm(
    otp: String,
    erts: String,
    os_pid: String,
    run_id: String,
    started_utc_us: Int,
    observed_utc_us: Int,
    uptime_ms: Int,
  )
}

pub type Configuration {
  Configuration(
    candidate: String,
    instance: String,
    role: String,
    managed: Bool,
  )
}

pub type Report {
  Report(vm: Vm, configuration: Configuration, runtime_ready: Bool)
}

@external(erlang, "uos_web_runtime_ffi", "observe_vm")
fn observe_vm() -> #(String, String, String, String, Int, Int, Int)

@external(erlang, "uos_web_runtime_ffi", "configuration")
fn configuration() -> #(String, String, String, Bool)

pub fn supported(otp: String) -> Bool {
  otp == "29" || otp == "27"
}

pub fn valid_candidate(candidate: String) -> Bool {
  string.byte_size(candidate) == 40
  && list.all(string.to_graphemes(candidate), fn(char) {
    string.contains("0123456789abcdef", char)
  })
}

fn valid_instance(instance: String) -> Bool {
  string.byte_size(instance) > 0
  && string.byte_size(instance) <= 64
  && list.all(string.to_graphemes(instance), fn(char) {
    string.contains(
      "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_",
      char,
    )
  })
}

pub fn configured(config: Configuration) -> Bool {
  valid_candidate(config.candidate)
  && valid_instance(config.instance)
  && { config.role == "primary" || config.role == "backup" }
}

pub fn from_observation(vm: Vm, config: Configuration) -> Report {
  Report(vm, config, supported(vm.otp) && configured(config))
}

pub fn observe() -> Report {
  let #(otp, erts, pid, run_id, started, now, uptime) = observe_vm()
  let #(candidate, instance, role, managed) = configuration()
  from_observation(
    Vm(otp, erts, pid, run_id, started, now, uptime),
    Configuration(candidate, instance, role, managed),
  )
}

pub fn startup_check(report: Report) -> Result(Nil, String) {
  case
    supported(report.vm.otp),
    report.configuration.managed,
    configured(report.configuration)
  {
    False, _, _ ->
      Error("UOS web requires OTP 29; observed OTP " <> report.vm.otp)
    True, True, False ->
      Error(
        "Managed UOS web requires a 40-hex candidate, bounded instance ID and primary/backup role",
      )
    True, _, _ -> Ok(Nil)
  }
}

pub fn to_json(report: Report) -> String {
  json.object([
    #("schema", json.string("uos.web-runtime-identity.v1")),
    #("runtime_ready", json.bool(report.runtime_ready)),
    #("application_admitted", json.bool(False)),
    #(
      "authority",
      json.string(
        "running VM observation; release metadata is declared, not attested",
      ),
    ),
    #("otp_release", json.string(report.vm.otp)),
    #("erts_version", json.string(report.vm.erts)),
    #("os_pid", json.string(report.vm.os_pid)),
    #("run_id", json.string(report.vm.run_id)),
    #("started_utc_us", json.int(report.vm.started_utc_us)),
    #("observed_utc_us", json.int(report.vm.observed_utc_us)),
    #("vm_monotonic_elapsed_ms", json.int(report.vm.uptime_ms)),
    #(
      "declared_candidate_revision",
      json.string(report.configuration.candidate),
    ),
    #("declared_instance_id", json.string(report.configuration.instance)),
    #("declared_role", json.string(report.configuration.role)),
    #("managed", json.bool(report.configuration.managed)),
    #(
      "scope",
      json.string(
        "VM identity only; application readiness, artifact binding and writer fencing require independent checks",
      ),
    ),
  ])
  |> json.to_string
}

pub fn view(report: Report) -> Element(a) {
  html.section([], [
    html.h1([], [text("Running web VM")]),
    html.p([], [
      text(
        "Observed OTP "
        <> report.vm.otp
        <> ", ERTS "
        <> report.vm.erts
        <> ", OS PID "
        <> report.vm.os_pid,
      ),
    ]),
    html.p([], [
      text(
        "Instance: "
        <> report.configuration.instance
        <> " · role: "
        <> report.configuration.role,
      ),
    ]),
    html.p([], [text("Declared candidate: " <> report.configuration.candidate)]),
    html.p([], [
      text("VM elapsed time: " <> int.to_string(report.vm.uptime_ms) <> " ms"),
    ]),
    html.p([], [
      text(
        "Identity observations do not grant application admission or deployment authority.",
      ),
    ]),
    html.pre([], [text(to_json(report))]),
  ])
}

/// Terminal projection uses the same observation and schema as the web surface.
pub fn main() {
  observe() |> to_json |> io.println
}
