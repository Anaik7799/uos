//// Authenticated Mini App read boundary. Policy and identity remain in Gleam.
//// No backend callback runs before bounded signature, freshness and allowlist checks.

import cepaf_gleam/telegram/auth
import cepaf_gleam/telegram/types
import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
import gleam/string
import gleam/uri

pub const max_body_bytes = 8192

pub const data_path = "/mini-app/api/data"

pub type AllowedIdentity {
  // A chat restriction requires a signed initData chat.id. None is explicit
  // user-scoped read access; no unsigned SDK identity is accepted.
  AllowedIdentity(user_id: Int, chat_id: Option(Int))
}

pub opaque type Configuration {
  Configuration(token: String, allowed: List(AllowedIdentity), max_age: Int)
}

pub opaque type AuthorizedRead {
  AuthorizedRead(
    page: types.MiniAppPage,
    user_id: Int,
    chat_id: Option(Int),
    topic: Option(String),
  )
}

pub type Observation {
  Observed(at_unix: Int, source: String, fields: Dict(String, String))
  Unavailable(reason: String)
  Forbidden
}

pub type ApiError {
  InvalidRequest
  Unauthorized
  ConfigurationUnavailable
  BackendUnavailable
}

pub fn configuration(
  token: String,
  allowed: List(AllowedIdentity),
  max_age: Int,
) -> Result(Configuration, ApiError) {
  case
    string.byte_size(token) > 0
    && string.byte_size(token) <= auth.max_token_bytes
    && !string.contains(token, "\u{0}")
    && max_age > 0
    && max_age <= 300
    && allowed != []
    && list.length(allowed) <= 256
    && list.all(allowed, fn(a) {
      a.user_id > 0
      && a.user_id <= auth.max_safe_integer
      && case a.chat_id {
        None -> True
        Some(id) ->
          id != 0 && id >= -auth.max_safe_integer && id <= auth.max_safe_integer
      }
    })
  {
    True -> Ok(Configuration(token, allowed, max_age))
    False -> Error(ConfigurationUnavailable)
  }
}

pub fn all_pages() -> List(types.MiniAppPage) {
  [
    types.MiniDashboard,
    types.MiniHealthGrid,
    types.MiniCockpit,
    types.MiniImmune,
    types.MiniPlanning,
    types.MiniInference,
    types.MiniConversation,
    types.MiniConfig,
    types.MiniPodman,
    types.MiniFederation,
    types.MiniVerification,
    types.MiniFmea,
    types.MiniTelemetry,
    types.MiniZenohBrowser,
  ]
}

pub fn parse_page(path: String) -> Result(types.MiniAppPage, Nil) {
  case path {
    "/mini-app" | "/mini-app/" -> Ok(types.MiniDashboard)
    _ -> list.find(all_pages(), fn(page) { types.page_to_path(page) == path })
  }
}

pub fn owns_path(path: String) -> Bool {
  path == "/mini-app" || string.starts_with(path, "/mini-app/")
}

pub fn page(read: AuthorizedRead) -> types.MiniAppPage {
  read.page
}

pub fn user_id(read: AuthorizedRead) -> Int {
  read.user_id
}

pub fn chat_id(read: AuthorizedRead) -> Option(Int) {
  read.chat_id
}

pub fn selected_topic(read: AuthorizedRead) -> Option(String) {
  read.topic
}

fn signed_chat(init_data: String) -> Result(Option(Int), ApiError) {
  // validate_fresh already rejects malformed encodings and duplicate decoded keys.
  use params <- result.try(
    uri.parse_query(init_data) |> result.replace_error(InvalidRequest),
  )
  case list.key_find(params, "chat") {
    Error(_) -> Ok(None)
    Ok(raw) -> {
      let decoder = {
        use id <- decode.field("id", decode.int)
        decode.success(id)
      }
      use id <- result.try(
        json.parse(raw, decoder) |> result.replace_error(InvalidRequest),
      )
      case
        id != 0 && id >= -auth.max_safe_integer && id <= auth.max_safe_integer
      {
        True -> Ok(Some(id))
        False -> Error(InvalidRequest)
      }
    }
  }
}

