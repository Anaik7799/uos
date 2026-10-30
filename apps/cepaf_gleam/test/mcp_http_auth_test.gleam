import cepaf_gleam/mcp/http_auth as auth
import cepaf_gleam/mcp/principal
import cepaf_gleam/mcp/transports/http
import cepaf_gleam/mcp/types.{
  Legacy20241105, Modern20260728, NonRetryable, Refused, ToolError,
}
import gleam/list
import gleam/string
import gleeunit/should

fn config() {
  auth.AuthConfig(
    ["https://nas-1.tail55d152.ts.net"],
    "issuer",
    "uos-mcp",
    "mcp",
    "secret-canary-do-not-leak",
  )
}

fn claims() {
  auth.TokenClaims(
    "issuer",
    "uos-mcp",
    "actor",
    "client",
    "/workspace",
    "session",
    ["mcp"],
    100,
    2000,
  )
}

fn headers(token: String) {
  [
    #("Origin", "https://nas-1.tail55d152.ts.net"),
    #("Authorization", "Bearer " <> token),
    #("Cookie", "secret-cookie"),
    #("Content-Type", "application/json"),
    #("Accept", "application/json"),
    #("MCP-Protocol-Version", "2024-11-05"),
    #("Mcp-Session-Id", "session"),
  ]
}

