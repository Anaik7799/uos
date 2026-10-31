//// Fail-closed JSON-tolerant vault metadata loader.
////
//// The metadata snapshot is untrusted input. Symlinks anywhere on the path
//// (including parent directories), oversize empty or non-file stores, strict
//// duplicate-key/NUL JSON guard failures, unknown or forbidden top-level
//// fields, non-text policy values or secret material keys, wrong tenant
//// bindings, and stale or clock-skewed snapshots all yield `UnwiredVault`.
//// An explicit `observed_at_ms` freshness window prevents static metadata from
//// being reported as live health.

import cepaf_gleam/harness/value
import cepaf_gleam/mcp/adapters/feature_receipt_ledger as ledger
import cepaf_gleam/mcp/adapters/vault_metadata
import cepaf_gleam/mcp/json_guard
import envoy
import gleam/dict
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import simplifile

pub const max_vault_metadata_bytes = 262_144

pub const default_max_age_ms = 300_000

pub const max_freshness_ms = 3_600_000

pub const clock_skew_tolerance_ms = 5000

const allowed_top_level_keys = [
  "tenant_id",
  "sealed",
  "healthy",
  "observed_at_ms",
  "max_age_ms",
  "secret_names",
  "policies",
  "audit_lines",
]

const forbidden_policy_key_fragments = [
  "secret",
  "token",
  "password",
  "private_key",
  "api_key",
  "unseal",
  "root_token",
  "vault_token",
  "secret_value",
  "unseal_keys",
]

@external(erlang, "cepaf_gleam_ffi", "system_time_nanos")
fn system_time_nanos() -> Int

pub fn default_metadata_path(root: String) -> String {
  root <> "/var/vault/metadata.json"
}

fn env_override(name: String) -> Option(String) {
  case envoy.get(name) {
    Ok(value) if value != "" -> Some(value)
    _ -> None
  }
}

pub fn load_vault_handle(root: String) -> vault_metadata.VaultHandle {
  let metadata_path = case env_override("UOS_VAULT_SNAPSHOT_PATH") {
    Some(path) -> path
    None ->
      case env_override("UOS_VAULT_METADATA_PATH") {
        Some(path) -> path
        None -> default_metadata_path(root)
      }
  }
  case ledger.normalized_absolute_path(metadata_path) {
    True -> load_vault_handle_from(root, metadata_path)
    False ->
      vault_metadata.UnwiredVault(
        "Vault snapshot path must be absolute and normalized",
      )
  }
}

pub fn load_vault_handle_from(
  root: String,
  metadata_path: String,
) -> vault_metadata.VaultHandle {
  load_vault_handle_at(root, metadata_path, system_time_nanos() / 1_000_000)
}

/// Deterministic clock-injected loader used by tests. The tenant is compared
/// exactly against `root` with no whitespace trimming so the transport-bound
/// `principal.workspace_root` matches 100%.
pub fn load_vault_handle_at(
  root: String,
  metadata_path: String,
  now_ms: Int,
) -> vault_metadata.VaultHandle {
  case root == "" {
    True ->
      vault_metadata.UnwiredVault("Workspace root missing for vault metadata")
    False ->
      case ledger.has_unsafe_ancestor(metadata_path) {
        True -> vault_metadata.UnwiredVault("Vault metadata symlink forbidden")
        False ->
          case
            simplifile.is_file(metadata_path),
            simplifile.file_info(metadata_path)
          {
            Ok(False), _ | Error(_), _ ->
              vault_metadata.UnwiredVault(
                "Vault metadata store unwired or absent",
              )
            Ok(True), Error(_) ->
              vault_metadata.UnwiredVault(
                "Vault metadata corrupt or exceeds 256 KiB bound",
              )
            Ok(True), Ok(info) ->
              case info.size > max_vault_metadata_bytes || info.size <= 0 {
                True ->
                  vault_metadata.UnwiredVault(
                    "Vault metadata corrupt or exceeds 256 KiB bound",
                  )
                False ->
                  case
                    ledger.read_bounded(metadata_path, max_vault_metadata_bytes)
                  {
                    Error(_) ->
                      vault_metadata.UnwiredVault(
                        "Vault metadata unreadable or oversized",
                      )
                    Ok(raw) ->
                      case string.byte_size(raw) > max_vault_metadata_bytes {
                        True ->
                          vault_metadata.UnwiredVault(
                            "Vault metadata unreadable or oversized",
                          )
                        False ->
                          case json_guard.native_inspect(raw, 16) {
                            Error(_) ->
                              vault_metadata.UnwiredVault(
                                "Vault metadata JSON corrupt or failed strict OTP29 guard",
                              )
                            Ok(parsed) ->
                              case parsed {
                                value.Object(fields) ->
                                  case
                                    validate_vault_metadata(
                                      fields,
                                      root,
                                      now_ms,
                                    )
                                  {
                                    Ok(handle) -> handle
                                    Error(reason) ->
                                      vault_metadata.UnwiredVault(reason)
                                  }
                                _ ->
                                  vault_metadata.UnwiredVault(
                                    "Vault metadata must be a JSON object",
                                  )
                              }
                          }
                      }
                  }
              }
          }
      }
  }
}

// ---------------------------------------------------------------------------
// Symlink ancestor guard
// ---------------------------------------------------------------------------

