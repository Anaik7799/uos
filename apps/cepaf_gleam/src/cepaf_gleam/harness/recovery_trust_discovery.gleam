//// Bounded factual discovery, NOT an issuer, key store, roster or permission.
//// Key/custody identifiers are PRIVATE metadata. Production has no protected
//// provider binding; observe() truthfully returns UNKNOWN without any I/O.
//// The private native provider and paired IPC are exercised only by the ordinary
//// development fixture. No caller JSON/path/env can configure a production DB.

import cepaf_gleam/harness/telegram_store_transport as transport
import cepaf_gleam/mcp/principal.{type Principal}
import cepaf_gleam/mcp/resources
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub const resource_uri = "uos://governance/recovery-trust-discovery"

pub type KeyMetadata {
  KeyMetadata(
    kid: String,
    algorithm: String,
    custody_reference: String,
    state: String,
  )
}

pub opaque type Report {
  Unknown(reason: String)
  Observed(
    realm_id: String,
    issuer: String,
    observed_ms: Int,
    sqlite_version: String,
    keys: List(KeyMetadata),
  )
}

type Value {
  JsonObject(List(#(String, Value)))
  JsonArray(List(Value))
  JsonString(String)
  JsonInt(Int)
  JsonFloat(Float)
  JsonBool(Bool)
  JsonNull
}

@external(erlang, "telegram_store_codec_ffi", "parse_strict")
fn parse_strict(raw: String) -> Result(Value, String)

@external(erlang, "telegram_store_transport_ffi", "request_config_with_cleanup")
fn exchange(
  config: transport.LocalConfiguration,
  body: String,
) -> #(Result(String, String), Option(#(Int, Int)))

fn exact_fields(
  v: Value,
  names: List(String),
) -> Result(List(#(String, Value)), Nil) {
  case v {
    JsonObject(fields) -> {
      case
        list.length(fields) == list.length(names)
        && list.sort(list.map(fields, fn(f) { f.0 }), string.compare)
        == list.sort(names, string.compare)
      {
        True -> Ok(fields)
        False -> Error(Nil)
      }
    }
    JsonFloat(_) -> Error(Nil)
    _ -> Error(Nil)
  }
}

fn field(fs: List(#(String, Value)), name: String) -> Value {
  list.find(fs, fn(f) { f.0 == name })
  |> result.map(fn(f) { f.1 })
  |> result.unwrap(JsonNull)
}

fn text(
  fs: List(#(String, Value)),
  name: String,
  maximum: Int,
) -> Result(String, Nil) {
  case field(fs, name) {
    JsonString(s) ->
      case string.byte_size(s) > 0 && string.byte_size(s) <= maximum {
        True -> Ok(s)
        False -> Error(Nil)
      }
    _ -> Error(Nil)
  }
}

fn id(s: String) -> Bool {
  string.byte_size(s) > 0
  && string.byte_size(s) <= 128
  && list.all(string.to_graphemes(s), fn(c) {
    string.contains(
      "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.",
      c,
    )
  })
}

fn key(v: Value) -> Result(KeyMetadata, Nil) {
  use fs <- result.try(
    exact_fields(v, ["kid", "algorithm", "custody_reference", "state"]),
  )
  use kid <- result.try(text(fs, "kid", 128))
  use alg <- result.try(text(fs, "algorithm", 8))
  use reference <- result.try(text(fs, "custody_reference", 256))
  use state <- result.try(text(fs, "state", 8))
  case
    id(kid)
    && list.contains(["EdDSA", "ES256", "RS256"], alg)
    && reference == "iam/signing/" <> string.lowercase(alg) <> "/" <> kid
    && list.contains(["current", "rotating"], state)
  {
    True -> Ok(KeyMetadata(kid, alg, reference, state))
    False -> Error(Nil)
  }
}

fn decode(raw: String) -> Result(Report, Nil) {
  use _ <- result.try(
    case string.byte_size(raw) > 0 && string.byte_size(raw) <= 16_384 {
      True -> Ok(Nil)
      False -> Error(Nil)
    },
  )
  use v <- result.try(parse_strict(raw) |> result.map_error(fn(_) { Nil }))
  use fs <- result.try(
    exact_fields(v, [
      "schema_version",
      "source_schema",
      "authority",
      "trusted_roster",
      "purpose_binding",
      "custody_verified",
      "status",
      "reason",
      "realm_id",
      "issuer",
      "observed_at_ms",
      "sqlite_version",
      "keys",
    ]),
  )
  use _ <- result.try(
    case
      field(fs, "schema_version") == JsonInt(1)
      && field(fs, "source_schema") == JsonString("ferriskey.sqlite.v1")
      && field(fs, "authority") == JsonString("NONE")
      && field(fs, "trusted_roster") == JsonBool(False)
      && field(fs, "purpose_binding") == JsonString("UNKNOWN")
      && field(fs, "custody_verified") == JsonBool(False)
    {
      True -> Ok(Nil)
      False -> Error(Nil)
    },
  )
  case field(fs, "status") {
    JsonString("UNKNOWN") -> {
      use reason <- result.try(text(fs, "reason", 32))
      case
        list.contains(
          [
            "PROVIDER_UNCONFIGURED",
            "LOCATOR_UNAVAILABLE",
            "LOCATOR_CHANGED",
            "LAUNCHER_BINDING_INVALID",
            "STORE_UNAVAILABLE",
            "METADATA_INVALID",
            "METADATA_BOUND",
            "METADATA_ABSENT",
            "SCHEMA_UNSUPPORTED",
            "CUSTODY_REFERENCE_UNKNOWN",
            "REQUEST_REFUSED",
          ],
          reason,
        )
        && field(fs, "keys") == JsonArray([])
        && field(fs, "realm_id") == JsonNull
        && field(fs, "issuer") == JsonNull
        && field(fs, "observed_at_ms") == JsonNull
        && field(fs, "sqlite_version") == JsonNull
      {
        True -> Ok(Unknown(reason))
        False -> Error(Nil)
      }
    }
    JsonString("OBSERVED_METADATA_ONLY") -> {
      use realm <- result.try(text(fs, "realm_id", 128))
      use issuer <- result.try(text(fs, "issuer", 512))
      use version <- result.try(text(fs, "sqlite_version", 32))
      use observed <- result.try(case field(fs, "observed_at_ms") {
        JsonInt(ms) if ms > 0 && ms < 9_000_000_000_000_000 -> Ok(ms)
        _ -> Error(Nil)
      })
      use keys <- result.try(case field(fs, "keys") {
        JsonArray(vs) ->
          case vs != [] && list.length(vs) <= 16 {
            True -> list.try_map(vs, key)
            False -> Error(Nil)
          }
        _ -> Error(Nil)
      })
      case
        id(realm)
        && string.starts_with(issuer, "https://")
        && field(fs, "reason") == JsonNull
      {
        True -> Ok(Observed(realm, issuer, observed, version, keys))
        False -> Error(Nil)
      }
    }
    _ -> Error(Nil)
  }
}

// Only a genuine paired cleanup witness permits returning native facts. No
// public exchange injection, reset or trusted-provider constructor exists.
fn observe_bound(config: transport.LocalConfiguration) -> Report {
  case
    exchange(
      config,
      "{\"operation\":\"observe_metadata\",\"schema_version\":1}",
    )
  {
    #(Ok(raw), Some(#(0, at))) if at > 0 ->
      decode(raw) |> result.unwrap(Unknown("PROVIDER_RESPONSE_UNKNOWN"))
    _ -> Unknown("PROVIDER_OUTCOME_UNKNOWN")
  }
}

fn launcher_provider() -> Option(transport.LocalConfiguration) {
  None
}

/// No production provider, locator, roster or key custody has been admitted.
pub fn observe() -> Report {
  case launcher_provider() {
    None -> Unknown("PROVIDER_UNCONFIGURED")
    Some(config) -> observe_bound(config)
  }
}

pub fn to_json(report: Report) -> String {
  let facts = case report {
    Unknown(reason) -> [
      #("status", json.string("UNKNOWN")),
      #("reason", json.string(reason)),
      #("realm_id", json.null()),
      #("issuer", json.null()),
      #("observed_at_ms", json.null()),
      #("sqlite_version", json.null()),
      #("keys", json.array([], fn(x) { x })),
    ]
    Observed(realm, issuer, at, version, keys) -> [
      #("status", json.string("OBSERVED_METADATA_ONLY")),
      #("reason", json.null()),
      #("realm_id", json.string(realm)),
      #("issuer", json.string(issuer)),
      #("observed_at_ms", json.int(at)),
      #("sqlite_version", json.string(version)),
      #(
        "keys",
        json.array(keys, fn(k) {
          json.object([
            #("kid", json.string(k.kid)),
            #("algorithm", json.string(k.algorithm)),
            #("custody_reference", json.string(k.custody_reference)),
            #("state", json.string(k.state)),
          ])
        }),
      ),
    ]
  }
  json.object([
    #("schema_version", json.int(1)),
    #("authority", json.string("NONE")),
    #("trusted_roster", json.bool(False)),
    #("custody_verified", json.bool(False)),
    #("purpose_binding", json.string("UNKNOWN")),
    #("source_schema", json.string("ferriskey.sqlite.v1")),
    #(
      "clock_basis",
      json.string("NATIVE_WALL_CLOCK_OBSERVATION_NOT_SYNC_PROOF"),
    ),
    ..facts
  ])
  |> json.to_string
}

/// Principal-private registration value, not activation of the live registry.
pub fn resource(report: Report, p: Principal) -> resources.ResourceEntry {
  resources.ResourceEntry(
    resource_uri,
    "Recovery trust metadata — not authority",
    "application/json",
    resources.PrivatePrincipalResource,
    principal.actor_id(p),
    principal.workspace_root(p),
    to_json(report),
  )
}
