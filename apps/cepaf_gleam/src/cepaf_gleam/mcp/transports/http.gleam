//// T18 bounded Streamable HTTP adapter. The host supplies the session profile,
//// clock and dispatch closure; this module never creates effect authority.

import cepaf_gleam/harness/value
import cepaf_gleam/mcp/http_auth as auth
import cepaf_gleam/mcp/principal.{type Principal}
import cepaf_gleam/mcp/types.{type Outcome, type ProtocolProfile}
import cepaf_gleam/mcp/version
import cepaf_gleam/mcp/wire
import gleam/bit_array
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
      with_cors(
        HttpResponse(
          200,
          [
            #("Content-Type", "application/json"),
            #("Cache-Control", "no-store"),
          ],
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

fn with_cors(
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
            #("Access-Control-Allow-Methods", "GET, POST, OPTIONS"),
            ..resp.headers
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
    True ->
      case has_forbidden_nul(request.body) {
        True -> Error(response(400, "HTTP_NUL_BYTE_FORBIDDEN"))
        False ->
          case
            json_depth_bytes(
              bit_array.from_string(request.body),
              False,
              False,
              0,
              0,
            )
            > max_json_depth
          {
            True -> Error(response(400, "HTTP_JSON_DEPTH_EXCEEDED"))
            False -> Ok(sse_ok && !json_ok)
          }
      }
    False -> Error(response(406, "HTTP_ACCEPT_REQUIRED"))
  }
}

fn has_forbidden_nul(text: String) -> Bool {
  string.contains(text, "\u{0000}")
  || string.contains(text, "\\u0000")
  || string.contains(text, "\\U0000")
}

// Scan bytes directly: no per-byte list cells, and string braces do not nest.
fn json_depth_bytes(
  bytes: BitArray,
  in_string: Bool,
  escaped: Bool,
  depth: Int,
  maximum: Int,
) -> Int {
  case bytes, in_string, escaped {
    <<>>, _, _ -> maximum
    <<_, rest:bytes>>, True, True ->
      json_depth_bytes(rest, True, False, depth, maximum)
    <<0x5c, rest:bytes>>, True, False ->
      json_depth_bytes(rest, True, True, depth, maximum)
    <<0x22, rest:bytes>>, _, _ ->
      json_depth_bytes(rest, !in_string, False, depth, maximum)
    <<0x7b, rest:bytes>>, False, _ | <<0x5b, rest:bytes>>, False, _ -> {
      let next = depth + 1
      let maximum = case next > maximum {
        True -> next
        False -> maximum
      }
      json_depth_bytes(rest, False, False, next, maximum)
    }
    <<0x7d, rest:bytes>>, False, _ | <<0x5d, rest:bytes>>, False, _ ->
      json_depth_bytes(rest, False, False, depth - 1, maximum)
    <<_, rest:bytes>>, _, _ ->
      json_depth_bytes(rest, in_string, False, depth, maximum)
    _, _, _ -> maximum
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
