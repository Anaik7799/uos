//// T18 bounded Streamable HTTP adapter. The host supplies the session profile,
//// clock and dispatch closure; this module never creates effect authority.

import cepaf_gleam/harness/value
import cepaf_gleam/mcp/http_auth as auth
import cepaf_gleam/mcp/json_guard
import cepaf_gleam/mcp/principal.{type Principal}
import cepaf_gleam/mcp/types.{type Outcome, type ProtocolProfile}
import cepaf_gleam/mcp/version
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

pub const max_json_depth = 32

pub const metadata_path = "/.well-known/oauth-protected-resource"

fn response(status: Int, code: String) -> HttpResponse {
  HttpResponse(
    status,
    [#("Content-Type", "application/json"), ..security_headers()],
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
  let origin_check = case request.method {
    // Authentication supplies the same Origin check plus the resource
    // metadata challenge on POST/DELETE failures.
    "POST" | "DELETE" -> Ok(Nil)
    _ -> optional_origin(config, request.headers)
  }
  case origin_check {
    Error(reply) -> reply
    Ok(Nil) ->
      handle_allowed_origin(
        request,
        config,
        profile,
        now_ms,
        resource_url,
        auth_servers,
        dispatch,
      )
  }
}

/// Headers shared by standard ingress, preflight and session termination.
pub fn security_headers() -> List(#(String, String)) {
  [
    #("Cache-Control", "no-store"),
    #("X-Content-Type-Options", "nosniff"),
    #("X-Frame-Options", "DENY"),
    #("Referrer-Policy", "strict-origin-when-cross-origin"),
    #(
      "Content-Security-Policy",
      "default-src 'none'; frame-ancestors 'none'; base-uri 'none'",
    ),
    #("Vary", "Origin, Accept-Encoding"),
  ]
}

fn optional_origin(
  config: auth.AuthConfig,
  headers: List(#(String, String)),
) -> Result(Nil, HttpResponse) {
  case list.filter(headers, fn(h) { string.lowercase(h.0) == "origin" }) {
    [] -> Ok(Nil)
    [#(_, origin)] ->
      case auth.approved_origin(config, origin) {
        True -> Ok(Nil)
        False -> Error(response(403, "HTTP_ORIGIN_FORBIDDEN"))
      }
    _ -> Error(response(403, "HTTP_ORIGIN_FORBIDDEN"))
  }
}

fn handle_allowed_origin(
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
    "OPTIONS", "/mcp" | "OPTIONS", "/.well-known/oauth-protected-resource" ->
      with_cors(
        HttpResponse(
          204,
          [
            #("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS"),
            #(
              "Access-Control-Allow-Headers",
              "Authorization, Content-Type, Accept, Mcp-Session-Id, Mcp-Protocol-Version",
            ),
            #("Access-Control-Max-Age", "86400"),
            ..security_headers()
          ],
          "",
        ),
        config,
        request.headers,
      )
    "DELETE", "/mcp" ->
      case auth.authenticate(config, request.headers, now_ms) {
        Ok(_) ->
          with_cors(
            HttpResponse(204, security_headers(), ""),
            config,
            request.headers,
          )
        Error(error) ->
          response(
            case error.code {
              "HTTP_ORIGIN_FORBIDDEN" -> 403
              _ -> 401
            },
            error.code,
          )
      }
    "GET", "/.well-known/oauth-protected-resource" ->
      with_cors(
        HttpResponse(
          200,
          [#("Content-Type", "application/json"), ..security_headers()],
          auth.protected_resource_metadata(resource_url, auth_servers, [
            config.required_scope,
          ]),
        ),
        config,
        request.headers,
      )
    "POST", "/mcp" ->
      with_cors(
        post(request, config, profile, now_ms, resource_url, dispatch),
        config,
        request.headers,
      )
    _, "/mcp" | _, "/.well-known/oauth-protected-resource" ->
      response(405, "METHOD_NOT_ALLOWED")
    _, _ -> response(404, "NOT_FOUND")
  }
}

pub fn with_cors(
  resp: HttpResponse,
  config: auth.AuthConfig,
  req_headers: List(#(String, String)),
) -> HttpResponse {
  case auth.header(req_headers, "origin") {
    Ok(origin) ->
      case auth.approved_origin(config, origin) {
        True ->
          HttpResponse(..resp, headers: [
            #("Access-Control-Allow-Origin", origin),
            #("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS"),
            ..list.filter(resp.headers, fn(h) {
              string.lowercase(h.0) != "access-control-allow-methods"
              && string.lowercase(h.0) != "access-control-allow-origin"
            })
          ])
        False -> resp
      }
    Error(_) -> resp
  }
}

fn post(
  request: HttpRequest,
  config: auth.AuthConfig,
  profile: ProtocolProfile,
  now_ms: Int,
  resource_url: String,
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
          let metadata_uri =
            origin_base(resource_url)
            |> result.or(origin_base(config.expected_issuer))
            |> result.unwrap("")
            |> string.append(metadata_path)
          HttpResponse(..reply, headers: [
            #(
              "WWW-Authenticate",
              "Bearer resource_metadata=\"" <> metadata_uri <> "\"",
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

fn origin_base(url: String) -> Result(String, Nil) {
  let parsed = case url {
    "https://" <> rest -> Ok(#("https://", rest))
    "http://" <> rest -> Ok(#("http://", rest))
    _ -> Error(Nil)
  }
  use #(scheme, rest) <- result.try(parsed)
  case string.split(rest, "/") {
    [authority, ..] if authority != "" -> Ok(scheme <> authority)
    _ -> Error(Nil)
  }
}

fn validate_envelope(request: HttpRequest) -> Result(Bool, HttpResponse) {
  use sse <- result.try(validate_transport_envelope(request))
  // Retain the canonical transport's stricter historical textual NUL policy.
  // The native decoder independently rejects decoded NUL in keys and values.
  use _ <- result.try(case has_forbidden_nul(request.body) {
    True -> Error(response(400, "HTTP_NUL_BYTE_FORBIDDEN"))
    False -> Ok(Nil)
  })
  case json_guard.inspect(request.body, "HTTP") {
    Ok(_) -> Ok(sse)
    Error(error) -> Error(response(400, error.code))
  }
}

fn validate_transport_envelope(
  request: HttpRequest,
) -> Result(Bool, HttpResponse) {
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

/// Authenticate standard JSON-RPC ingress without converting typed arguments to
/// the legacy string-only wire representation. JSON syntax/envelope failures
/// are left to the standard handler; no invalid document is dispatched here.
/// Batch items share the authenticated HTTP identity, and each item's explicit
/// identity/protocol fields must agree before any item may execute.
pub fn prepare_standard(
  request: HttpRequest,
  config: auth.AuthConfig,
  profile: ProtocolProfile,
  now_ms: Int,
) -> Result(#(Principal, List(#(String, String)), Bool), HttpResponse) {
  use sse <- result.try(validate_transport_envelope(request))
  use p <- result.try(
    auth.authenticate(config, request.headers, now_ms)
    |> result.map_error(fn(error) {
      let reply =
        response(
          case error.code {
            "HTTP_ORIGIN_FORBIDDEN" -> 403
            _ -> 401
          },
          error.code,
        )
      let metadata_uri =
        origin_base(config.expected_audience)
        |> result.or(origin_base(config.expected_issuer))
        |> result.unwrap("")
        |> string.append(metadata_path)
      HttpResponse(..reply, headers: [
        #(
          "WWW-Authenticate",
          "Bearer resource_metadata=\"" <> metadata_uri <> "\"",
        ),
        ..reply.headers
      ])
    }),
  )
  use ver <- result.try(
    case auth.header(request.headers, "mcp-protocol-version") {
      Ok(ver) ->
        case
          version.matches_profile(profile, ver)
          && auth.header(request.headers, "mcp-session-id")
          == Ok(principal.session_id(p))
        {
          True -> Ok(ver)
          False -> Error(response(400, "HEADER_BODY_MISMATCH"))
        }
      Error(_) -> Error(response(400, "HEADER_BODY_MISMATCH"))
    },
  )
  let credentials = credential_values(request.headers, config)
  use _ <- result.try(case json_guard.inspect(request.body, "HTTP") {
    Error(_) -> Ok(Nil)
    Ok(body) -> {
      let items = case body {
        value.Array(items) -> items
        _ -> [body]
      }
      use _ <- result.try(
        case
          list.all(items, fn(item) {
            standard_field_matches(item, ["params", "protocolVersion"], ver)
            && standard_field_matches(
              item,
              ["params", "_meta", "session_id"],
              principal.session_id(p),
            )
          })
        {
          True -> Ok(Nil)
          False -> Error(response(400, "HEADER_BODY_MISMATCH"))
        },
      )
      use _ <- result.try(
        case
          list.all(items, fn(item) {
            standard_field_matches(
              item,
              ["params", "arguments", "actor"],
              principal.actor_id(p),
            )
            && standard_field_matches(
              item,
              ["params", "_meta", "actor"],
              principal.actor_id(p),
            )
          })
        {
          True -> Ok(Nil)
          False -> Error(response(403, "HEADER_BODY_MISMATCH"))
        },
      )
      case safe_value(body, credentials) {
        True -> Ok(Nil)
        False -> Error(response(403, "HTTP_CREDENTIAL_FORWARDING_FORBIDDEN"))
      }
    }
  })
  let clean =
    list.filter(request.headers, fn(h) {
      !credential_header(h.0)
      && !contains_credential(h.0, credentials)
      && !contains_credential(h.1, credentials)
    })
  Ok(#(p, clean, sse))
}

fn has_forbidden_nul(text: String) -> Bool {
  string.contains(text, "\u{0000}")
  || string.contains(text, "\\u0000")
  || string.contains(text, "\\U0000")
}

fn standard_field_matches(
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
            Ok(child) -> standard_field_matches(child, rest, expected)
            Error(_) -> True
          }
        // A malformed params/arguments container is a standard RPC validation
        // error. It cannot contain an explicit contradictory identity field.
        _ -> True
      }
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
  let header_version = auth.header(request.headers, "mcp-protocol-version")
  use ver <- result.try(case header_version {
    Ok(ver) ->
      case
        version.matches_profile(profile, ver)
        && auth.header(request.headers, "mcp-session-id")
        == Ok(principal.session_id(p))
      {
        True -> Ok(ver)
        False -> Error(response(400, "HEADER_BODY_MISMATCH"))
      }
    Error(_) -> Error(response(400, "HEADER_BODY_MISMATCH"))
  })
  use body <- result.try(
    json.parse(request.body, value.decoder())
    |> result.map_error(fn(_) { response(400, "MALFORMED_JSONRPC") }),
  )
  use _ <- result.try(
    case field_matches(body, ["params", "protocolVersion"], ver) {
      True -> Ok(Nil)
      False -> Error(response(400, "HEADER_BODY_MISMATCH"))
    },
  )
  use _ <- result.try(
    case
      field_matches(
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
