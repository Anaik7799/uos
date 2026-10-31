//// Ephemeral Ed25519 OIDC and HMAC transport fixtures, never real approvals.

import cepaf_gleam/ecology/release_approval as approval
import cepaf_gleam/ecology/release_authority as authority
import cepaf_gleam/ecology/release_identity as identity
import cepaf_gleam/ecology/release_intent as intent
import cepaf_gleam/ecology/release_store as store
import cepaf_gleam/harness/telegram_store_transport as transport
import cepaf_gleam/mcp/http_auth as auth
import cepaf_gleam/mcp/transports/http
import cepaf_gleam/mcp/transports/zenoh
import ecology_release_authority_test as native_fixture
import gleam/erlang/process
import gleam/json
import gleam/list
import gleam/option.{Some}
import gleam/result
import gleam/string
import gleeunit/should
import indrajaal/release_mcp as m

@external(erlang, "telegram_approval_test_crypto", "public_key")
fn public_key(role: String) -> String

@external(erlang, "telegram_approval_test_crypto", "sign")
fn sign(role: String, payload: String) -> String

pub const host = "nas-1.tail55d152.ts.net"

const issuer = "https://nas-1.tail55d152.ts.net:4101/realms/uos"

const origin = "https://nas-1.tail55d152.ts.net"

const workspace = "/private/release-ingress-fixture"

const actor = "fixture-worker"

const secret = "private-ephemeral-transport-hmac-key-123456789"

fn dg(c) {
  "sha256:" <> string.repeat(c, 64)
}

pub fn fixture() {
  let now = authority.host_clock()
  let sec = now.utc_ms / 1000
  let jwks =
    json.object([
      #(
        "keys",
        json.array(
          [
            json.object([
              #("kty", json.string("OKP")),
              #("crv", json.string("Ed25519")),
              #("kid", json.string("operator-key")),
              #("alg", json.string("EdDSA")),
              #("x", json.string(public_key("operator"))),
            ]),
          ],
          fn(x) { x },
        ),
      ),
    ])
    |> json.to_string
  let assert Ok(id) =
    identity.configure(
      issuer,
      "uos-release-control",
      jwks,
      sec * 1000,
      300_000,
      "uos-release-client",
      ["urn:uos:mfa"],
      30_000,
    )
  let ss =
    list.map([approval.Operator, approval.Codex, approval.Agy], fn(role) {
      let name = approval.role_name(role)
      approval.Signer(
        role,
        name <> "-subject",
        name <> "-key",
        public_key(name),
      )
    })
  let assert Ok(roster) =
    approval.new_roster(ss, now.utc_ms, now.utc_ms + 120_000)
  let assert Ok(request) =
    intent.new(intent.Proposal(
      intent.Digests(
        dg("a"),
        dg("b"),
        dg("c"),
        dg("d"),
        dg("e"),
        dg("f"),
        dg("1"),
        dg("2"),
        dg("3"),
        dg("4"),
      ),
      intent.Execution(workspace, "fixture-plan", "fixture-task", actor, 1),
      host,
      "boot-fixture",
      "vm-fixture",
      "runtime:fixture",
      1,
      "fixture",
      intent.Window(
        now.utc_ms,
        now.utc_ms + 60_000,
        now.mono_ms,
        now.mono_ms + 60_000,
      ),
    ))
  // No native worker is reached by this unavailable boundary. This fixture
  // tests actual owner+crypto refusal; native success is a separate root test.
  let native =
    transport.reviewed_local_configuration(
      "/unavailable/guardian",
      string.repeat("0", 64),
      "/unavailable/worker",
      string.repeat("0", 64),
      "/unavailable/fixture.sqlite3",
    )
  let ac =
    authority.Configuration(
      id,
      roster,
      native,
      ["operator-subject"],
      host,
      "boot-fixture",
      "vm-fixture",
      1000,
      authority.host_clock,
    )
  let assert Ok(owner) = authority.start(ac, authority.unavailable_boundary())
  let http_config =
    auth.AuthConfig(
      [origin],
      origin <> "/issuer",
      origin <> "/release",
      "release:control",
      secret,
    )
  let assert Ok(config) =
    m.configure(
      id,
      http_config,
      host,
      "boot-fixture",
      "vm-fixture",
      [m.Prepared(request, owner.data)],
      [#(actor, "operator-subject")],
      500,
    )
  let token = oidc_token(sec, "operator-subject", "operator", "urn:uos:mfa")
  #(config, request, token, owner.data, id, http_config, roster)
}

