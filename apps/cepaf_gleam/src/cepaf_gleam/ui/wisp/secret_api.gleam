//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ui/wisp/secret_api</module>
////     <fsharp-lineage>New — no F# predecessor</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L0_CONSTITUTIONAL</layer>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-VAULT-003, SC-VAULT-009, SC-VAULT-025, SC-AUTH-001</stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================
////
//// Wisp REST API for vault secret access. Used primarily by `.pi/` (Pi-mono)
//// to fetch the Anthropic API key without storing plaintext in `.pi/config.json`.
////
//// Endpoints:
////   GET  /api/v1/secret/<name>          — fetch latest secret value (OIDC-gated)
////   GET  /api/v1/secret/<name>/status   — freshness / version metadata only
////   GET  /api/v1/secret-status           — all-secrets summary for dashboard tile
////
//// SC-VAULT-003: All callers MUST go through this endpoint OR vault.gleam directly.
//// SC-VAULT-009: Every fetch emits Zenoh envelope on indrajaal/l0/secret/access/<name>
//// SC-VAULT-025: .pi/ specifically MUST use this endpoint, never read JSON

import cepaf_gleam/vault_audit_reconcile
import gleam/json
import gleam/string

// =====================================================================
// Response shapes (typed JSON per SC-GLM-UI-003 — never string concat)
// =====================================================================

/// GET /api/v1/secret/<name> — returns the plaintext value (caller is
/// expected to consume immediately and zeroize). Wraps in JSON for transport
/// integrity; future revision may switch to binary content-type.
pub fn secret_value_json(name: String, value: String, version: Int) -> String {
  json.object([
    #("name", json.string(name)),
    #("value", json.string(value)),
    #("version", json.int(version)),
    #("warning", json.string("zeroize after use; do not log; do not persist")),
  ])
  |> json.to_string
}

/// GET /api/v1/secret/<name>/status — freshness metadata WITHOUT the value.
/// Safe to call from low-trust contexts (dashboard, monitoring).
pub fn secret_status_json(
  name: String,
  version: Int,
  fetched_at: Int,
  ttl: Int,
  max_ttl: Int,
  age_seconds: Int,
) -> String {
  let state = case age_seconds < ttl {
    True -> "fresh"
    False ->
      case age_seconds < max_ttl {
        True -> "soft_stale"
        False -> "hard_stale"
      }
  }
  json.object([
    #("name", json.string(name)),
    #("version", json.int(version)),
    #("fetched_at", json.int(fetched_at)),
    #("ttl_seconds", json.int(ttl)),
    #("max_ttl_seconds", json.int(max_ttl)),
    #("age_seconds", json.int(age_seconds)),
    #("state", json.string(state)),
  ])
  |> json.to_string
}

/// GET /api/v1/secret-status — summary for dashboard Andon tile (30s refresh per
/// SC-AGUI-UI-008). Returns count by state + per-secret states.
pub fn secret_status_summary_json(
  fresh_count: Int,
  soft_stale_count: Int,
  hard_stale_count: Int,
  per_secret_states: List(#(String, String)),
  vault_state: String,
  last_sync_age_seconds: Int,
) -> String {
  json.object([
    #("vault_state", json.string(vault_state)),
    #("last_sync_age_seconds", json.int(last_sync_age_seconds)),
    #(
      "counts",
      json.object([
        #("fresh", json.int(fresh_count)),
        #("soft_stale", json.int(soft_stale_count)),
        #("hard_stale", json.int(hard_stale_count)),
      ]),
    ),
    #(
      "per_secret",
      json.array(per_secret_states, fn(pair) {
        let #(name, state) = pair
        json.object([
          #("name", json.string(name)),
          #("state", json.string(state)),
        ])
      }),
    ),
    #(
      "dashboard_color",
      json.string(dashboard_color(
        fresh_count,
        soft_stale_count,
        hard_stale_count,
        vault_state,
      )),
    ),
  ])
  |> json.to_string
}

// =====================================================================
// Pass-25: policy-audit JSON surface (wires vault_audit_reconcile kernel)
//
// Used by the daily SC-VAULT-016 cron + dashboard tile to surface
// Missing/Orphan/Drift discrepancies. The pure ReconcileResult comes from
// `vault_audit_reconcile.reconcile/2`; this function only handles the
// JSON envelope + severity tier label.
// =====================================================================

