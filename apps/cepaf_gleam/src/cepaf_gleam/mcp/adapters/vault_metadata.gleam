//// Vault metadata only. Tenant scope is the transport-bound principal workspace
//// root until the principal contract supplies a separate authenticated tenant.

import cepaf_gleam/mcp/admission.{type ValidatedCall}
import cepaf_gleam/mcp/candidate_id
import cepaf_gleam/mcp/evidence
import cepaf_gleam/mcp/principal
import cepaf_gleam/mcp/types.{type Outcome, NonRetryable, Refused, ToolError}
import gleam/dict.{type Dict}
import gleam/json
import gleam/list
import gleam/string

pub type VaultHandle {
  UnwiredVault(reason: String)
  SupervisedVault(
    tenant_id: String,
    seal_state: Bool,
    healthy: Bool,
    secret_names: List(String),
    policies: Dict(String, String),
    audit_lines: List(String),
  )
}

/// Conservative whole-field redaction prevents leaking suffixes or multiline
/// keys. Matching is case-insensitive. Bare `sk-` is deliberately NOT a
/// pattern because it would falsely redact benign identifiers such as
/// `task-123` or `disk-1`; only concrete provider prefixes are matched.
pub fn redact(value: String) -> String {
  let lower = string.lowercase(value)
  case
    list.any(
      [
        "hvs.",
        "hvb.",
        "hvr.",
        "eyj",
        "bearer ",
        "bearer\t",
        "token=",
        "secret=",
        "secret_value=",
        "private key",
        "-----begin",
        "ghp_",
        "ghs_",
        "glpat-",
        "ya29.",
        "aiza",
        "github_pat_",
        "xoxb-",
        "sk-proj-",
        "sk-ant-",
        "sk-live-",
        "root_token=",
        "password=",
        "password:",
        "apikey=",
        "api_key=",
        "vault_token=",
      ],
      fn(pattern) { string.contains(lower, pattern) },
    )
    || aws_key(value)
    || url_userinfo(value)
  {
    True -> "[REDACTED]"
    False -> value
  }
}

fn aws_key(value: String) -> Bool {
  case string.split_once(value, "AKIA") {
    Error(_) -> False
    Ok(#(_, suffix)) -> {
      let chars = string.to_graphemes(string.slice(suffix, 0, 16))
      list.length(chars) == 16
      && list.all(chars, fn(c) {
        string.contains("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789", c)
      })
      || aws_key(suffix)
    }
  }
}

fn url_userinfo(value: String) -> Bool {
  case string.split_once(value, "://") {
    Error(_) -> False
    Ok(#(_, rest)) -> {
      let authority = string.split(rest, "/") |> list.first
      case authority {
        Ok(host) ->
          string.contains(host, "@")
          && string.contains(host, ":")
          || url_userinfo(rest)
        _ -> False
      }
    }
  }
}

fn refused(code: String, reason: String) -> Outcome {
  Refused(ToolError(code, redact(reason), NonRetryable))
}

pub fn execute(handle: VaultHandle, call: ValidatedCall) -> Outcome {
  case handle {
    UnwiredVault(reason) -> refused("VAULT_BACKEND_UNWIRED", reason)
    SupervisedVault(tenant, sealed, healthy, names, policies, audit) -> {
      let scope = principal.workspace_root(call.principal)
      let requested = case dict.get(call.arguments, "tenant_id") {
        Ok(value) -> value
        Error(_) -> scope
      }
      case requested == scope && tenant == scope && scope != "" {
        False ->
          refused(
            "VAULT_CROSS_TENANT_FORBIDDEN",
            "Requested tenant is outside authenticated tenant scope",
          )
        True ->
          case call.spec.name {
            "vault_status" ->
              complete(call, json.object([#("sealed", json.bool(sealed))]))
            "vault_health" ->
              complete(call, json.object([#("healthy", json.bool(healthy))]))
            "vault_list_secrets" ->
              complete(
                call,
                json.object([
                  #(
                    "secret_names",
                    json.array(names, fn(name) { json.string(redact(name)) }),
                  ),
                ]),
              )
            "vault_audit_tail" ->
              complete(
                call,
                json.object([
                  #(
                    "audit_lines",
                    json.array(audit, fn(line) { json.string(redact(line)) }),
                  ),
                ]),
              )
            "vault_policy_get" -> {
              let name = case dict.get(call.arguments, "policy") {
                Ok(value) -> value
                Error(_) -> "default"
              }
              case dict.get(policies, name) {
                Ok(policy) ->
                  complete(
                    call,
                    json.object([#("policy", json.string(redact(policy)))]),
                  )
                Error(_) ->
                  refused("VAULT_POLICY_NOT_FOUND", "Vault policy not found")
              }
            }
            _ ->
              refused(
                "UNSUPPORTED_VAULT_METADATA_TOOL",
                "Unsupported vault metadata tool",
              )
          }
      }
    }
  }
}

fn complete(call: ValidatedCall, payload: json.Json) -> Outcome {
  evidence.classify_backend_payload(
    call.spec.route,
    call.spec.name,
    json.to_string(payload),
    candidate_id.current(),
  )
}