fn oidc_token(sec, subject, signer, acr) {
  json.object([
    #("sub", json.string(subject)),
    #("iss", json.string(issuer)),
    #("aud", json.string("uos-release-control")),
    #("iat", json.int(sec)),
    #("nbf", json.int(sec)),
    #("exp", json.int(sec + 120)),
    #(
      "realm_access",
      json.object([#("roles", json.array(["uos-release-client"], json.string))]),
    ),
    #("acr", json.string(acr)),
  ])
  |> json.to_string
  |> sign(signer, _)
}

pub fn rpc(name, args) {
  json.object([
    #("jsonrpc", json.string("2.0")),
    #("id", json.int(7)),
    #("method", json.string("tools/call")),
    #(
      "params",
      json.object([
        #("name", json.string(name)),
        #("arguments", json.object(args)),
      ]),
    ),
  ])
  |> json.to_string
}

fn transport_token(who, ws, now) {
  auth.sign_token(
    auth.TokenClaims(
      origin <> "/issuer",
      origin <> "/release",
      who,
      "private-test",
      ws,
      "fixture-session",
      ["release:control"],
      now - 1000,
      now + 60_000,
    ),
    secret,
  )
}

pub fn request(body, token) {
  let now = authority.host_clock()
  http.HttpRequest(
    "POST",
    "/mcp",
    [
      #("content-type", "application/json"),
      #("accept", "application/json"),
      #("origin", origin),
      #(
        "authorization",
        "Bearer " <> transport_token(actor, workspace, now.utc_ms),
      ),
      #("mcp-protocol-version", "2026-07-28"),
      #("mcp-session-id", "fixture-session"),
      #("uos-release-oidc", token),
    ],
    body,
  )
}

fn has(resp: http.HttpResponse, s: String) {
  string.contains(resp.body, s) |> should.be_true
}

fn lacks(resp: http.HttpResponse, s: String) {
  string.contains(resp.body, s) |> should.be_false
}

pub fn actual_http_crypto_status_and_public_intent_test() {
  let #(config, i, token, _, _, _, _) = fixture()
  let reply =
    m.handle_http(
      config,
      request(
        rpc("release_status", [
          #("intent_digest", json.string(intent.digest(i))),
        ]),
        token,
      ),
    )
  reply.status |> should.equal(200)
  has(reply, "no_grant")
  has(reply, "isError")
  lacks(reply, token)
  lacks(reply, secret)
  let reply =
    m.handle_http(
      config,
      request(
        rpc("release_intent", [
          #("intent_digest", json.string(intent.digest(i))),
        ]),
        token,
      ),
    )
  has(reply, intent.digest(i))
  lacks(reply, "runtime_evidence")
}

