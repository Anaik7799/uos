//// T18 bounded Streamable HTTP adapter. The host supplies the session profile,
//// clock and dispatch closure; this module never creates effect authority.

import cepaf_gleam/harness/value
import cepaf_gleam/mcp/http_auth as auth
import cepaf_gleam/mcp/principal.{type Principal}
import cepaf_gleam/mcp/types.{
  type Outcome, type ProtocolProfile, Legacy20241105, Modern20260728,
}
import cepaf_gleam/mcp/wire
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string

pub type HttpRequest {
  HttpRequest(
    method: String,
    path: String,
    headers: List(#(String, String)),
    body: String,
  )
}

pub type HttpResponse {
  HttpResponse(status: Int, headers: List(#(String, String)), body: String)
}

pub const max_body_bytes = 1_048_576

pub const metadata_path = "/.well-known/oauth-protected-resource"

fn response(status: Int, code: String) -> HttpResponse {
  HttpResponse(
    status,
    [#("Content-Type", "application/json"), #("Cache-Control", "no-store")],
    json.object([#("error", json.string(code))]) |> json.to_string,
  )
}

pub fn handle(
  request: HttpRequest,
  config: auth.AuthConfig,
  profile: ProtocolProfile,
  now_ms: Int,
  resource_url: String,
  auth_servers: List(String),
  dispatch: fn(Principal, List(#(String, String)), wire.NormalizedMessage) ->
    Outcome,
) -> HttpResponse {
  case request.method, request.path {
    "GET", "/.well-known/oauth-protected-resource" ->
      HttpResponse(
        200,
        [#("Content-Type", "application/json"), #("Cache-Control", "no-store")],
        auth.protected_resource_metadata(resource_url, auth_servers, [
          config.required_scope,
        ]),
      )
    "POST", "/mcp" -> post(request, config, profile, now_ms, dispatch)
    _, "/mcp" | _, "/.well-known/oauth-protected-resource" ->
      response(405, "METHOD_NOT_ALLOWED")
    _, _ -> response(404, "NOT_FOUND")
  }
}

fn post(
  request: HttpRequest,
  config: auth.AuthConfig,
  profile: ProtocolProfile,
  now_ms: Int,
  dispatch: fn(Principal, List(#(String, String)), wire.NormalizedMessage) ->
    Outcome,
) -> HttpResponse {
  case validate_envelope(request) {
    Error(reply) -> reply
    Ok(sse) ->
      case auth.authenticate(config, request.headers, now_ms) {
        Error(error) -> {
          let status = case error.code {
            "HTTP_ORIGIN_FORBIDDEN" -> 403
            _ -> 401
          }
          let reply = response(status, error.code)
          HttpResponse(..reply, headers: [
            #(
              "WWW-Authenticate",
              "Bearer resource_metadata=\"" <> metadata_path <> "\"",
            ),
            ..reply.headers
          ])
        }
        Ok(p) ->
          case normalize(request, config, profile, p) {
            Error(reply) -> reply
            Ok(message) -> {
              let credentials = credential_values(request.headers, config)
              let clean =
                list.filter(request.headers, fn(h) {
                  !credential_header(h.0)
                  && !contains_credential(h.0, credentials)
                  && !contains_credential(h.1, credentials)
                })
              let outcome = dispatch(p, clean, message)
              case wire.encode_outcome(profile, message.id, outcome) {
                None -> HttpResponse(202, [#("Cache-Control", "no-store")], "")
                Some(body) ->
                  case sse {
                    True ->
                      HttpResponse(
                        200,
                        [
                          #("Content-Type", "text/event-stream"),
                          #("Cache-Control", "no-store"),
                        ],
                        "event: message\ndata: " <> body <> "\n\n",
                      )
                    False ->
                      HttpResponse(
                        200,
                        [
                          #("Content-Type", "application/json"),
                          #("Cache-Control", "no-store"),
                        ],
                        body,
                      )
                  }
              }
            }
          }
      }
  }
}

fn validate_envelope(request: HttpRequest) -> Result(Bool, HttpResponse) {
  use _ <- result.try(case string.byte_size(request.body) <= max_body_bytes {
    True -> Ok(Nil)
    False -> Error(response(413, "HTTP_BODY_TOO_LARGE"))
  })
  let content_type = case auth.header(request.headers, "content-type") {
    Ok(h) -> h
    Error(_) -> ""
  }
  let media_type = case string.split(content_type, ";") {
    [first, ..] -> string.lowercase(string.trim(first))
    _ -> ""
  }
  use _ <- result.try(case media_type == "application/json" {
    True -> Ok(Nil)
    False -> Error(response(415, "HTTP_CONTENT_TYPE_REQUIRED"))
  })
  let accept = case auth.header(request.headers, "accept") {
    Ok(h) -> h
    Error(_) -> ""
  }
  let json_ok = accepts(accept, "application/json")
  let sse_ok = accepts(accept, "text/event-stream")
  case json_ok || sse_ok {
    True -> Ok(sse_ok && !json_ok)
    False -> Error(response(406, "HTTP_ACCEPT_REQUIRED"))
  }
}

fn accepts(header: String, media: String) -> Bool {
  list.any(string.split(string.lowercase(header), ","), fn(part) {
    case list.map(string.split(part, ";"), string.trim) {
      [name, ..params] ->
        name == media
        && list.all(params, fn(p) {
          case string.split(p, "=") {
            ["q", "0"] | ["q", "0.0"] | ["q", "0.00"] | ["q", "0.000"] -> False
            _ -> True
          }
        })
      _ -> False
    }
  })
}

fn normalize(
  request: HttpRequest,
  config: auth.AuthConfig,
  profile: ProtocolProfile,
  p: Principal,
) -> Result(wire.NormalizedMessage, HttpResponse) {
  let version = case profile {
    Legacy20241105 -> "2024-11-05"
    Modern20260728 -> "2026-07-28"
  }
  use _ <- result.try(
    case
      auth.header(request.headers, "mcp-protocol-version") == Ok(version)
      && auth.header(request.headers, "mcp-session-id")
      == Ok(principal.session_id(p))
    {
      True -> Ok(Nil)
      False -> Error(response(400, "HEADER_BODY_MISMATCH"))
    },
  )
  use body <- result.try(
    json.parse(request.body, value.decoder())
    |> result.map_error(fn(_) { response(400, "MALFORMED_JSONRPC") }),
  )
  use _ <- result.try(
    case
      field_matches(body, ["params", "protocolVersion"], version)
      && field_matches(
        body,
        ["params", "_meta", "session_id"],
        principal.session_id(p),
      )
      && field_matches(
        body,
        ["params", "arguments", "actor"],
        principal.actor_id(p),
      )
      && field_matches(
        body,
        ["params", "_meta", "actor"],
        principal.actor_id(p),
      )
    {
      True -> Ok(Nil)
      False -> Error(response(403, "HEADER_BODY_MISMATCH"))
    },
  )
  use _ <- result.try(
    case safe_value(body, credential_values(request.headers, config)) {
      True -> Ok(Nil)
      False -> Error(response(403, "HTTP_CREDENTIAL_FORWARDING_FORBIDDEN"))
    },
  )
  // Missing jsonrpc is tolerated by the shared normalizer. An explicit wrong
  // value is refused here; IDs and argument shape are checked by the normalizer.
  use _ <- result.try(case field_matches(body, ["jsonrpc"], "2.0") {
    True -> Ok(Nil)
    False -> Error(response(400, "MALFORMED_JSONRPC"))
  })
  wire.decode_request(profile, request.body)
  |> result.map_error(fn(_) { response(400, "MALFORMED_JSONRPC") })
}

/// Absent optional fields are allowed. Present null/non-string fields and
/// malformed intermediate containers cannot conceal contradictory identities.
fn field_matches(
  body: value.Value,
  path: List(String),
  expected: String,
) -> Bool {
  case path {
    [] -> body == value.Text(expected)
    [key, ..rest] ->
      case body {
        value.Object(_) ->
          case value.get(body, key) {
            Error(_) -> True
            Ok(child) -> field_matches(child, rest, expected)
          }
        _ -> False
      }
  }
}

fn credential_header(name: String) -> Bool {
  list.contains(
    ["authorization", "cookie", "proxy-authorization", "set-cookie"],
    string.lowercase(name),
  )
}

fn credential_values(
  headers: List(#(String, String)),
  config: auth.AuthConfig,
) -> List(String) {
  let values =
    list.filter_map(headers, fn(h) {
      case credential_header(h.0) {
        True -> Ok(h.1)
        False -> Error(Nil)
      }
    })
  let token = case auth.header(headers, "authorization") {
    Ok(h) -> string.drop_start(h, 7)
    Error(_) -> ""
  }
  [config.signing_secret, token, ..values] |> list.filter(fn(s) { s != "" })
}

fn contains_credential(text: String, credentials: List(String)) -> Bool {
  list.any(credentials, fn(c) { string.contains(text, c) })
}

fn safe_value(body: value.Value, credentials: List(String)) -> Bool {
  case body {
    value.Text(s) -> !contains_credential(s, credentials)
    value.Object(fields) ->
      list.all(fields, fn(p) {
        !credential_header(p.0)
        && !contains_credential(p.0, credentials)
        && safe_value(p.1, credentials)
      })
    value.Array(values) ->
      list.all(values, fn(v) { safe_value(v, credentials) })
    _ -> True
  }
}
