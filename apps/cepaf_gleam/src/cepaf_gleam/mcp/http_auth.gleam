//// Protected HTTP authentication. Tokens use hex(JSON).hex(HMAC-SHA256),
//// domain-separated as uos-mcp-http-v1. Authentication grants identity only.

import cepaf_gleam/harness/files
import cepaf_gleam/mcp/principal.{type Principal}
import cepaf_gleam/mcp/types.{
  type ToolError, ClientProfile, NonRetryable, ToolError,
}
import gleam/bit_array
import gleam/crypto
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/string

pub type AuthConfig {
  AuthConfig(
    approved_origins: List(String),
    expected_issuer: String,
    expected_audience: String,
    required_scope: String,
    signing_secret: String,
  )
}

pub type TokenClaims {
  TokenClaims(
    issuer: String,
    audience: String,
    actor_id: String,
    client_name: String,
    workspace_root: String,
    session_id: String,
    scopes: List(String),
    issued_at_ms: Int,
    expires_at_ms: Int,
  )
}

pub fn protected_resource_metadata(
  resource_url: String,
  auth_servers: List(String),
  scopes_supported: List(String),
) -> String {
  json.object([
    #("resource", json.string(resource_url)),
    #("authorization_servers", json.array(auth_servers, json.string)),
    #("scopes_supported", json.array(scopes_supported, json.string)),
    #("bearer_methods_supported", json.array(["header"], json.string)),
  ])
  |> json.to_string
}