pub fn malformed_closed_wire_never_reaches_owner_test() {
  let #(config, i, token, owner, _, _, _) = fixture()
  let valid =
    rpc("release_status", [#("intent_digest", json.string(intent.digest(i)))])
  list.each(
    [
      "[]",
      "null",
      "{",
      "{\"jsonrpc\":\"2.0\",\"id\":1,\"id\":2,\"method\":\"tools/list\"}",
      string.replace(valid, "\"tools/call\"", "\"unknown\""),
      string.replace(valid, "\"arguments\":{", "\"extra\":true,\"arguments\":{"),
      rpc("release_status", [
        #("intent_digest", json.string(intent.digest(i))),
        #("extra", json.string("x")),
      ]),
      rpc("release_status", [#("intent_digest", json.int(1))]),
      rpc("unknown", [#("intent_digest", json.string(intent.digest(i)))]),
      string.repeat(" ", m.maximum_body_bytes + 1),
      "{\"jsonrpc\":\"2.0\",\"method\":\"tools/call\",\"params\":{}}",
    ],
    fn(body) {
      m.handle_http(config, request(body, token)).status |> should.equal(400)
    },
  )
  let assert Ok(state) = authority.get(owner, 500)
  state.phase |> should.equal(authority.NoGrant)
}

pub fn both_real_identity_proofs_required_and_sanitized_test() {
  let #(config, i, token, _, _, _, _) = fixture()
  let body =
    rpc("release_status", [#("intent_digest", json.string(intent.digest(i)))])
  let req = request(body, token)
  let bad_http =
    http.HttpRequest(
      ..req,
      headers: list.map(req.headers, fn(h) {
        case h.0 == "authorization" {
          True -> #(h.0, "Bearer invalid")
          False -> h
        }
      }),
    )
  m.handle_http(config, bad_http).status |> should.equal(401)
  list.each(
    [
      "invalid",
      token <> "x",
      oidc_token(
        authority.host_clock().utc_ms / 1000,
        "other-subject",
        "operator",
        "urn:uos:mfa",
      ),
      oidc_token(
        authority.host_clock().utc_ms / 1000,
        "operator-subject",
        "codex",
        "urn:uos:mfa",
      ),
      oidc_token(
        authority.host_clock().utc_ms / 1000,
        "operator-subject",
        "operator",
        "not-urn:uos:mfa",
      ),
    ],
    fn(t) {
      let reply = m.handle_http(config, request(body, t))
      has(reply, "RELEASE_IDENTITY")
      lacks(reply, t)
    },
  )
  let duplicate =
    http.HttpRequest(..req, headers: [
      #("UOS-Release-OIDC", token),
      ..req.headers
    ])
  m.handle_http(config, duplicate).status |> should.equal(400)
  let absent =
    http.HttpRequest(
      ..req,
      headers: list.filter(req.headers, fn(h) { h.0 != "uos-release-oidc" }),
    )
  m.handle_http(config, absent).status |> should.equal(400)
}

pub fn authenticated_transport_workspace_mismatch_rejected_test() {
  let #(config, i, token, _, _, _, _) = fixture()
  let req =
    request(
      rpc("release_status", [#("intent_digest", json.string(intent.digest(i)))]),
      token,
    )
  let changed =
    http.HttpRequest(
      ..req,
      headers: list.map(req.headers, fn(h) {
        case h.0 == "authorization" {
          True -> #(
            h.0,
            "Bearer "
              <> transport_token(
              actor,
              "/private/other",
              authority.host_clock().utc_ms,
            ),
          )
          False -> h
        }
      }),
    )
  has(m.handle_http(config, changed), "RELEASE_SCOPE_REFUSED")
}

pub fn actual_owner_unavailable_boundary_cannot_issue_test() {
  let #(config, i, token, owner, _, _, roster) = fixture()
  let rs =
    list.map([approval.Operator, approval.Codex, approval.Agy], fn(role) {
      let name = approval.role_name(role)
      let body =
        json.object([
          #("version", json.string(intent.approval_purpose)),
          #("purpose", json.string(intent.approval_purpose)),
          #("role", json.string(name)),
          #("subject", json.string(name <> "-subject")),
          #("decision", json.string("approve")),
          #("intent_digest", json.string(intent.digest(i))),
          #("effect_id", json.string(intent.transaction_id(i))),
          #("roster_digest", json.string(approval.roster_digest(roster))),
          #("iat_ms", json.int(intent.created_utc_ms(i))),
          #("nbf_ms", json.int(intent.created_utc_ms(i))),
          #("exp_ms", json.int(intent.expires_utc_ms(i))),
        ])
        |> json.to_string
      sign(name, body)
    })
  let assert [op, co, ag] = rs
  let reply =
    m.handle_http(
      config,
      request(
        rpc("release_issue", [
          #("intent_digest", json.string(intent.digest(i))),
          #("operator_receipt", json.string(op)),
          #("codex_receipt", json.string(co)),
          #("agy_receipt", json.string(ag)),
        ]),
        token,
      ),
    )
  has(reply, "RELEASE_OWNER_HOLD_RECONCILE")
  let assert Ok(s) = authority.get(owner, 500)
  s.dispatch_handoffs |> should.equal(0)
  lacks(reply, op)
}

pub fn known_registry_and_numeric_command_boundaries_test() {
  let #(config, i, token, _, _, _, _) = fixture()
  has(
    m.handle_http(
      config,
      request(
        rpc("release_status", [
          #("intent_digest", json.string(string.repeat("0", 64))),
        ]),
        token,
      ),
    ),
    "RELEASE_INTENT_UNKNOWN",
  )
  list.each(
    [
      #("0", "0", "stage", "0"),
      #("01", "0", "stage", "0"),
      #("1", "-1", "stage", "0"),
      #("1", "0", "unknown", "0"),
      #("1", "0", "stage", "1"),
      #("1", "0", "replace", "15"),
    ],
    fn(p) {
      let resp =
        m.handle_http(
          config,
          request(
            rpc("release_step", [
              #("intent_digest", json.string(intent.digest(i))),
              #("epoch", json.string(p.0)),
              #("generation", json.string(p.1)),
              #("command", json.string(p.2)),
              #("index", json.string(p.3)),
            ]),
            token,
          ),
        )
      has(resp, "RELEASE_OWNER_HOLD_RECONCILE")
    },
  )
}

fn envelope(body) {
  let topic = "indrajaal/mcp/request/fixture/request1"
  let reply = "indrajaal/mcp/response/fixture/request1"
  zenoh.SignedZenohEnvelope(
    topic,
    reply,
    actor,
    "private-test",
    workspace,
    "fixture-session",
    body,
    zenoh.compute_signature(
      secret,
      topic,
      reply,
      actor,
      "private-test",
      workspace,
      "fixture-session",
      body,
    ),
  )
}

fn zenoh_body(tool, args, token) {
  json.object([
    #("jsonrpc", json.string("2.0")),
    #("id", json.int(7)),
    #("method", json.string("tools/call")),
    #(
      "params",
      json.object([
        #("name", json.string(tool)),
        #("arguments", json.object(args)),
        #("_meta", json.object([#("release_oidc_token", json.string(token))])),
      ]),
    ),
  ])
  |> json.to_string
}

pub fn actual_signed_zenoh_and_oidc_double_identity_test() {
  let #(config, i, token, _, _, _, _) = fixture()
  let e =
    envelope(zenoh_body(
      "release_status",
      [#("intent_digest", json.string(intent.digest(i)))],
      token,
    ))
  let assert Ok(Some(#(_, body))) =
    m.handle_zenoh(config, secret, True, "fixture", e)
  string.contains(body, "no_grant") |> should.be_true
  string.contains(body, token) |> should.be_false
  m.handle_zenoh(config, secret, False, "fixture", e)
  |> result.is_error
  |> should.be_true
  m.handle_zenoh(
    config,
    secret,
    True,
    "fixture",
    zenoh.SignedZenohEnvelope(..e, signature: "forged"),
  )
  |> result.is_error
  |> should.be_true
  m.handle_zenoh(
    config,
    secret,
    True,
    "fixture",
    zenoh.SignedZenohEnvelope(
      ..e,
      reply_topic: "indrajaal/mcp/response/foreign/request1",
    ),
  )
  |> result.is_error
  |> should.be_true
  let no_oidc =
    envelope(
      rpc("release_status", [#("intent_digest", json.string(intent.digest(i)))]),
    )
  let assert Ok(Some(#(_, missing))) =
    m.handle_zenoh(config, secret, True, "fixture", no_oidc)
  string.contains(missing, "RELEASE_IDENTITY_REFUSED") |> should.be_true
}

pub fn standard_list_initialize_and_config_bounds_test() {
  let #(config, i, token, owner, id, hc, _) = fixture()
  let body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\"}"
  let reply = m.handle_http(config, request(body, token))
  list.each(m.tool_names(), fn(name) { has(reply, name) })
  has(reply, "additionalProperties")
  let init =
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2026-07-28\",\"clientInfo\":{\"name\":\"test\",\"version\":\"1\"},\"capabilities\":{}}}"
  has(m.handle_http(config, request(init, token)), "uos-release-preparation")
  list.each([[], [m.Prepared(i, owner), m.Prepared(i, owner)]], fn(ps) {
    m.configure(
      id,
      hc,
      host,
      "boot-fixture",
      "vm-fixture",
      ps,
      [#(actor, "operator-subject")],
      500,
    )
    |> result.is_error
    |> should.be_true
  })
  m.configure(
    id,
    hc,
    host,
    "boot-fixture",
    "OTHER",
    [m.Prepared(i, owner)],
    [#(actor, "operator-subject")],
    500,
  )
  |> result.is_error
  |> should.be_true
  m.unavailable().status |> should.equal(503)
}

pub fn actual_native_owner_issue_consume_revoke_via_http_ingress_test() {
  let #(ac, i, receipts, token, _) = native_fixture.fixture(30_000)
  let effects = process.new_subject()
  let assert Ok(owner) =
    authority.start(
      ac,
      authority.Boundary(fn(_, _) { Ok(Nil) }, fn(h) {
        process.send(effects, authority.handoff_event(h))
        Ok(Nil)
      }),
    )
  let hc =
    auth.AuthConfig(
      [origin],
      origin <> "/issuer",
      origin <> "/release",
      "release:control",
      secret,
    )
  let ex = intent.execution(i)
  let assert Ok(config) =
    m.configure(
      ac.identity,
      hc,
      ac.host,
      ac.boot,
      ac.clock_domain,
      [m.Prepared(i, owner.data)],
      [#(ex.worker, "operator-subject")],
      3000,
    )
  let headers =
    request("", token).headers
    |> list.map(fn(h) {
      case h.0 == "authorization" {
        True -> #(
          h.0,
          "Bearer "
            <> transport_token(
            ex.worker,
            ex.workspace,
            authority.host_clock().utc_ms,
          ),
        )
        False -> h
      }
    })
  let assert [op, co, ag] = receipts
  let issue =
    rpc("release_issue", [
      #("intent_digest", json.string(intent.digest(i))),
      #("operator_receipt", json.string(op.token)),
      #("codex_receipt", json.string(co.token)),
      #("agy_receipt", json.string(ag.token)),
    ])
  let issued =
    m.handle_http(config, http.HttpRequest("POST", "/mcp", headers, issue))
  has(issued, "recorded")
  lacks(issued, op.token)
  let step =
    rpc("release_step", [
      #("intent_digest", json.string(intent.digest(i))),
      #("epoch", json.string("1")),
      #("generation", json.string("0")),
      #("command", json.string("stage")),
      #("index", json.string("0")),
    ])
  let done =
    m.handle_http(config, http.HttpRequest("POST", "/mcp", headers, step))
  has(done, "dispatch_handoffs")
  let assert Ok(event) = process.receive(effects, 1000)
  { event.event_index > 0 } |> should.be_true
  let duplicate =
    m.handle_http(config, http.HttpRequest("POST", "/mcp", headers, step))
  has(duplicate, "RELEASE_OWNER_HOLD_RECONCILE")
  let revoke =
    rpc("release_revoke", [
      #("intent_digest", json.string(intent.digest(i))),
      #("reason", json.string("operator_revoked")),
    ])
  has(
    m.handle_http(config, http.HttpRequest("POST", "/mcp", headers, revoke)),
    "stopped",
  )
  let assert Ok(view) = authority.get(owner.data, 1000)
  view.dispatch_handoffs |> should.equal(1)
  view.revocation_requested |> should.be_true
}

pub fn authenticated_initialized_notification_and_header_bounds_test() {
  let #(config, _, token, owner, _, _, _) = fixture()
  let body = "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}"
  let reply = m.handle_http(config, request(body, token))
  reply.status |> should.equal(202)
  reply.body |> should.equal("")
  m.handle_http(config, request(body, "bad")).status |> should.equal(403)
  let req = request(body, token)
  m.handle_http(
    config,
    http.HttpRequest(..req, headers: [
      #("extra", string.repeat("x", 16_385)),
      ..req.headers
    ]),
  ).status
  |> should.equal(400)
  let bad = "{\"jsonrpc\":\"2.0\",\"id\":null,\"method\":\"tools/list\"}"
  m.handle_http(config, request(bad, token)).status |> should.equal(400)
  let assert Ok(state) = authority.get(owner, 500)
  state.phase |> should.equal(authority.NoGrant)
}

fn different_candidate(i: intent.Intent) -> intent.Intent {
  let assert Ok(other) =
    intent.new(intent.Proposal(
      intent.Digests(..intent.bindings(i), candidate: dg("9")),
      intent.execution(i),
      intent.host(i),
      intent.boot(i),
      intent.clock_domain(i),
      intent.runtime_resource(i),
      intent.runtime_epoch(i),
      "other-candidate",
      intent.Window(
        intent.created_utc_ms(i),
        intent.expires_utc_ms(i),
        intent.created_mono_ms(i),
        intent.expires_mono_ms(i),
      ),
    ))
  other
}

pub fn actual_owner_candidate_binding_survives_registry_reload_test() {
  let #(ac, a, receipts, token, _) = native_fixture.fixture(30_000)
  let b = different_candidate(a)
  let effects = process.new_subject()
  let assert Ok(owner) =
    authority.start(
      ac,
      authority.Boundary(fn(_, _) { Ok(Nil) }, fn(h) {
        process.send(effects, authority.handoff_intent(h))
        Ok(Nil)
      }),
    )
  let hc =
    auth.AuthConfig(
      [origin],
      origin <> "/issuer",
      origin <> "/release",
      "release:control",
      secret,
    )
  let ex = intent.execution(a)
  let bindings = [#(ex.worker, "operator-subject")]
  // Different semantic intents may not share one owner in a registry.
  m.configure(
    ac.identity,
    hc,
    ac.host,
    ac.boot,
    ac.clock_domain,
    [m.Prepared(a, owner.data), m.Prepared(b, owner.data)],
    bindings,
    3000,
  )
  |> result.is_error
  |> should.be_true
  let assert Ok(_) = authority.issue(owner.data, token, a, receipts, 3000)
  // A replaced/reloaded registry can nevertheless contain ONLY B. Native owner
  // atomic expected-digest checks, not registry uniqueness or a prior get,
  // must prevent commands for B from using the already issued A session.
  let assert Ok(config_b) =
    m.configure(
      ac.identity,
      hc,
      ac.host,
      ac.boot,
      ac.clock_domain,
      [m.Prepared(b, owner.data)],
      bindings,
      3000,
    )
  let headers =
    request("", token).headers
    |> list.map(fn(h) {
      case h.0 == "authorization" {
        True -> #(
          h.0,
          "Bearer "
            <> transport_token(
            ex.worker,
            ex.workspace,
            authority.host_clock().utc_ms,
          ),
        )
        False -> h
      }
    })
  let dg_b = #("intent_digest", json.string(intent.digest(b)))
  list.each(
    [
      rpc("release_status", [dg_b]),
      rpc("release_step", [
        dg_b,
        #("epoch", json.string("1")),
        #("generation", json.string("0")),
        #("command", json.string("stage")),
        #("index", json.string("0")),
      ]),
      rpc("release_revoke", [dg_b, #("reason", json.string("operator_revoked"))]),
    ],
    fn(body) {
      let reply =
        m.handle_http(config_b, http.HttpRequest("POST", "/mcp", headers, body))
      has(reply, "RELEASE_OWNER_HOLD_RECONCILE")
    },
  )
  let assert Ok(view) = authority.get(owner.data, 1000)
  view.phase |> should.equal(authority.GrantRecorded)
  view.dispatch_handoffs |> should.equal(0)
  view.revocation_requested |> should.be_false
  // Positive control: the genuine session's candidate still dispatches once.
  let assert Ok(_) =
    authority.dispatch(
      owner.data,
      token,
      intent.digest(a),
      authority.Step(1, 0, store.Stage),
      3000,
    )
  let assert Ok(actual) = process.receive(effects, 1000)
  intent.digest(actual) |> should.equal(intent.digest(a))
}
