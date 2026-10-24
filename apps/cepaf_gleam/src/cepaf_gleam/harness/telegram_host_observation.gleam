import cepaf_gleam/harness/clock as checked_clock
import cepaf_gleam/harness/observer_policy as obs
import gleam/bit_array
import gleam/json
import gleam/list
import gleam/string

pub const kernel_sha256 =
  "6b21357f63fe5baf247df4e3aff246779a988d22d0a44dd5558f2ee28a54d930"

const kernel_exe = "/home/an/NAS-setup/uos/engines/zigvm/zig-out/bin/zigvm"

const guardian_exe = "/home/an/NAS-setup/uos/tools/validation/obs_guardian.exe"

const guardian_sha256 =
  "b7bab1a85ffa3689a2548ff28a391e659c0537104dec7be0f774bae1820ec4be"

const kernel_deadline_ms = 1000

const kernel_max_bytes = 256

const kernel_scope = "installed_executable_version_only"

const clock_policy = "development_reference_1h_observation_only"

const admission_not_granted = "NOT_GRANTED"

@external(erlang, "sa_plan_observer_ffi", "observe_checked")
fn invoke(
  guardian: String,
  guardian_sha: String,
  argv: List(String),
  deadline_ms: Int,
  max_bytes: Int,
) -> Result(obs.Observation, String)

pub fn version_payload(
  result: Result(obs.Observation, String),
) -> Result(String, String) {
  case result {
    Ok(observation) ->
      case
        observation.guardian_result == "child_exited"
        && observation.cleanup == "confirmed"
        && observation.child_exit == 0
        && bit_array.byte_size(observation.payload) <= kernel_max_bytes
      {
        True ->
          case bit_array.to_string(observation.payload) {
            Ok(raw) -> parse_version_line(string.trim(raw))
            Error(_) -> Error("kernel_version_unavailable")
          }
        False -> Error("kernel_version_unavailable")
      }
    Error(_) -> Error("kernel_version_unavailable")
  }
}

fn parse_version_line(trimmed: String) -> Result(String, String) {
  case string.split(trimmed, " ") {
    ["zigvm", version] ->
      case valid_version(version) {
        True -> Ok(version)
        False -> Error("kernel_version_unavailable")
      }
    _ -> Error("kernel_version_unavailable")
  }
}

fn valid_version(version: String) -> Bool {
  case string.split(version, ".") {
    [major, minor, patch] ->
      list.all([major, minor, patch], valid_decimal_segment)
    _ -> False
  }
}

fn valid_decimal_segment(segment: String) -> Bool {
  let bytes = string.byte_size(segment)
  case bytes >= 1 && bytes <= 6 {
    True -> list.all(string.to_graphemes(segment), is_ascii_digit)
    False -> False
  }
}

fn is_ascii_digit(grapheme: String) -> Bool {
  case grapheme {
    "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" -> True
    _ -> False
  }
}

pub fn kernel_version() -> Result(String, String) {
  let argv = [
    "--exe",
    kernel_exe,
    "--sha256",
    kernel_sha256,
    "--deadline-ms",
    "1000",
    "--max-bytes",
    "256",
    "--",
    "version",
  ]
  version_payload(invoke(
    guardian_exe,
    guardian_sha256,
    argv,
    kernel_deadline_ms,
    kernel_max_bytes,
  ))
}

pub fn kernel_report() -> json.Json {
  case kernel_version() {
    Ok(version) ->
      json.object([
        #("status", json.string("observed")),
        #("version", json.string(version)),
        #("artifact_sha256", json.string(kernel_sha256)),
        #("scope", json.string(kernel_scope)),
        #("runtime_admission", json.string(admission_not_granted)),
      ])
    Error(_) ->
      json.object([
        #("status", json.string("unavailable")),
        #("reason", json.string("kernel_version_unavailable")),
        #("scope", json.string(kernel_scope)),
        #("runtime_admission", json.string(admission_not_granted)),
      ])
  }
}

pub fn clock_result(
  result: Result(checked_clock.Observation, String),
) -> json.Json {
  case result {
    Ok(observation) -> {
      let sample = observation.sample
      let reference_age_us =
        sample.observed.utc_us - observation.reference_utc_us
      let receipt_age_us =
        sample.observed.boot_us - sample.evidence.reading.boot_us
      json.object([
        #("status", json.string("observed")),
        #("offset_us", json.int(sample.evidence.offset_us)),
        #("uncertainty_us", json.int(sample.evidence.uncertainty_us)),
        #("reference_age_us", json.int(reference_age_us)),
        #("receipt_age_us", json.int(receipt_age_us)),
        #("delivery_us", json.int(observation.delivery_us)),
        #("observed_at_us", json.int(sample.observed.utc_us)),
        #("policy", json.string(clock_policy)),
        #("runtime_admission", json.string(admission_not_granted)),
      ])
    }
    Error(_) ->
      json.object([
        #("status", json.string("unavailable")),
        #("reason", json.string("clock_observation_unavailable")),
        #("policy", json.string(clock_policy)),
        #("runtime_admission", json.string(admission_not_granted)),
      ])
  }
}

pub fn clock_report() -> json.Json {
  clock_result(checked_clock.observe())
}
