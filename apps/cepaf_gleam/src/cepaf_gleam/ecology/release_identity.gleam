//// Bounded authenticated ingress identity, never release permission.
//// Configuration/JWKS must come from an independently trusted provider, not
//// request data. No default issuer, key, role, MFA claim or identity exists.
//// Identity carries no bearer token; positive authentication cannot actuate.

import cepaf_gleam/auth/oidc
import cepaf_gleam/harness/files
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string

const maximum_time = 9_000_000_000_000_000

pub opaque type Configuration {
  Configuration(
    oidc: oidc.OidcConfig,
    required_role: String,
    accepted_acr: List(String),
    keys_loaded_ms: Int,
    keys_expires_ms: Int,
    lifetime_ms: Int,
    digest: String,
  )
}

pub opaque type Identity {
  Identity(
    subject: String,
    configuration_digest: String,
    host: String,
    boot: String,
    clock_domain: String,
    observed_utc_ms: Int,
    observed_mono_ms: Int,
    expires_utc_ms: Int,
    expires_mono_ms: Int,
  )
}

fn bounded(value: String, maximum: Int) -> Bool {
  string.byte_size(value) > 0
  && string.byte_size(value) <= maximum
  && !string.contains(value, "\u{0000}")
}

/// Require an explicit HTTPS Tailnet issuer. This lexical check is not issuer
/// ownership, TLS verification, JWKS provenance or deployment admission.
pub fn tailnet_issuer(value: String) -> Bool {
  case string.split(value, "/") {
    ["https:", "", authority, ..] -> {
      let host_and_port = string.split(authority, ":")
      let host = list.first(host_and_port) |> result.unwrap("")
      let hostname_valid = case string.split(host, ".") {
        [label, "tail55d152", "ts", "net"] ->
          bounded(label, 63)
          && !string.starts_with(label, "-")
          && !string.ends_with(label, "-")
        _ -> False
      }
      let port_valid = case host_and_port {
        [_] -> True
        [_, port] ->
          case int.parse(port) {
            Ok(n) -> n >= 1 && n <= 65_535 && int.to_string(n) == port
            Error(_) -> False
          }
        _ -> False
      }
      bounded(value, 512)
      && port_valid
      && hostname_valid
      && list.all(string.to_utf_codepoints(value), fn(c) {
        let n = string.utf_codepoint_to_int(c)
        n > 32 && n != 127 && n != 92
      })
      && string.ends_with(host, ".tail55d152.ts.net")
      && list.all(string.to_utf_codepoints(host), fn(c) {
        let n = string.utf_codepoint_to_int(c)
        { n >= 97 && n <= 122 } || { n >= 48 && n <= 57 } || n == 45 || n == 46
      })
      && !string.contains(value, "#")
      && !string.contains(value, "?")
    }
    _ -> False
  }
}

pub fn configure(
  issuer: String,
  audience: String,
  jwks: String,
  keys_loaded_ms: Int,
  keys_lifetime_ms: Int,
  required_role: String,
  accepted_acr: List(String),
  identity_lifetime_ms: Int,
) -> Result(Configuration, String) {
  use _ <- result.try(
    case
      tailnet_issuer(issuer)
      && bounded(audience, 128)
      && bounded(required_role, 128)
      && list.length(list.take(accepted_acr, 17)) <= 16
      && accepted_acr != []
      && list.all(accepted_acr, fn(x) { bounded(x, 128) })
      && keys_loaded_ms >= 0
      && keys_loaded_ms <= maximum_time - 300_000
      && keys_lifetime_ms >= 1000
      && keys_lifetime_ms <= 300_000
      && keys_lifetime_ms % 1000 == 0
      && keys_loaded_ms % 1000 == 0
      && identity_lifetime_ms > 0
      && identity_lifetime_ms <= 30_000
    {
      True -> Ok(Nil)
      False -> Error("RELEASE_IDENTITY_CONFIGURATION_INVALID")
    },
  )
  let empty =
    oidc.OidcConfig(
      issuer_url: issuer,
      jwks_url: issuer <> "/protocol/openid-connect/certs",
      client_id: audience,
      required_audience: audience,
      jwks_snapshot: None,
    )
  use configured <- result.try(
    oidc.load_jwks_snapshot(
      empty,
      jwks,
      keys_loaded_ms / 1000,
      keys_lifetime_ms / 1000,
    )
    |> result.map_error(fn(_) { "RELEASE_IDENTITY_KEYS_INVALID" }),
  )
  let digest =
    json.object([
      #("domain", json.string("uos.ecology.release.identity.v1")),
      #("issuer", json.string(issuer)),
      #("audience", json.string(audience)),
      #("jwks", json.string(jwks)),
      #("loaded_ms", json.int(keys_loaded_ms)),
      #("keys_lifetime_ms", json.int(keys_lifetime_ms)),
      #("role", json.string(required_role)),
      #("acr", json.array(accepted_acr, json.string)),
      #("identity_lifetime_ms", json.int(identity_lifetime_ms)),
    ])
    |> json.to_string
    |> files.digest
  Ok(Configuration(
    configured,
    required_role,
    accepted_acr,
    keys_loaded_ms,
    keys_loaded_ms + keys_lifetime_ms,
    identity_lifetime_ms,
    digest,
  ))
}