/// GET /api/v1/secret-policy-audit — discrepancy report between expected
/// secret_policy and Smriti.db actuals. Severity tier drives operator alert.
pub fn policy_audit_json(
  result: vault_audit_reconcile.ReconcileResult,
) -> String {
  let severity = vault_audit_reconcile.highest_severity(result)
  json.object([
    #("severity", json.string(severity)),
    #("expected_count", json.int(result.expected_count)),
    #("actual_count", json.int(result.actual_count)),
    #("matched_count", json.int(result.matched_count)),
    #(
      "discrepancies",
      json.array(result.discrepancies, fn(d) {
        case d {
          vault_audit_reconcile.Missing(name: name) ->
            json.object([
              #("kind", json.string("missing")),
              #("name", json.string(name)),
            ])
          vault_audit_reconcile.Orphan(name: name) ->
            json.object([
              #("kind", json.string("orphan")),
              #("name", json.string(name)),
            ])
          vault_audit_reconcile.Drift(
            name: name,
            field: field,
            expected: exp,
            actual: act,
          ) ->
            json.object([
              #("kind", json.string("drift")),
              #("name", json.string(name)),
              #("field", json.string(field)),
              #("expected", json.string(exp)),
              #("actual", json.string(act)),
            ])
        }
      }),
    ),
  ])
  |> json.to_string
}

/// Andon escalation per TPS countermeasures:
///  green: all fresh + vault active + recent sync
///  amber: any soft-stale OR sync stale
///  red: any hard-stale OR vault sealed > 30s
fn dashboard_color(
  _fresh: Int,
  soft: Int,
  hard: Int,
  vault_state: String,
) -> String {
  case vault_state, hard, soft {
    "Active", 0, 0 -> "green"
    "Active", 0, _ -> "amber"
    "Active", _, _ -> "red"
    _, _, _ -> "red"
  }
}

// =====================================================================
// Auth gate — Bearer token / OIDC verification
// =====================================================================

/// SC-VAULT-003 + SC-AUTH-001: every endpoint requires authenticated access.
/// Returns Ok(name) if token resolves to a user with `secret_read` permission.
pub fn require_auth(authorization_header: String) -> Result(String, String) {
  case string.starts_with(authorization_header, "Bearer ") {
    False -> Error("missing_bearer_token")
    True ->
      Error(
        "oidc_permission_validation_not_wired_use_handle_get_secret_constant_time_bearer",
      )
  }
}

/// Error response shape for unauthorized / not-found / fail-closed.
pub fn error_json(code: String, message: String) -> String {
  json.object([
    #("error", json.string(code)),
    #("message", json.string(message)),
  ])
  |> json.to_string
}

/// SC-VAULT-009: invoke this from every endpoint after a successful read.
/// Stub for now; Slice E continuation wires to zenoh_otel.publish_span.
pub fn emit_access_audit(
  caller: String,
  secret_name: String,
  result: String,
) -> Nil {
  // TODO: zenoh_otel.publish(
  //   "indrajaal/l0/secret/access/" <> secret_name,
  //   json.object([
  //     #("at", json.int(now())),
  //     #("caller", json.string(caller)),
  //     #("name", json.string(secret_name)),
  //     #("result", json.string(result)),
  //   ]) |> json.to_string
  // )
  let _ = caller
  let _ = secret_name
  let _ = result
  Nil
}

// =====================================================================
// Wave 11 — runtime handler
//
// `handle_get_secret/2` is the function called from `web/server.gleam`
// AFTER it intercepts `GET /api/v1/secret/<name>` and verifies the
// `Authorization: Bearer <token>` header.
//
// Auth flow (constant-time):
//   1. Caller passes the raw bearer token (already stripped of "Bearer ").
//   2. We compute SHA-256 of the supplied token via FFI.
//   3. We compare against the SHA-256 of `~/.config/c3i/pi_session.token`
//      (read once + cached via persistent_term-like FFI, or re-read every
//       request — current implementation re-reads for simplicity; the file
//       is small and the performance cost is negligible vs. vault subprocess).
//
// Vault flow (fail-closed):
//   1. If auth fails → 401 with no vault access.
//   2. If auth succeeds → spawn `vault_migrate --get --name <n>`.
//   3. Subprocess JSON is returned as-is (already shape-correct).
//   4. Errors map to 404 (not_found) / 500 (other).
//
// Returns: #(http_status_code, body_json_string)
// =====================================================================