// Strict schema validation
// ---------------------------------------------------------------------------

fn get_field(
  fields: List(#(String, value.Value)),
  key: String,
) -> Result(value.Value, Nil) {
  case list.find(fields, fn(pair) { pair.0 == key }) {
    Ok(pair) -> Ok(pair.1)
    Error(_) -> Error(Nil)
  }
}

fn required_text(
  fields: List(#(String, value.Value)),
  key: String,
) -> Result(String, String) {
  case get_field(fields, key) {
    Ok(value.Text(text)) if text != "" -> Ok(text)
    _ -> Error("Vault metadata schema invalid")
  }
}

fn required_bool(
  fields: List(#(String, value.Value)),
  key: String,
) -> Result(Bool, String) {
  case get_field(fields, key) {
    Ok(value.Boolean(flag)) -> Ok(flag)
    _ -> Error("Vault metadata schema invalid")
  }
}

fn required_int(
  fields: List(#(String, value.Value)),
  key: String,
) -> Result(Int, String) {
  case get_field(fields, key) {
    Ok(value.Integer(number)) -> Ok(number)
    _ -> Error("Vault metadata schema invalid")
  }
}

fn parse_secret_names(
  fields: List(#(String, value.Value)),
) -> Result(List(String), String) {
  case get_field(fields, "secret_names") {
    Error(_) -> Ok([])
    Ok(value.Array(items)) ->
      list.try_map(items, fn(item) {
        case item {
          value.Text(name) if name != "" -> Ok(name)
          _ -> Error("Vault metadata schema invalid")
        }
      })
    Ok(_) -> Error("Vault metadata schema invalid")
  }
}

fn parse_policies(
  fields: List(#(String, value.Value)),
) -> Result(dict.Dict(String, String), String) {
  case get_field(fields, "policies") {
    Error(_) -> Ok(dict.new())
    Ok(value.Object(pfields)) -> {
      use pairs <- result.try(
        list.try_map(pfields, fn(pair) {
          let key = pair.0
          let lower_key = string.lowercase(key)
          let key_forbidden =
            list.any(forbidden_policy_key_fragments, fn(fragment) {
              lower_key == fragment
            })
          case key_forbidden {
            True -> Error("Vault metadata policy key forbidden")
            False ->
              case pair.1 {
                value.Text(policy) -> Ok(#(key, vault_metadata.redact(policy)))
                _ -> Error("Vault metadata schema invalid")
              }
          }
        }),
      )
      Ok(dict.from_list(pairs))
    }
    Ok(_) -> Error("Vault metadata schema invalid")
  }
}

fn parse_audit_lines(
  fields: List(#(String, value.Value)),
) -> Result(List(String), String) {
  case get_field(fields, "audit_lines") {
    Error(_) -> Ok([])
    Ok(value.Array(alines)) ->
      list.try_map(alines, fn(line) {
        case line {
          value.Text(text) -> Ok(vault_metadata.redact(text))
          _ -> Error("Vault metadata schema invalid")
        }
      })
    Ok(_) -> Error("Vault metadata schema invalid")
  }
}

fn parse_max_age_ms(
  fields: List(#(String, value.Value)),
) -> Result(Int, String) {
  case get_field(fields, "max_age_ms") {
    Error(_) -> Ok(default_max_age_ms)
    Ok(value.Integer(age_ms)) if age_ms > 0 && age_ms <= max_freshness_ms ->
      Ok(age_ms)
    Ok(_) -> Error("Vault metadata schema invalid")
  }
}

fn validate_vault_metadata(
  fields: List(#(String, value.Value)),
  root: String,
  now_ms: Int,
) -> Result(vault_metadata.VaultHandle, String) {
  case
    list.any(fields, fn(field) {
      !list.contains(allowed_top_level_keys, field.0)
    })
  {
    True -> Error("Vault metadata contains unknown or forbidden field")
    False -> {
      use tenant_id <- result.try(required_text(fields, "tenant_id"))
      case tenant_id != root {
        True -> Error("Vault metadata tenant_id does not match workspace root")
        False -> {
          use seal_state <- result.try(required_bool(fields, "sealed"))
          use healthy <- result.try(required_bool(fields, "healthy"))
          use observed_at_ms <- result.try(required_int(
            fields,
            "observed_at_ms",
          ))
          use max_age_ms <- result.try(parse_max_age_ms(fields))
          let clock_skewed = observed_at_ms > now_ms + clock_skew_tolerance_ms
          let stale = now_ms - observed_at_ms > max_age_ms
          case clock_skewed || stale {
            True -> Error("Vault metadata snapshot stale or clock-skewed")
            False -> {
              use secret_names <- result.try(parse_secret_names(fields))
              use policies <- result.try(parse_policies(fields))
              use audit_lines <- result.try(parse_audit_lines(fields))
              case dict.size(policies) == 0 {
                True -> Error("Vault metadata schema invalid")
                False ->
                  Ok(vault_metadata.SupervisedVault(
                    tenant_id: root,
                    seal_state: seal_state,
                    healthy: healthy,
                    secret_names: secret_names,
                    policies: policies,
                    audit_lines: audit_lines,
                  ))
              }
            }
          }
        }
      }
    }
  }
}
