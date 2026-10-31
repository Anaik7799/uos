//// Wave 2 transport regressions: preflight, termination and strict ingress.

import cepaf_gleam/mcp/http_auth as auth
import cepaf_gleam/mcp/transports/http
import cepaf_gleam/mcp/transports/stdio
import cepaf_gleam/mcp/types
import gleam/list
import gleam/string
import gleeunit/should

fn config() {
  auth.AuthConfig(
    ["https://nas-1.tail55d152.ts.net"],
    "issuer",
    "uos-mcp",
    "mcp",
    "wave2-transport-fixture-secret",
  )
}

fn headers() {
  let token =
    auth.sign_token(
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
      ),
      config().signing_secret,
    )
  [
    #("Origin", "https://nas-1.tail55d152.ts.net"),
    #("Authorization", "Bearer " <> token),
    #("Content-Type", "application/json"),
    #("Accept", "application/json"),
    #("Mcp-Protocol-Version", "2024-11-05"),
    #("Mcp-Session-Id", "session"),
  ]
}

fn handle(method, path, hs, body) {
  http.handle(
    http.HttpRequest(method, path, hs, body),
    config(),
    types.Legacy20241105,
    1000,
    "https://nas-1.tail55d152.ts.net/mcp",
    [],
    fn(_, _, _) {
      types.Refused(types.ToolError(
        "DISPATCHED",
        "fixture dispatch",
        types.NonRetryable,
      ))
    },
  )
}

pub fn options_advertises_delete_and_bounded_preflight_without_dispatch_test() {
  list.each(["/mcp", http.metadata_path], fn(path) {
    let reply = handle("OPTIONS", path, headers(), "")
    reply.status |> should.equal(204)
    reply.body |> should.equal("")
    auth.header(reply.headers, "access-control-allow-methods")
    |> should.equal(Ok("GET, POST, DELETE, OPTIONS"))
    auth.header(reply.headers, "access-control-allow-headers")
    |> should.equal(Ok(
      "Authorization, Content-Type, Accept, Mcp-Session-Id, Mcp-Protocol-Version",
    ))
    auth.header(reply.headers, "access-control-max-age")
    |> should.equal(Ok("86400"))
    auth.header(reply.headers, "x-content-type-options")
    |> should.equal(Ok("nosniff"))
  })
}

pub fn preflight_without_origin_is_allowed_but_invalid_or_duplicate_origin_refuses_test() {
  handle("OPTIONS", "/mcp", [], "").status |> should.equal(204)
  list.each(
    [
      [#("Origin", "https://evil.example")],
      [
        #("Origin", "https://nas-1.tail55d152.ts.net"),
        #("origin", "https://nas-1.tail55d152.ts.net"),
      ],
    ],
    fn(hs) {
      handle("OPTIONS", "/mcp", hs, "").status |> should.equal(403)
      handle("OPTIONS", http.metadata_path, hs, "").status
      |> should.equal(403)
    },
  )
}

pub fn delete_requires_authentication_and_origin_and_never_dispatches_test() {
  let reply = handle("DELETE", "/mcp", headers(), "")
  reply.status |> should.equal(204)
  reply.body |> should.equal("")
  auth.header(reply.headers, "cache-control") |> should.equal(Ok("no-store"))
  handle(
    "DELETE",
    "/mcp",
    list.filter(headers(), fn(h) { h.0 != "Authorization" }),
    "",
  ).status
  |> should.equal(401)
  handle("DELETE", "/mcp", [#("Origin", "https://evil.example")], "").status
  |> should.equal(403)
}

pub fn nested_duplicate_members_are_rejected_before_transport_dispatch_test() {
  let raw =
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\",\"params\":{\"arguments\":{\"x\":1,\"x\":2}}}"
  let reply = handle("POST", "/mcp", headers(), raw)
  reply.status |> should.equal(400)
  string.contains(reply.body, "DUPLICATE_JSON_KEY") |> should.be_true
  let assert Ok(session) =
    stdio.new_session(
      "actor",
      "client",
      "/workspace",
      "session",
      types.Legacy20241105,
      5000,
    )
  let assert Error(error) =
    stdio.ingest_chunk(session, raw <> "\n", 0, fn(_, _) {
      panic as "duplicate must not dispatch"
    })
  error.code |> should.equal("DUPLICATE_JSON_KEY")
}

pub fn standard_batch_identity_binding_checks_every_member_test() {
  let valid =
    "[{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"preflight_check\",\"arguments\":{\"actor\":\"actor\",\"benefit\":2,\"cost\":1}}}]"
  let assert Ok(#(p, clean, sse)) =
    http.prepare_standard(
      http.HttpRequest("POST", "/mcp", headers(), valid),
      config(),
      types.Legacy20241105,
      1000,
    )
  auth.header(clean, "authorization") |> should.be_error
  sse |> should.be_false
  let assert Error(mismatch) =
    http.prepare_standard(
      http.HttpRequest(
        "POST",
        "/mcp",
        headers(),
        string.replace(valid, "\"actor\":\"actor\"", "\"actor\":\"other\""),
      ),
      config(),
      types.Legacy20241105,
      1000,
    )
  mismatch.status |> should.equal(403)
  string.contains(mismatch.body, "HEADER_BODY_MISMATCH") |> should.be_true
  let assert Error(version_mismatch) =
    http.prepare_standard(
      http.HttpRequest(
        "POST",
        "/mcp",
        headers(),
        "[{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2026-07-28\"}}]",
      ),
      config(),
      types.Legacy20241105,
      1000,
    )
  version_mismatch.status |> should.equal(400)
  // The returned principal comes only from the verified HTTP bearer.
  let _ = p
}