pub fn authenticate(
  configuration: Configuration,
  token: String,
  host: String,
  boot: String,
  clock_domain: String,
  now_utc_ms: Int,
  now_mono_ms: Int,
) -> Result(Identity, String) {
  use _ <- result.try(
    case
      bounded(token, 8192)
      && bounded(host, 128)
      && bounded(boot, 128)
      && bounded(clock_domain, 128)
      && now_utc_ms >= configuration.keys_loaded_ms
      && now_utc_ms < configuration.keys_expires_ms
      && now_mono_ms >= 0 - maximum_time
      && now_mono_ms <= maximum_time - 30_000
    {
      True -> Ok(Nil)
      False -> Error("RELEASE_IDENTITY_CONTEXT_INVALID")
    },
  )
  use claims <- result.try(
    oidc.validate_token(token, configuration.oidc, now_utc_ms / 1000)
    |> result.map_error(fn(_) { "RELEASE_IDENTITY_AUTHENTICATION_REFUSED" }),
  )
  // Do not use substring-based MFA classification or OIDC skew as effect TTL.
  use _ <- result.try(
    case
      bounded(claims.sub, 128)
      && list.contains(claims.roles, configuration.required_role)
      && list.contains(configuration.accepted_acr, claims.acr)
      && claims.exp > 0
      && claims.exp <= maximum_time / 1000
      && now_utc_ms < claims.exp * 1000
      && case claims.iat {
        Some(iat) -> iat >= 0 && iat * 1000 <= now_utc_ms
        None -> False
      }
      && case claims.nbf {
        Some(nbf) -> nbf >= 0 && nbf * 1000 <= now_utc_ms
        None -> False
      }
    {
      True -> Ok(Nil)
      False -> Error("RELEASE_IDENTITY_ROLE_OR_TIME_REFUSED")
    },
  )
  let deadline =
    int.min(
      now_utc_ms + configuration.lifetime_ms,
      int.min(claims.exp * 1000, configuration.keys_expires_ms),
    )
  Ok(Identity(
    claims.sub,
    configuration.digest,
    host,
    boot,
    clock_domain,
    now_utc_ms,
    now_mono_ms,
    deadline,
    now_mono_ms + deadline - now_utc_ms,
  ))
}

pub fn subject(identity: Identity) -> String {
  identity.subject
}

pub fn expires_utc_ms(identity: Identity) -> Int {
  identity.expires_utc_ms
}

pub fn expires_mono_ms(identity: Identity) -> Int {
  identity.expires_mono_ms
}

pub fn configuration_digest(configuration: Configuration) -> String {
  configuration.digest
}

pub fn still_valid(
  configuration: Configuration,
  identity: Identity,
  host: String,
  boot: String,
  clock_domain: String,
  now_utc_ms: Int,
  now_mono_ms: Int,
) -> Bool {
  identity.configuration_digest == configuration.digest
  && identity.host == host
  && identity.boot == boot
  && identity.clock_domain == clock_domain
  && now_utc_ms >= identity.observed_utc_ms
  && now_utc_ms < identity.expires_utc_ms
  && now_utc_ms >= configuration.keys_loaded_ms
  && now_utc_ms < configuration.keys_expires_ms
  && now_mono_ms >= identity.observed_mono_ms
  && now_mono_ms < identity.expires_mono_ms
}
