//// Explicit preparation ingress; transport identity and OIDC identity are both
//// required. Configuration/registry provenance and production admission remain
//// external. No default configuration, grant constructor, secrets or raw errors.

import cepaf_gleam/ecology/release_approval as approval
import cepaf_gleam/ecology/release_authority as authority
import cepaf_gleam/ecology/release_identity as identity
import cepaf_gleam/ecology/release_intent as intent
import cepaf_gleam/ecology/release_store as store
import cepaf_gleam/harness/files
import cepaf_gleam/harness/value as v
import cepaf_gleam/mcp/http_auth as auth
import cepaf_gleam/mcp/json_guard
import cepaf_gleam/mcp/principal
import cepaf_gleam/mcp/transports/http
import cepaf_gleam/mcp/transports/zenoh
import cepaf_gleam/mcp/types
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub const maximum_body_bytes = 65_536

pub type Prepared {
  Prepared(request: intent.Intent, owner: Subject(authority.Message))
}

pub opaque type Configuration {
  Configuration(
    identity: identity.Configuration,
    http: auth.AuthConfig,
    host: String,
    boot: String,
    clock_domain: String,
    prepared: List(Prepared),
    subjects: List(#(String, String)),
    within: Int,
  )
}

pub fn configure(
  id: identity.Configuration,
  http_config: auth.AuthConfig,
  host: String,
  boot: String,
  clock_domain: String,
  prepared: List(Prepared),
  subjects: List(#(String, String)),
  within: Int,
) -> Result(Configuration, String) {
  let ps = list.take(prepared, 17)
  let ss = list.take(subjects, 17)
  let valid =
    ps != []
    && list.length(ps) <= 16
    && ss != []
    && list.length(ss) <= 16
    && within >= 1
    && within <= 5000
    && string.byte_size(http_config.signing_secret) >= 32
    && string.byte_size(http_config.signing_secret) <= 256
    && http_config.approved_origins != []
    && list.length(list.take(http_config.approved_origins, 17)) <= 16
    && list.all(http_config.approved_origins, identity.tailnet_issuer)
    && identity.tailnet_issuer(http_config.expected_issuer)
    && identity.tailnet_issuer(http_config.expected_audience)
    && http_config.required_scope != ""
    && unique(list.map(ps, fn(p) { intent.digest(p.request) }))
    && unique_owners(ps)
    && unique(list.map(ss, fn(s) { s.0 }))
    && unique(list.map(ss, fn(s) { s.1 }))
    && list.all(ss, fn(s) { bounded(s.0, 256) && bounded(s.1, 256) })
    && list.all(ps, fn(p) {
      intent.host(p.request) == host
      && intent.boot(p.request) == boot
      && intent.clock_domain(p.request) == clock_domain
      && list.any(ss, fn(s) { s.0 == intent.execution(p.request).worker })
    })
  case valid {
    True ->
      Ok(Configuration(
        id,
        http_config,
        host,
        boot,
        clock_domain,
        ps,
        ss,
        within,
      ))
    False -> Error("RELEASE_CONFIGURATION_REFUSED")
  }
}

fn bounded(s: String, cap: Int) -> Bool {
  string.byte_size(s) > 0
  && string.byte_size(s) <= cap
  && list.all(string.to_utf_codepoints(s), fn(c) {
    let n = string.utf_codepoint_to_int(c)
    n >= 32 && n != 127
  })
}

fn unique(xs: List(String)) -> Bool {
  case xs {
    [] -> True
    [x, ..rest] -> !list.contains(rest, x) && unique(rest)
  }
}

fn unique_owners(ps: List(Prepared)) -> Bool {
  case ps {
    [] -> True
    [p, ..rest] ->
      !list.any(rest, fn(other) { other.owner == p.owner })
      && unique_owners(rest)
  }
}

fn object(
  value: v.Value,
  required: List(String),
  optional: List(String),
) -> Result(List(#(String, v.Value)), String) {
  case value {
    v.Object(fields) ->
      case
        list.length(fields) <= list.length(required) + list.length(optional)
        && list.all(required, fn(k) { list.any(fields, fn(f) { f.0 == k }) })
        && list.all(fields, fn(f) {
          list.contains(required, f.0) || list.contains(optional, f.0)
        })
      {
        True -> Ok(fields)
        False -> Error("RELEASE_INVALID_REQUEST")
      }
    _ -> Error("RELEASE_INVALID_REQUEST")
  }
}

fn text(value: v.Value, key: String, cap: Int) -> Result(String, String) {
  case v.get(value, key) {
    Ok(v.Text(s)) ->
      case bounded(s, cap) {
        True -> Ok(s)
        False -> Error("RELEASE_INVALID_REQUEST")
      }
    _ -> Error("RELEASE_INVALID_REQUEST")
  }
}

type Request {
  Request(
    id: v.Value,
    method: String,
    name: String,
    args: v.Value,
    token: Option(String),
  )
}

fn decode(raw: String) -> Result(Request, String) {
  use _ <- result.try(case string.byte_size(raw) <= maximum_body_bytes {
    True -> Ok(Nil)
    False -> Error("RELEASE_BODY_BOUND")
  })
  use root <- result.try(
    json_guard.native_inspect(raw, 12)
    |> result.replace_error("RELEASE_INVALID_REQUEST"),
  )
  use _ <- result.try(object(root, ["jsonrpc", "method"], ["id", "params"]))
  use _ <- result.try(case v.get(root, "jsonrpc") == Ok(v.Text("2.0")) {
    True -> Ok(Nil)
    False -> Error("RELEASE_INVALID_REQUEST")
  })
  use method <- result.try(text(root, "method", 64))
  use id <- result.try(case v.get(root, "id") {
    Ok(v.Text(s)) if s != "" ->
      case string.byte_size(s) <= 128 {
        True -> Ok(v.Text(s))
        False -> Error("RELEASE_INVALID_REQUEST")
      }
    Ok(v.Integer(n)) if n >= 0 && n <= 9_007_199_254_740_991 -> Ok(v.Integer(n))
    Error(_) if method == "notifications/initialized" -> Ok(v.Null)
    _ -> Error("RELEASE_INVALID_REQUEST")
  })
  let params = v.get(root, "params") |> result.unwrap(v.Object([]))
  use token <- result.try(case v.get(params, "_meta") {
    Error(_) -> Ok(None)
    Ok(meta) -> {
      use _ <- result.try(object(meta, ["release_oidc_token"], []))
      text(meta, "release_oidc_token", 16_384) |> result.map(Some)
    }
  })
  case method {
    "notifications/initialized" -> {
      use _ <- result.try(object(params, [], ["_meta"]))
      case id {
        v.Null -> Ok(Request(id, method, "", v.Object([]), token))
        _ -> Error("RELEASE_INVALID_REQUEST")
      }
    }
    "initialize" -> {
      use _ <- result.try(
        object(params, ["protocolVersion", "clientInfo", "capabilities"], [
          "_meta",
        ]),
      )
      use _ <- result.try(
        case v.get(params, "protocolVersion") == Ok(v.Text("2026-07-28")) {
          True -> Ok(Nil)
          False -> Error("RELEASE_PROTOCOL_REFUSED")
        },
      )
      use client <- result.try(v.get(params, "clientInfo"))
      use _ <- result.try(object(client, ["name", "version"], []))
      use _ <- result.try(text(client, "name", 128))
      use _ <- result.try(text(client, "version", 64))
      use caps <- result.try(v.get(params, "capabilities"))
      use _ <- result.try(object(caps, [], []))
      Ok(Request(id, method, "", v.Object([]), token))
    }
    "tools/list" -> {
      use _ <- result.try(object(params, [], ["_meta"]))
      Ok(Request(id, method, "", v.Object([]), token))
    }
    "tools/call" -> {
      use _ <- result.try(object(params, ["name", "arguments"], ["_meta"]))
      use name <- result.try(text(params, "name", 64))
      use args <- result.try(v.get(params, "arguments"))
      use _ <- result.try(validate_args(name, args))
      Ok(Request(id, method, name, args, token))
    }
    _ -> Error("RELEASE_METHOD_REFUSED")
  }
}

fn argument_keys(name: String) -> Result(List(String), String) {
  case name {
    "release_status" | "release_intent" -> Ok(["intent_digest"])
    "release_issue" ->
      Ok(["intent_digest", "operator_receipt", "codex_receipt", "agy_receipt"])
    "release_step" ->
      Ok(["intent_digest", "epoch", "generation", "command", "index"])
    "release_revoke" -> Ok(["intent_digest", "reason"])
    _ -> Error("RELEASE_TOOL_REFUSED")
  }
}

fn validate_args(name: String, args: v.Value) -> Result(Nil, String) {
  use keys <- result.try(argument_keys(name))
  use fields <- result.try(object(args, keys, []))
  case
    list.all(fields, fn(f) {
      case f.1 {
        v.Text(s) -> bounded(s, 16_384)
        _ -> False
      }
    })
  {
    True -> Ok(Nil)
    False -> Error("RELEASE_INVALID_ARGUMENTS")
  }
}

fn authorize(
  config: Configuration,
  p: principal.Principal,
  token: String,
) -> Result(identity.Identity, String) {
  let now = authority.host_clock()
  use proof <- result.try(
    identity.authenticate(
      config.identity,
      token,
      config.host,
      config.boot,
      config.clock_domain,
      now.utc_ms,
      now.mono_ms,
    )
    |> result.replace_error("RELEASE_IDENTITY_REFUSED"),
  )
  case
    list.any(config.subjects, fn(s) {
      s.0 == principal.actor_id(p) && s.1 == identity.subject(proof)
    })
  {
    True -> Ok(proof)
    False -> Error("RELEASE_IDENTITY_BINDING_REFUSED")
  }
}

fn prepared(
  config: Configuration,
  p: principal.Principal,
  args: v.Value,
) -> Result(Prepared, String) {
  use dg <- result.try(text(args, "intent_digest", 64))
  use entry <- result.try(
    list.find(config.prepared, fn(p) { intent.digest(p.request) == dg })
    |> result.replace_error("RELEASE_INTENT_UNKNOWN"),
  )
  let ex = intent.execution(entry.request)
  case
    ex.worker == principal.actor_id(p)
    && ex.workspace == principal.workspace_root(p)
  {
    True -> Ok(entry)
    False -> Error("RELEASE_SCOPE_REFUSED")
  }
}

fn number(
  args: v.Value,
  key: String,
  lower: Int,
  upper: Int,
) -> Result(Int, String) {
  use raw <- result.try(text(args, key, 16))
  use n <- result.try(
    int.parse(raw) |> result.replace_error("RELEASE_INVALID_ARGUMENTS"),
  )
  case n >= lower && n <= upper && int.to_string(n) == raw {
    True -> Ok(n)
    False -> Error("RELEASE_INVALID_ARGUMENTS")
  }
}

fn command(args: v.Value) -> Result(store.Command, String) {
  use name <- result.try(text(args, "command", 32))
  use index <- result.try(number(args, "index", 0, 14))
  case name, index {
    "stage", 0 -> Ok(store.Stage)
    "fence_readers", 0 -> Ok(store.FenceReaders)
    "replace", n -> Ok(store.Replace(n))
    "verify_candidate", 0 -> Ok(store.VerifyCandidate)
    "restore", n -> Ok(store.Restore(n))
    "verify_previous", 0 -> Ok(store.VerifyPrevious)
    "resume_readers", 0 -> Ok(store.ResumeReaders)
    _, _ -> Error("RELEASE_INVALID_ARGUMENTS")
  }
}

fn reason(args: v.Value) -> Result(store.RevokeReason, String) {
  use r <- result.try(text(args, "reason", 32))
  case r {
    "operator_revoked" -> Ok(store.OperatorRevoked)
    "owner_changed" -> Ok(store.OwnerChanged)
    "candidate_changed" -> Ok(store.CandidateChanged)
    "evidence_stale" -> Ok(store.EvidenceStale)
    "expired" -> Ok(store.RevokeExpired)
    "cancelled" -> Ok(store.Cancelled)
    "containment" -> Ok(store.Containment)
    _ -> Error("RELEASE_INVALID_ARGUMENTS")
  }
}

fn snapshot(s: authority.Snapshot) -> json.Json {
  let phase = case s.phase {
    authority.NoGrant -> "no_grant"
    authority.Preparing -> "preparing"
    authority.GrantRecorded -> "recorded"
    authority.Checking -> "checking"
    authority.Dispatching -> "dispatching"
    authority.Stopped -> "stopped"
    authority.Held(_) -> "held"
  }
  json.object([
    #("phase", json.string(phase)),
    #("intent_digest", case s.intent_digest {
      Some(digest) -> json.string(digest)
      None -> json.null()
    }),
    #("generation", json.int(s.generation)),
    #("dispatch_handoffs", json.int(s.dispatch_handoffs)),
    #("revocation_requested", json.bool(s.revocation_requested)),
    #("application_admitted", json.bool(False)),
    #("system_admitted", json.bool(False)),
  ])
}

fn execute(
  config: Configuration,
  p: principal.Principal,
  token: String,
  r: Request,
) -> Result(json.Json, String) {
  use proof <- result.try(authorize(config, p, token))
  case r.method {
    "notifications/initialized" -> Ok(json.object([]))
    "initialize" ->
      Ok(
        json.object([
          #("protocolVersion", json.string("2026-07-28")),
          #("capabilities", json.object([#("tools", json.object([]))])),
          #(
            "serverInfo",
            json.object([
              #("name", json.string("uos-release-preparation")),
              #("version", json.string("1")),
            ]),
          ),
        ]),
      )
    "tools/list" ->
      Ok(json.object([#("tools", json.array(tool_names(), tool_schema))]))
    _ -> {
      use entry <- result.try(prepared(config, p, r.args))
      // Recheck after decoding and registry lookup, before the actual owner call.
      let now = authority.host_clock()
      use _ <- result.try(
        case
          identity.still_valid(
            config.identity,
            proof,
            config.host,
            config.boot,
            config.clock_domain,
            now.utc_ms,
            now.mono_ms,
          )
        {
          True -> Ok(Nil)
          False -> Error("RELEASE_IDENTITY_EXPIRED")
        },
      )
      case r.name {
        "release_intent" ->
          Ok(
            json.object([
              #("intent_digest", json.string(intent.digest(entry.request))),
              #(
                "transaction_id",
                json.string(intent.transaction_id(entry.request)),
              ),
              #("candidate", json.string(intent.candidate(entry.request))),
              #("manifest", json.string(intent.manifest(entry.request))),
              #(
                "expires_utc_ms",
                json.int(intent.expires_utc_ms(entry.request)),
              ),
              #("application_admitted", json.bool(False)),
            ]),
          )
        _ -> {
          let response = case r.name {
            "release_status" ->
              authority.get_bound(
                entry.owner,
                intent.digest(entry.request),
                config.within,
              )
            "release_issue" -> {
              use op <- result.try(text(r.args, "operator_receipt", 8192))
              use co <- result.try(text(r.args, "codex_receipt", 8192))
              use ag <- result.try(text(r.args, "agy_receipt", 8192))
              authority.issue(
                entry.owner,
                token,
                entry.request,
                [
                  approval.Receipt(approval.Operator, op),
                  approval.Receipt(approval.Codex, co),
                  approval.Receipt(approval.Agy, ag),
                ],
                config.within,
              )
            }
            "release_step" -> {
              use epoch <- result.try(number(
                r.args,
                "epoch",
                1,
                9_000_000_000_000_000,
              ))
              use gen <- result.try(number(
                r.args,
                "generation",
                0,
                9_000_000_000_000_000,
              ))
              use cmd <- result.try(command(r.args))
              authority.dispatch(
                entry.owner,
                token,
                intent.digest(entry.request),
                authority.Step(epoch, gen, cmd),
                config.within,
              )
            }
            "release_revoke" -> {
              use why <- result.try(reason(r.args))
              authority.revoke(
                entry.owner,
                token,
                intent.digest(entry.request),
                why,
                config.within,
              )
            }
            _ -> Error("RELEASE_TOOL_REFUSED")
          }
          // A timeout can follow a durable consume. The ingress cannot decide
          // that no effect occurred, and must not advertise a safe retry.
          response
          |> result.map(snapshot)
          |> result.replace_error("RELEASE_OWNER_HOLD_RECONCILE")
        }
      }
    }
  }
}

pub fn tool_names() -> List(String) {
  [
    "release_status",
    "release_intent",
    "release_issue",
    "release_step",
    "release_revoke",
  ]
}

fn tool_schema(name: String) -> json.Json {
  let keys = argument_keys(name) |> result.unwrap([])
  json.object([
    #("name", json.string(name)),
    #(
      "description",
      json.string("Explicit configured release preparation; no admission"),
    ),
    #(
      "inputSchema",
      json.object([
        #("type", json.string("object")),
        #("additionalProperties", json.bool(False)),
        #(
          "properties",
          json.object(
            list.map(keys, fn(k) {
              #(k, json.object([#("type", json.string("string"))]))
            }),
          ),
        ),
        #("required", json.array(keys, json.string)),
      ]),
    ),
  ])
}