fn replace(headers: List(#(String, String)), key: String, replacement: String) {
  list.map(headers, fn(p) {
    case p.0 == key {
      True -> #(key, replacement)
      False -> p
    }
  })
}

fn run(headers, body) {
  http.handle(
    http.HttpRequest("POST", "/mcp", headers, body),
    config(),
    Legacy20241105,
    1000,
    "https://nas-1.tail55d152.ts.net/mcp",
    ["https://auth.tail55d152.ts.net"],
    fn(_, _, _) { Refused(ToolError("DISPATCHED", "safe", NonRetryable)) },
  )
}

pub fn invalid_origin_issuer_audience_scope_refused_test() {
  let token = auth.sign_token(claims(), config().signing_secret)
  let assert Ok(p) = auth.authenticate(config(), headers(token), 1000)
  principal.actor_id(p) |> should.equal("actor")
  principal.session_id(p) |> should.equal("session")
  list.each(
    [
      "http://nas-1.tail55d152.ts.net:4100",
      "https://evil.example",
      "*",
      "null",
      "https://nas-1.tail55d152.ts.net.evil.example",
      "https://nas-1.tail55d152.ts.net/",
    ],
    fn(origin) {
      let assert Error(e) =
        auth.authenticate(
          config(),
          replace(headers(token), "Origin", origin),
          1000,
        )
      e.code |> should.equal("HTTP_ORIGIN_FORBIDDEN")
    },
  )
  list.each(
    [
      auth.TokenClaims(..claims(), issuer: "bad"),
      auth.TokenClaims(..claims(), audience: "bad"),
      auth.TokenClaims(..claims(), scopes: []),
      auth.TokenClaims(..claims(), expires_at_ms: 1000),
      auth.TokenClaims(..claims(), issued_at_ms: 1001),
    ],
    fn(c) {
      auth.authenticate(
        config(),
        headers(auth.sign_token(c, config().signing_secret)),
        1000,
      )
      |> should.be_error
    },
  )
  auth.authenticate(config(), headers(token <> "0"), 1000) |> should.be_error
  auth.authenticate(
    config(),
    list.filter(headers(token), fn(p) { p.0 != "Origin" }),
    1000,
  )
  |> should.be_error
  let metadata =
    http.handle(
      http.HttpRequest("GET", "/.well-known/oauth-protected-resource", [], ""),
      config(),
      Legacy20241105,
      1000,
      "https://nas-1.tail55d152.ts.net/mcp",
      ["https://auth.tail55d152.ts.net"],
      fn(_, _, _) { panic as "metadata must not dispatch" },
    )
  metadata.status |> should.equal(200)
  string.contains(metadata.body, "authorization_servers") |> should.be_true
  string.contains(metadata.body, "scopes_supported") |> should.be_true
}

pub fn header_body_mismatch_refused_test() {
  let hs = headers(auth.sign_token(claims(), config().signing_secret))
  list.each(
    [
      replace(hs, "MCP-Protocol-Version", "2026-07-28"),
      replace(hs, "Mcp-Session-Id", "other"),
    ],
    fn(h) {
      let response = run(h, "{\"id\":1,\"method\":\"ping\"}")
      response.status |> should.equal(400)
      string.contains(response.body, "HEADER_BODY_MISMATCH") |> should.be_true
    },
  )
  list.each(
    [
      "{\"protocolVersion\":\"2026-07-28\"}",
      "{\"_meta\":{\"session_id\":\"other\"}}",
      "{\"arguments\":{\"actor\":\"other\"}}",
      "{\"_meta\":{\"actor\":\"other\"}}",
      "{\"_meta\":{\"session_id\":null}}",
    ],
    fn(params) {
      let response =
        run(hs, "{\"id\":1,\"method\":\"ping\",\"params\":" <> params <> "}")
      list.contains([400, 403], response.status) |> should.be_true
      string.contains(response.body, "HEADER_BODY_MISMATCH") |> should.be_true
    },
  )
}

pub fn token_not_forwarded_as_backend_credential_test() {
  let token = auth.sign_token(claims(), config().signing_secret)
  let hs = headers(token)
  let response =
    http.handle(
      http.HttpRequest(
        "POST",
        "/mcp",
        hs,
        "{\"id\":1,\"method\":\"ping\",\"params\":{\"arguments\":{\"actor\":\"actor\",\"query\":\"ok\"}}}",
      ),
      config(),
      Legacy20241105,
      1000,
      "https://nas-1.tail55d152.ts.net/mcp",
      [],
      fn(p, clean, message) {
        principal.actor_id(p) |> should.equal("actor")
        list.any(clean, fn(h) {
          list.contains(["authorization", "cookie"], string.lowercase(h.0))
          || string.contains(h.1, token)
        })
        |> should.be_false
        list.any(message.args, fn(p) { string.contains(p.1, token) })
        |> should.be_false
        string.contains(message.canonical_json, token) |> should.be_false
        Refused(ToolError("DISPATCHED", "safe", NonRetryable))
      },
    )
  response.status |> should.equal(200)
  string.contains(response.body, "DISPATCHED") |> should.be_true
  list.each(
    [token, "Bearer " <> token, "secret-canary-do-not-leak"],
    fn(credential) {
      let body =
        "{\"id\":1,\"method\":\"ping\",\"params\":{\"arguments\":{\"credential\":\""
        <> credential
        <> "\"}}}"
      let blocked = run(hs, body)
      blocked.status |> should.equal(403)
      string.contains(blocked.body, credential) |> should.be_false
    },
  )
  list.each(
    [
      "secret-canary-do-not-leak",
      "Bearer secret-canary-do-not-leak",
      "Basic secret-canary-do-not-leak",
      "",
    ],
    fn(bad) {
      let response =
        run(replace(hs, "Authorization", bad), "{\"id\":1,\"method\":\"ping\"}")
      response.status |> should.equal(401)
      string.contains(response.body, "secret-canary-do-not-leak")
      |> should.be_false
    },
  )
}

pub fn response_negotiation_and_limits_test() {
  let hs = headers(auth.sign_token(claims(), config().signing_secret))
  let sse =
    run(
      replace(hs, "Accept", "text/event-stream"),
      "{\"id\":1,\"method\":\"ping\"}",
    )
  sse.status |> should.equal(200)
  string.starts_with(sse.body, "event: message\ndata: ") |> should.be_true
  string.ends_with(sse.body, "\n\n") |> should.be_true
  let notification = run(hs, "{\"method\":\"notifications/initialized\"}")
  notification.status |> should.equal(202)
  notification.body |> should.equal("")
  run(replace(hs, "Content-Type", "text/plain"), "{}").status
  |> should.equal(415)
  run(replace(hs, "Accept", "text/html"), "{}").status |> should.equal(406)
  run(hs, string.repeat("é", 524_289)).status |> should.equal(413)
}

pub fn duplicate_headers_and_configured_origins_test() {
  let token = auth.sign_token(claims(), config().signing_secret)
  let hs = headers(token)
  list.each(
    [
      #("origin", "https://nas-1.tail55d152.ts.net"),
      #("authorization", "Bearer " <> token),
    ],
    fn(h) { auth.authenticate(config(), [h, ..hs], 1000) |> should.be_error },
  )
  auth.authenticate(
    config(),
    list.filter(hs, fn(h) { h.0 != "Authorization" }),
    1000,
  )
  |> should.be_error
  auth.authenticate(
    config(),
    headers(auth.sign_token(claims(), "wrong-signing-key")),
    1000,
  )
  |> should.be_error
  let origin = "https://vm-1.tail55d152.ts.net:8443"
  let alternate = auth.AuthConfig(..config(), approved_origins: [origin])
  auth.authenticate(alternate, replace(hs, "Origin", origin), 1000)
  |> should.be_ok
  list.each(
    [
      "http://nas-1.tail55d152.ts.net:4100",
      "https://evil.example",
      "*",
      "null",
      "https://nas-1.tail55d152.ts.net@evil.example",
    ],
    fn(origin) {
      let invalid_config =
        auth.AuthConfig(..config(), approved_origins: [origin])
      auth.authenticate(invalid_config, replace(hs, "Origin", origin), 1000)
      |> should.be_error
    },
  )
  let forbidden =
    run(replace(hs, "Origin", "http://nas-1.tail55d152.ts.net:4100"), "{}")
  forbidden.status |> should.equal(403)
  list.any(forbidden.headers, fn(h) {
    h.0 == "WWW-Authenticate"
    && string.contains(h.1, "/.well-known/oauth-protected-resource")
  })
  |> should.be_true
  list.each(
    [#("mcp-protocol-version", "2024-11-05"), #("mcp-session-id", "session")],
    fn(h) {
      let response = run([h, ..hs], "{\"id\":1,\"method\":\"ping\"}")
      response.status |> should.equal(400)
      string.contains(response.body, "HEADER_BODY_MISMATCH") |> should.be_true
    },
  )
}

pub fn modern_profile_and_exact_byte_limit_test() {
  let hs = headers(auth.sign_token(claims(), config().signing_secret))
  let response =
    http.handle(
      http.HttpRequest(
        "POST",
        "/mcp",
        replace(hs, "MCP-Protocol-Version", "2026-07-28"),
        "{\"jsonrpc\":\"2.0\",\"id\":\"modern\",\"method\":\"ping\",\"params\":{\"protocolVersion\":\"2026-07-28\",\"_meta\":{\"session_id\":\"session\",\"actor\":\"actor\"}}}",
      ),
      config(),
      Modern20260728,
      1000,
      "https://nas-1.tail55d152.ts.net/mcp",
      [],
      fn(_, _, _) {
        Refused(ToolError("MODERN_DISPATCH", "safe", NonRetryable))
      },
    )
  response.status |> should.equal(200)
  string.contains(response.body, "MODERN_DISPATCH") |> should.be_true
  let body = "{\"id\":1,\"method\":\"ping\"}"
  let at_limit =
    body <> string.repeat(" ", http.max_body_bytes - string.byte_size(body))
  run(hs, at_limit).status |> should.equal(200)
  run(hs, at_limit <> " ").status |> should.equal(413)
  run(replace(hs, "Accept", "application/json;q=0, text/event-stream"), body).headers
  |> list.contains(#("Content-Type", "text/event-stream"))
  |> should.be_true
  run(replace(hs, "Accept", "application/json;q=0"), body).status
  |> should.equal(406)
}

pub fn credential_aliases_and_json_escaping_refused_test() {
  let token = auth.sign_token(claims(), config().signing_secret)
  let hs = [
    #("X-Backend", token),
    #(token, "credential-in-header-name"),
    ..headers(token)
  ]
  let response =
    http.handle(
      http.HttpRequest("POST", "/mcp", hs, "{\"id\":1,\"method\":\"ping\"}"),
      config(),
      Legacy20241105,
      1000,
      "https://nas-1.tail55d152.ts.net/mcp",
      [],
      fn(_, clean, _) {
        list.any(clean, fn(h) {
          string.contains(h.0, token) || string.contains(h.1, token)
        })
        |> should.be_false
        Refused(ToolError("CLEAN", "safe", NonRetryable))
      },
    )
  response.status |> should.equal(200)
  let escaped =
    string.replace(token, "A", "\\u0041") |> string.replace("B", "\\u0042")
  let blocked =
    run(
      headers(token),
      "{\"id\":1,\"method\":\"ping\",\"params\":{\"arguments\":{\"value\":\""
        <> escaped
        <> "\"}}}",
    )
  blocked.status |> should.equal(403)
  string.contains(blocked.body, token) |> should.be_false
}
