//// Explicit finite-environment native transport; observation, never authority.
//// Laws: invalid configuration/body dispatches nothing; closed profile ignores
//// inherited environment; failure never selects legacy transport. The runtime
//// also checks its actual architecture. Immutable owned executable paths and
//// trusted BEAM startup remain premises; this constructor grants no permission.

import cepaf_gleam/harness/telegram_store_transport as legacy
import gleam/list
import gleam/option.{type Option, None}
import gleam/result
import gleam/string

pub type Architecture {
  LinuxX8664
  UnsupportedArchitecture
}

pub type EnvironmentProfile {
  NativeStorageV1
}

pub type ConfigurationError {
  UnsupportedHost
  InvalidPath
  InvalidDigest
}

pub opaque type Configuration {
  FiniteConfiguration(
    architecture: Architecture,
    profile: EnvironmentProfile,
    launcher: String,
    launcher_sha256: String,
    guardian: String,
    guardian_sha256: String,
    worker: String,
    worker_sha256: String,
    configuration: String,
  )
}

fn path(text: String) -> Bool {
  string.byte_size(text) > 1
  && string.byte_size(text) <= 4096
  && string.starts_with(text, "/")
  && !string.contains(text, "\u{0000}")
  && list.all(string.split(string.drop_start(text, 1), "/"), fn(p) {
    p != "" && p != "." && p != ".."
  })
}

fn digest(text: String) -> Bool {
  string.byte_size(text) == 64
  && list.all(string.to_graphemes(text), fn(c) {
    string.byte_size(c) == 1 && string.contains("0123456789abcdef", c)
  })
}

pub fn reviewed_configuration(
  architecture: Architecture,
  profile: EnvironmentProfile,
  launcher: String,
  launcher_sha256: String,
  guardian: String,
  guardian_sha256: String,
  worker: String,
  worker_sha256: String,
  configuration: String,
) -> Result(Configuration, ConfigurationError) {
  case architecture {
    UnsupportedArchitecture -> Error(UnsupportedHost)
    LinuxX8664 ->
      case
        list.all([launcher, guardian, worker, configuration], path),
        list.all([launcher_sha256, guardian_sha256, worker_sha256], digest)
      {
        False, _ -> Error(InvalidPath)
        _, False -> Error(InvalidDigest)
        True, True ->
          Ok(FiniteConfiguration(
            architecture,
            profile,
            launcher,
            launcher_sha256,
            guardian,
            guardian_sha256,
            worker,
            worker_sha256,
            configuration,
          ))
      }
  }
}

/// Fixed values are public constants, not process environment observations.
pub fn environment(profile: EnvironmentProfile) -> List(#(String, String)) {
  case profile {
    NativeStorageV1 -> [
      #("PATH", "/nonexistent"),
      #("LANG", "C"),
      #("LC_ALL", "C"),
      #("TZ", "UTC"),
    ]
  }
}

@external(erlang, "telegram_store_transport_ffi", "finite_request_with_cleanup")
fn native_request(
  config: Configuration,
  body: String,
) -> #(Result(String, String), Option(#(Int, Int)))

pub fn exchange_with_cleanup(
  config: Configuration,
  body: String,
) -> #(Result(String, legacy.TransportError), Option(#(Int, Int))) {
  case string.byte_size(body) {
    0 -> #(Error(legacy.InputBound), None)
    n if n > legacy.max_body_bytes -> #(Error(legacy.InputBound), None)
    _ -> {
      let #(response, cleanup) = native_request(config, body)
      #(
        result.map_error(response, fn(code) {
          case code {
            "transport_input_bound" -> legacy.InputBound
            "transport_configuration_or_spawn" -> legacy.ConfigurationOrSpawn
            "transport_cleanup_unknown" -> legacy.CleanupUnknown
            _ -> legacy.Uncertain
          }
        }),
        cleanup,
      )
    }
  }
}