pub fn authorize(
  body: String,
  config: Configuration,
  now_unix: Int,
) -> Result(AuthorizedRead, ApiError) {
  use _ <- result.try(case string.byte_size(body) <= max_body_bytes {
    True -> Ok(Nil)
    False -> Error(InvalidRequest)
  })
  let decoder = {
    use init_data <- decode.field("init_data", decode.string)
    use path <- decode.field("path", decode.string)
    use topic <- decode.optional_field(
      "topic",
      None,
      decode.optional(decode.string),
    )
    decode.success(#(init_data, path, topic))
  }
  use #(init_data, path, topic) <- result.try(
    json.parse(body, decoder) |> result.replace_error(InvalidRequest),
  )
  use selected_page <- result.try(
    parse_page(path) |> result.replace_error(InvalidRequest),
  )
  use _ <- result.try(case topic {
    None -> Ok(Nil)
    Some(key) ->
      case
        selected_page == types.MiniZenohBrowser && string.byte_size(key) <= 512
      {
        True -> Ok(Nil)
        False -> Error(InvalidRequest)
      }
  })
  use user <- result.try(
    case
      auth.validate_fresh(init_data, config.token, now_unix, config.max_age)
    {
      auth.Authenticated(user) -> Ok(user)
      auth.InvalidHash | auth.ExpiredData | auth.MalformedData(_) ->
        Error(Unauthorized)
    },
  )
  use signed_chat_id <- result.try(signed_chat(init_data))
  case
    list.any(config.allowed, fn(allowed) {
      allowed.user_id == user.id
      && case allowed.chat_id {
        None -> True
        Some(expected) -> signed_chat_id == Some(expected)
      }
    })
  {
    True -> Ok(AuthorizedRead(selected_page, user.id, signed_chat_id, topic))
    False -> Error(Unauthorized)
  }
}

fn json_response(status: Int, body: json.Json) -> response.Response(String) {
  response.new(status)
  |> response.set_body(json.to_string(body))
  |> response.set_header("content-type", "application/json; charset=utf-8")
  |> response.set_header("cache-control", "no-store")
  |> response.set_header("x-content-type-options", "nosniff")
  |> response.set_header("referrer-policy", "no-referrer")
}