/// Single-valued, case-insensitive headers. Duplicates fail closed.
pub fn header(
  headers: List(#(String, String)),
  name: String,
) -> Result(String, Nil) {
  case
    list.filter(headers, fn(h) {
      string.lowercase(h.0) == string.lowercase(name)
    })
  {
    [#(_, value)] -> Ok(value)
    _ -> Error(Nil)
  }
}

fn refused(code: String) -> ToolError {
  ToolError(code, "HTTP authentication refused", NonRetryable)
}

/// Explicit allowlist AND strict HTTPS Tailnet host syntax, including configured
/// origins. No paths, credentials, wildcard, IP literals or implicit docs origin.
pub fn approved_origin(config: AuthConfig, origin: String) -> Bool {
  let host_port = string.drop_start(origin, 8)
  let host_ok = case string.split(host_port, ":") {
    [host] -> tailnet_host(host)
    [host, port] -> {
      let valid_port = case gleam_int_parse(port) {
        Ok(n) -> n > 0 && n <= 65_535
        Error(_) -> False
      }
      tailnet_host(host) && valid_port
    }
    _ -> False
  }
  string.starts_with(origin, "https://")
  && host_ok
  && list.contains(config.approved_origins, origin)
}

fn gleam_int_parse(port: String) -> Result(Int, Nil) {
  case
    list.all(string.to_graphemes(port), fn(c) {
      string.contains("0123456789", c)
    })
    && port != ""
  {
    True -> int.parse(port)
    False -> Error(Nil)
  }
}

fn tailnet_host(host: String) -> Bool {
  case string.split(host, ".") {
    [label, "tail55d152", "ts", "net"] ->
      label != ""
      && string.byte_size(label) <= 63
      && !string.starts_with(label, "-")
      && !string.ends_with(label, "-")
      && list.all(string.to_graphemes(label), fn(c) {
        string.contains("abcdefghijklmnopqrstuvwxyz0123456789-", c)
      })
    _ -> False
  }
}

pub fn authenticate(
  config: AuthConfig,
  headers: List(#(String, String)),
  now_ms: Int,
) -> Result(Principal, ToolError) {
  use origin <- result.try(
    header(headers, "origin")
    |> result.map_error(fn(_) { refused("HTTP_ORIGIN_FORBIDDEN") }),
  )
  use _ <- result.try(case approved_origin(config, origin) {
    True -> Ok(Nil)
    False -> Error(refused("HTTP_ORIGIN_FORBIDDEN"))
  })
  use authorization <- result.try(
    header(headers, "authorization")
    |> result.map_error(fn(_) { refused("HTTP_UNAUTHORIZED") }),
  )
  use claims <- result.try(verify_token(config, authorization, now_ms))
  Ok(principal.from_http_auth_middleware(
    actor: claims.actor_id,
    client: ClientProfile(claims.client_name),
    workspace_root: claims.workspace_root,
    session_id: claims.session_id,
  ))
}

/// Require an additional scope from the same fully verified bearer token.
pub fn token_has_scope(
  config: AuthConfig,
  headers: List(#(String, String)),
  scope: String,
  now_ms: Int,
) -> Bool {
  case header(headers, "authorization") {
    Error(_) -> False
    Ok(authorization) ->
      case verify_token(config, authorization, now_ms) {
        Ok(claims) -> scope != "" && list.contains(claims.scopes, scope)
        Error(_) -> False
      }
  }
}

/// Trusted issuer helper; not an OAuth issuance endpoint. Never expose the
/// signing secret or this function through a tool dispatcher.
pub fn sign_token(claims: TokenClaims, signing_secret: String) -> String {
  let payload =
    json.object([
      #("issuer", json.string(claims.issuer)),
      #("audience", json.string(claims.audience)),
      #("actor_id", json.string(claims.actor_id)),
      #("client_name", json.string(claims.client_name)),
      #("workspace_root", json.string(claims.workspace_root)),
      #("session_id", json.string(claims.session_id)),
      #("scopes", json.array(claims.scopes, json.string)),
      #("issued_at_ms", json.int(claims.issued_at_ms)),
      #("expires_at_ms", json.int(claims.expires_at_ms)),
    ])
    |> json.to_string
    |> bit_array.from_string
    |> bit_array.base16_encode
  payload <> "." <> signature(payload, signing_secret)
}

fn signature(payload: String, secret: String) -> String {
  crypto.hmac(
    bit_array.from_string("uos-mcp-http-v1:" <> payload),
    crypto.Sha256,
    bit_array.from_string(secret),
  )
  |> bit_array.base16_encode
}

fn claims_decoder() -> decode.Decoder(TokenClaims) {
  use issuer <- decode.field("issuer", decode.string)
  use audience <- decode.field("audience", decode.string)
  use actor <- decode.field("actor_id", decode.string)
  use client <- decode.field("client_name", decode.string)
  use root <- decode.field("workspace_root", decode.string)
  use session <- decode.field("session_id", decode.string)
  use scopes <- decode.field("scopes", decode.list(decode.string))
  use issued <- decode.field("issued_at_ms", decode.int)
  use expires <- decode.field("expires_at_ms", decode.int)
  decode.success(TokenClaims(
    issuer,
    audience,
    actor,
    client,
    root,
    session,
    scopes,
    issued,
    expires,
  ))
}

fn verify_token(
  config: AuthConfig,
  authorization: String,
  now_ms: Int,
) -> Result(TokenClaims, ToolError) {
  let error = refused("HTTP_UNAUTHORIZED")
  use token <- result.try(case string.split(authorization, " ") {
    ["Bearer", token] if token != "" -> Ok(token)
    _ -> Error(error)
  })
  use _ <- result.try(
    case string.byte_size(token) <= 32_768 && config.signing_secret != "" {
      True -> Ok(Nil)
      False -> Error(error)
    },
  )
  use parts <- result.try(case string.split(token, ".") {
    [payload, sig] -> Ok(#(payload, sig))
    _ -> Error(error)
  })
  // Compare fixed-size digests in constant time, using the harness SHA-256
  // primitive. HMAC (rather than secret-prefix SHA) prevents length extension.
  let verified =
    crypto.secure_compare(
      bit_array.from_string(files.digest(parts.1)),
      bit_array.from_string(
        files.digest(signature(parts.0, config.signing_secret)),
      ),
    )
  use _ <- result.try(case verified {
    True -> Ok(Nil)
    False -> Error(error)
  })
  use bytes <- result.try(
    bit_array.base16_decode(parts.0) |> result.map_error(fn(_) { error }),
  )
  use payload <- result.try(
    bit_array.to_string(bytes) |> result.map_error(fn(_) { error }),
  )
  use claims <- result.try(
    json.parse(payload, claims_decoder()) |> result.map_error(fn(_) { error }),
  )
  case
    claims.issuer == config.expected_issuer
    && claims.audience == config.expected_audience
    && config.required_scope != ""
    && list.contains(claims.scopes, config.required_scope)
    && claims.issued_at_ms <= now_ms
    && claims.expires_at_ms > now_ms
    && claims.issued_at_ms >= 0
    && claims.expires_at_ms > claims.issued_at_ms
    && claims.actor_id != ""
    && claims.client_name != ""
    && claims.workspace_root != ""
    && claims.session_id != ""
  {
    True -> Ok(claims)
    False -> Error(error)
  }
}