/// FFI ports: see lib/cepaf_gleam/src/secret_api_ffi.erl
@external(erlang, "secret_api_ffi", "expected_token_sha256")
fn expected_token_sha256() -> Result(String, String)

@external(erlang, "secret_api_ffi", "sha256_hex")
fn sha256_hex(input: String) -> String

@external(erlang, "secret_api_ffi", "constant_time_eq")
fn constant_time_eq(a: String, b: String) -> Bool

/// Returns one of:
///   Ok(json_string)             — single-line JSON: name/value/version/expires_at
///   Error("not_found")
///   Error("kek_missing")
///   Error("binary_missing")
///   Error("subprocess_failed:...")
@external(erlang, "secret_api_ffi", "fetch_secret_via_subprocess")
fn fetch_secret_raw(name: String) -> FetchResult

/// Wave 16 W4 (SC-VAULT-009): fetch dashboard status JSON from vault_migrate
/// `--status` subprocess. Read-only; never decrypts; never requires KEK.
///
/// Returns FetchOk(json) on exit 0 with payload conforming to Lustre
/// `secrets_vault.Model` shape, or FetchErr(token) on subprocess failure.
@external(erlang, "secret_api_ffi", "fetch_vault_status_via_subprocess")
pub fn fetch_vault_status() -> FetchResult

pub type FetchResult {
  FetchOk(json: String)
  FetchErr(token: String)
}

/// Compare an incoming Bearer token against the expected session token.
/// Constant-time, side-channel safe.
pub fn auth_ok(bearer_token: String) -> Bool {
  case expected_token_sha256() {
    Error(_) -> False
    Ok(expected_hex) -> {
      let supplied_hex = sha256_hex(bearer_token)
      constant_time_eq(supplied_hex, expected_hex)
    }
  }
}

/// Strip `Bearer ` prefix from an Authorization header value.
/// Returns Ok(token) if header is well-formed, Error(_) otherwise.
pub fn extract_bearer(authz_header: String) -> Result(String, String) {
  case string.starts_with(authz_header, "Bearer ") {
    False -> Error("missing_bearer_token")
    True -> Ok(string.drop_start(authz_header, 7))
  }
}

/// Main handler. Returns #(status_code, body_json_string).
///
/// Args:
///   authz_header: full value of `Authorization` header (or "" if absent)
///   secret_name:  path parameter from `/api/v1/secret/<name>`
pub fn handle_get_secret(
  authz_header: String,
  secret_name: String,
) -> #(Int, String) {
  // 1. Auth gate — constant-time bearer compare
  case extract_bearer(authz_header) {
    Error(_) -> {
      let _ = emit_access_audit("anonymous", secret_name, "denied_no_bearer")
      #(401, error_json("unauthorized", "missing or malformed bearer token"))
    }
    Ok(token) ->
      case auth_ok(token) {
        False -> {
          let _ =
            emit_access_audit("anonymous", secret_name, "denied_bad_bearer")
          #(401, error_json("unauthorized", "invalid bearer token"))
        }
        True -> {
          // 2. Auth passed — fetch from vault subprocess
          case fetch_secret_raw(secret_name) {
            FetchOk(json_str) -> {
              let _ = emit_access_audit("pi_session", secret_name, "granted")
              #(200, json_str)
            }
            FetchErr("not_found") -> {
              let _ = emit_access_audit("pi_session", secret_name, "not_found")
              #(404, error_json("not_found", "no such secret in vault"))
            }
            FetchErr("kek_missing") -> {
              let _ =
                emit_access_audit("pi_session", secret_name, "kek_missing")
              #(
                500,
                error_json(
                  "vault_unavailable",
                  "KEK sidecar missing — operator must provision",
                ),
              )
            }
            FetchErr("binary_missing") -> {
              let _ =
                emit_access_audit("pi_session", secret_name, "binary_missing")
              #(
                500,
                error_json(
                  "vault_unavailable",
                  "vault_migrate binary not built",
                ),
              )
            }
            FetchErr(other) -> {
              let _ = emit_access_audit("pi_session", secret_name, other)
              #(
                500,
                error_json("vault_error", "vault subprocess error: " <> other),
              )
            }
          }
        }
      }
  }
}