fn error_response(status: Int, code: String) -> response.Response(String) {
  json_response(status, json.object([#("error", json.string(code))]))
}

fn detail_field(key: String) -> Bool {
  string.starts_with(key, "Message part ")
  || string.starts_with(key, "Available topic ")
  || string.starts_with(key, "Exchange ")
  || string.starts_with(key, "Assessment ")
  || string.starts_with(key, "CHK-")
  || { string.starts_with(key, "Container ") && key != "Container count" }
  || { string.starts_with(key, "Image ") && key != "Image references" }
}

fn render_observation_inner(
  read: AuthorizedRead,
  observation: Observation,
  now: Int,
) -> response.Response(String) {
  let #(status, at, source, fields) = case observation {
    Unavailable(_) -> #("unavailable", json.null(), "", dict.new())
    Forbidden -> #("forbidden", json.null(), "", dict.new())
    Observed(at, source, fields) ->
      case at > 0 && at <= now && now - at <= 30 {
        True -> #("observed", json.int(at), source, fields)
        False -> #("stale", json.int(at), source, dict.new())
      }
  }
  let bounded =
    dict.size(fields) <= 100
    && string.byte_size(source) <= 128
    && list.all(dict.to_list(fields), fn(field) {
      string.byte_size(field.0) <= 128 && string.byte_size(field.1) <= 2048
    })
  case bounded {
    False -> error_response(503, "observation_exceeds_bound")
    True ->
      json_response(
        200,
        json.object([
          #("path", json.string(types.page_to_path(read.page))),
          #("status", json.string(status)),
          #("reason_code", json.string(reason_code_of(observation))),
          #("observed_at", at),
          #("source", json.string(source)),
          #(
            "fields",
            json.object(
              dict.to_list(fields)
              |> list.sort(fn(a, b) {
                case detail_field(a.0), detail_field(b.0) {
                  True, False -> order.Gt
                  False, True -> order.Lt
                  _, _ -> string.compare(a.0, b.0)
                }
              })
              |> list.map(fn(pair) { #(pair.0, json.string(pair.1)) }),
            ),
          ),
        ]),
      )
  }
}

fn render_observation(
  read: AuthorizedRead,
  observation: Observation,
  now: Int,
) -> response.Response(String) {
  case observation {
    Forbidden -> error_response(403, "topic_access_denied")
    Unavailable(_) if read.page == types.MiniTelemetry -> {
      let rendered = render_observation_inner(read, observation, now)
      response.Response(..rendered, status: 503)
    }
    _ -> render_observation_inner(read, observation, now)
  }
}

pub fn handle_data(
  req: request.Request(String),
  config: Result(Configuration, ApiError),
  clock: fn() -> Int,
  observe: fn(AuthorizedRead) -> Observation,
) -> response.Response(String) {
  case req.path != data_path {
    True -> error_response(404, "not_found")
    False ->
      case req.method {
        http.Post -> {
          let content_type_ok = case request.get_header(req, "content-type") {
            Ok(value) ->
              string.split(value, ";")
              |> list.first()
              |> result.map(string.trim)
              |> result.map(string.lowercase)
              == Ok("application/json")
            Error(_) -> False
          }
          case content_type_ok {
            False -> error_response(415, "json_required")
            True ->
              case config {
                Error(_) -> error_response(503, "mini_app_not_configured")
                Ok(config) -> {
                  let started_at = clock()
                  case authorize(req.body, config, started_at) {
                    Error(InvalidRequest) ->
                      error_response(400, "invalid_request")
                    Error(Unauthorized) -> error_response(401, "unauthorized")
                    Error(ConfigurationUnavailable)
                    | Error(BackendUnavailable) ->
                      error_response(503, "unavailable")
                    Ok(read) -> {
                      let observed = observe(read)
                      let after_observation = clock()
                      case
                        after_observation >= started_at
                        && after_observation - started_at <= 5
                      {
                        False ->
                          error_response(503, "observation_clock_or_deadline")
                        True ->
                          case authorize(req.body, config, after_observation) {
                            Ok(current) ->
                              render_observation(
                                current,
                                observed,
                                after_observation,
                              )
                            Error(_) ->
                              error_response(
                                401,
                                "authorization_expired_during_observation",
                              )
                          }
                      }
                    }
                  }
                }
              }
          }
        }
        http.Options ->
          response.new(204)
          |> response.set_body("")
          |> response.set_header("allow", "POST, OPTIONS")
          |> response.set_header("cache-control", "no-store")
        _ ->
          error_response(405, "method_not_allowed")
          |> response.set_header("allow", "POST, OPTIONS")
      }
  }
}

/// Closed set of unavailability reasons a client may see (review A-01, wave
/// 6l). An observer reason outside this list renders as
/// `unavailable_unspecified`; the raw string never reaches a response, so a
/// backend error text cannot leak, while a typed absence such as
/// `immune_actor_not_running` is distinguishable from an outage.
pub const unavailability_reasons = [
  "immune_actor_not_running", "immune_observer_timeout", "telemetry_unavailable",
  "zenoh_configuration_unavailable", "verification_observation_failed",
  "task_observation_failed", "podman_observation_failed",
  "mesh_configuration_invalid", "history_observation_failed",
  "health_observation_failed", "fmea_observation_failed",
  "dashboard_sources_unavailable", "dashboard_deadline_or_clock_refused",
  "alerts_deadline_or_clock_refused", "alert_review_projection_bound",
  "alert_owner_observation_unavailable", "inference_not_configured",
  "federation_not_configured", "observer_deadline_exceeded",
  "backend_exception", "zenoh_observation_clock_refused", "zenoh_query_failed",
  "zenoh_observation_field_bound",
]

pub fn reason_code(reason: String) -> String {
  case list.contains(unavailability_reasons, reason) {
    True -> reason
    False -> "unavailable_unspecified"
  }
}

fn reason_code_of(observation: Observation) -> String {
  case observation {
    Unavailable(reason) -> reason_code(reason)
    _ -> "none"
  }
}