fn rpc(r: Request, answer: Result(json.Json, String)) -> String {
  let content = case answer {
    Ok(j) ->
      case r.method {
        "tools/call" -> [
          #(
            "result",
            json.object([
              #(
                "content",
                json.array(
                  [
                    json.object([
                      #("type", json.string("text")),
                      #("text", json.string(json.to_string(j))),
                    ]),
                  ],
                  fn(x) { x },
                ),
              ),
              #("isError", json.bool(False)),
            ]),
          ),
        ]
        _ -> [#("result", j)]
      }
    Error(code) -> [
      #(
        "error",
        json.object([
          #("code", json.int(-32_001)),
          #("message", json.string(code)),
        ]),
      ),
    ]
  }
  json.object([
    #("jsonrpc", json.string("2.0")),
    #("id", v.encode(r.id)),
    ..content
  ])
  |> json.to_string
}

fn refusal(status: Int, code: String) -> http.HttpResponse {
  http.HttpResponse(
    status,
    [#("content-type", "application/json"), ..http.security_headers()],
    json.object([#("error", json.string(code))]) |> json.to_string,
  )
}

pub fn unavailable() -> http.HttpResponse {
  refusal(503, "RELEASE_UNCONFIGURED")
}

pub fn handle_http(
  config: Configuration,
  req: http.HttpRequest,
) -> http.HttpResponse {
  let hs = list.take(req.headers, 33)
  let headers_bounded =
    list.length(hs) <= 32
    && list.all(hs, fn(h) {
      string.byte_size(h.0) <= 128 && string.byte_size(h.1) <= 16_384
    })
  case
    headers_bounded
    && req.method == "POST"
    && req.path == "/mcp"
    && string.byte_size(req.body) <= maximum_body_bytes
  {
    False -> refusal(400, "RELEASE_REQUEST_REFUSED")
    True -> {
      let now = authority.host_clock()
      case
        http.prepare_standard(
          req,
          config.http,
          types.Modern20260728,
          now.utc_ms,
        )
      {
        Error(reply) -> reply
        Ok(#(p, _, sse)) ->
          case decode(req.body), auth.header(req.headers, "uos-release-oidc") {
            Ok(r), Ok(token) if r.token == None -> {
              let answer = execute(config, p, token, r)
              case r.id, answer {
                v.Null, Ok(_) ->
                  http.HttpResponse(202, http.security_headers(), "")
                v.Null, Error(_) -> refusal(403, "RELEASE_IDENTITY_REFUSED")
                _, _ -> {
                  let body = rpc(r, answer)
                  http.HttpResponse(
                    200,
                    [
                      #("content-type", case sse {
                        True -> "text/event-stream"
                        False -> "application/json"
                      }),
                      ..http.security_headers()
                    ],
                    case sse {
                      True -> "event: message\ndata: " <> body <> "\n\n"
                      False -> body
                    },
                  )
                }
              }
            }
            _, _ -> refusal(400, "RELEASE_REQUEST_REFUSED")
          }
      }
    }
  }
}

/// Existing authenticated Zenoh MCP profile carries the standard RPC reply as
/// its Complete value. No subscriptions are started by this pure handler.
pub fn handle_zenoh(
  config: Configuration,
  secret: String,
  subscriptions: Bool,
  client_id: String,
  envelope: zenoh.SignedZenohEnvelope,
) {
  use r <- result.try(
    decode(envelope.payload)
    |> result.replace_error(types.ToolError(
      "RELEASE_REQUEST_REFUSED",
      "Release request refused",
      types.NonRetryable,
    )),
  )
  zenoh.handle_envelope(
    secret,
    subscriptions,
    types.Modern20260728,
    client_id,
    envelope,
    fn(p, _) {
      let answer = case r.token {
        Some(token) -> execute(config, p, token, r)
        None -> Error("RELEASE_IDENTITY_REFUSED")
      }
      let body = rpc(r, answer)
      types.Complete(
        body,
        types.EvidenceRecord(
          "PREPARATION",
          "release",
          r.name,
          "configured",
          "implemented",
          "observed_handler",
          "UNVERIFIED",
          "NOT_ADMITTED",
          files.digest(body),
        ),
      )
    },
  )
}
