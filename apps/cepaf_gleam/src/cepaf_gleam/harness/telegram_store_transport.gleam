//// Storage-only bounded transport. No effect authority or automatic retry.

import gleam/result
import gleam/string

pub const max_body_bytes = 1_048_572

pub opaque type LocalConfiguration {
  LocalConfiguration(
    guardian: String,
    guardian_sha256: String,
    worker: String,
    worker_sha256: String,
    database: String,
  )
}

pub type TransportError {
  InputBound
  ConfigurationOrSpawn
  Uncertain
  CleanupUnknown
}

/// Trusted local launcher input only. This constructor is not a Telegram tool.
/// Hashes pin compiled native files; same-UID replacement is a cooperative boundary.
pub fn reviewed_local_configuration(
  guardian: String,
  guardian_sha256: String,
  worker: String,
  worker_sha256: String,
  database: String,
) -> LocalConfiguration {
  LocalConfiguration(guardian, guardian_sha256, worker, worker_sha256, database)
}

@external(erlang, "telegram_store_transport_ffi", "request")
fn request(
  guardian: String,
  guardian_sha256: String,
  worker: String,
  worker_sha256: String,
  database: String,
  body: String,
) -> Result(String, String)

/// A returned body is transport evidence only: the strict domain codec must
/// validate it before use. Every uncertain result blocks blind retry or send.
pub fn exchange(
  config: LocalConfiguration,
  canonical_request: String,
) -> Result(String, TransportError) {
  case string.byte_size(canonical_request) {
    0 -> Error(InputBound)
    n if n > max_body_bytes -> Error(InputBound)
    _ ->
      request(
        config.guardian,
        config.guardian_sha256,
        config.worker,
        config.worker_sha256,
        config.database,
        canonical_request,
      )
      |> result.map_error(fn(code) {
        case code {
          "transport_input_bound" -> InputBound
          "transport_configuration_or_spawn" -> ConfigurationOrSpawn
          "transport_cleanup_unknown" -> CleanupUnknown
          _ -> Uncertain
        }
      })
  }
}
