//// Track A: live gateway transport and immutable candidate regression tests.

import cepaf_gleam/mcp/adapters/planning_read
import cepaf_gleam/mcp/candidate_id
import cepaf_gleam/mcp/http_auth
import cepaf_gleam/mcp/principal
import cepaf_gleam/mcp/profiles/modern
import cepaf_gleam/mcp/runtime_gateway as gateway
import cepaf_gleam/mcp/server
import cepaf_gleam/mcp/subscriptions
import cepaf_gleam/mcp/supervisor
import cepaf_gleam/mcp/task_extension
import cepaf_gleam/mcp/transports/zenoh
import cepaf_gleam/mcp/types
import cepaf_gleam/mcp/version
import cepaf_gleam/mcp/wire
import cepaf_gleam/web/server as web_server
import gleam/dict
import gleam/dynamic/decode
import gleam/erlang/atom
import gleam/erlang/process
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import simplifile

@external(erlang, "mcp_stdio_ffi", "run_workspace_bounded_cd")
fn workspace_command(
  path: String,
  args: List(String),
  cwd: String,
  timeout_ms: Int,
) -> Result(#(Int, String), String)

@external(erlang, "cepaf_gleam_ffi", "system_time_nanos")
fn fixture_time() -> Int

pub fn workspace_subprocess_accepts_workspace_and_absolute_temp_cwd_test() {
  workspace_command("/usr/bin/pwd", [], root, 3000)
  |> should.equal(Ok(#(0, root <> "\n")))
  let temporary = "/tmp/uos-c04-workspace-" <> int.to_string(fixture_time())
  let assert Ok(Nil) = simplifile.create_directory(temporary)
  let output = workspace_command("/usr/bin/pwd", [], temporary, 3000)
  let assert Ok(Nil) = simplifile.delete(temporary)
  output |> should.equal(Ok(#(0, temporary <> "\n")))
}

pub fn workspace_subprocess_rejects_invalid_cwd_and_time_bounds_test() {
  list.each(["relative", root <> "/../uos", "/does-not-exist/uos-c04"], fn(cwd) {
    workspace_command("/usr/bin/pwd", [], cwd, 3000)
    |> should.equal(Error("backend_spawn_failed"))
  })
  list.each([0, -1, 60_001], fn(timeout_ms) {
    workspace_command("/usr/bin/pwd", [], root, timeout_ms)
    |> should.equal(Error("invalid_resource_bound"))
  })
  workspace_command("/usr/bin/printf", ["%s", "arg;$(literal)"], root, 3000)
  |> should.equal(Ok(#(0, "arg;$(literal)")))
}

pub fn workspace_subprocess_bounds_timeout_output_and_preserves_exit_code_test() {
  workspace_command("/usr/bin/sleep", ["1"], root, 80)
  |> should.equal(Error("timeout"))
  workspace_command("/usr/bin/false", [], root, 3000)
  |> should.equal(Ok(#(1, "")))
  workspace_command("/usr/bin/head", ["-c", "1048576", "/dev/zero"], root, 3000)
  |> fn(output) {
    let assert Ok(#(0, bytes)) = output
    string.byte_size(bytes) |> should.equal(1_048_576)
  }
  let overflow =
    workspace_command(
      "/usr/bin/head",
      ["-c", "1048577", "/dev/zero"],
      root,
      3000,
    )
  case overflow {
    Error("backend_output_or_process_failure") | Error("output_limit") -> Nil
    _ -> panic as "Output overflow must fail closed"
  }
}

@external(erlang, "cepaf_gleam_ffi", "get_env")
fn get_env(key: String) -> Result(String, Nil)

const root = "/home/an/NAS-setup/uos"

const now = 100_000

const origin = "https://nas-1.tail55d152.ts.net:4101"

pub fn modern_revision_initialize_and_http_followup_test() {
  version.matches_profile(types.Legacy20241105, "2024-11-05") |> should.be_true
  version.matches_profile(types.Modern20260728, "2024-11-05") |> should.be_false
  list.each(["", "2025-01-01", "2026-07-28suffix"], fn(rev) {
    version.matches_profile(types.Legacy20241105, rev) |> should.be_false
    version.matches_profile(types.Modern20260728, rev) |> should.be_false
  })
  list.each(["2025-03-26", "2025-06-18", "2025-11-25", "2026-07-28"], fn(rev) {
    version.negotiate(rev) |> should.equal(Ok(types.Modern20260728))
    version.matches_profile(types.Modern20260728, rev) |> should.be_true
    version.matches_profile(types.Legacy20241105, rev) |> should.be_false
    let assert Ok(initialized) = modern.initialize("codex", "1", rev)
    json.parse(initialized, decode.at(["protocolVersion"], decode.string))
    |> should.equal(Ok(rev))
    let hs =
      list.map(authenticated_headers(), fn(h) {
        case h.0 {
          "Mcp-Protocol-Version" -> #(h.0, rev)
          _ -> h
        }
      })
    list.each(["initialize", "tools/list", "discovery/list"], fn(method) {
      let raw =
        json.object([
          #("jsonrpc", json.string("2.0")),
          #("id", json.int(81)),
          #("method", json.string(method)),
          #("params", json.object([#("protocolVersion", json.string(rev))])),
        ])
        |> json.to_string
      let #(status, _, body) =
        gateway.handle_http_with_config("POST", "/mcp", hs, raw, config(), now)
      status |> should.equal(200)
      json.parse(body, decode.at(["error"], decode.dynamic)) |> should.be_error
      let assert Ok(payload) =
        json.parse(body, decode.at(["result", "value"], decode.string))
      case method {
        "initialize" ->
          json.parse(payload, decode.at(["protocolVersion"], decode.string))
          |> should.equal(Ok(rev))
        _ -> string.contains(payload, "tools") |> should.be_true
      }
    })
  })
  let hs =
    list.map(authenticated_headers(), fn(h) {
      case h.0 {
        "Mcp-Protocol-Version" -> #(h.0, "2025-06-18")
        _ -> h
      }
    })
  let #(status, _, body) =
    gateway.handle_http_with_config(
      "POST",
      "/mcp",
      hs,
      "{\"id\":82,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2026-07-28\"}}",
      config(),
      now,
    )
  status |> should.equal(400)
  string.contains(body, "HEADER_BODY_MISMATCH") |> should.be_true
}

pub fn resource_metadata_challenge_uses_resource_origin_test() {
  list.each(
    [
      #(origin <> "/mcp", "https://idp.tail55d152.ts.net", origin),
      #(
        origin <> "/nested/mcp/",
        "https://idp.tail55d152.ts.net/issuer/",
        origin,
      ),
      #(origin, "https://idp.tail55d152.ts.net", origin),
      #(
        "http://nas-1.tail55d152.ts.net:4100/mcp/",
        "https://idp.tail55d152.ts.net",
        "http://nas-1.tail55d152.ts.net:4100",
      ),
      #(
        "not-a-url",
        "https://idp.tail55d152.ts.net/issuer/",
        "https://idp.tail55d152.ts.net",
      ),
      #(
        "https:///missing-authority",
        "https://idp.tail55d152.ts.net/issuer/",
        "https://idp.tail55d152.ts.net",
      ),
      #("invalid", "invalid", ""),
    ],
    fn(case_data) {
      let cfg =
        http_auth.AuthConfig(
          ..config(),
          expected_audience: case_data.0,
          expected_issuer: case_data.1,
        )
      let #(status, hs, _) =
        gateway.handle_http_with_config(
          "POST",
          "/mcp",
          headers(),
          request("initialize"),
          cfg,
          now,
        )
      status |> should.equal(401)
      http_auth.header(hs, "www-authenticate")
      |> should.equal(Ok(
        "Bearer resource_metadata=\""
        <> case_data.2
        <> "/.well-known/oauth-protected-resource\"",
      ))
    },
  )
}

fn test_principal(actor: String, session: String) -> principal.Principal {
  principal.from_launcher_env(
    actor,
    types.ClientProfile("codex"),
    root,
    session,
  )
}

fn fixture() -> gateway.GatewayState {
  let assert Ok(pool) =
    supervisor.start_worker_pool_for_candidate(1, candidate_id.from_root(root))
  let assert Ok(supervised) = supervisor.start_supervised_gateway()
  let state =
    gateway.new_state(root, candidate_id.from_root(root), pool, supervised)
  let backends =
    server.ServerBackends(
      ..state.backends,
      planning_read: planning_read.AvailableStore("fixture-plan", [
        planning_read.CanonicalTaskRow(
          "fixture-plan",
          "running",
          "fixture only",
          "executing",
          "task-owner",
          7,
        ),
        planning_read.CanonicalTaskRow(
          "fixture-plan",
          "fresh",
          "fixture only",
          "executing",
          "task-owner",
          7,
        ),
      ]),
    )
  gateway.GatewayState(..state, backends: backends)
}

fn transition(
  state: gateway.GatewayState,
  p: principal.Principal,
  method: String,
  params: json.Json,
) -> #(types.Outcome, gateway.GatewayState) {
  let raw =
    json.object([
      #("jsonrpc", json.string("2.0")),
      #("id", json.int(99)),
      #("method", json.string(method)),
      #("params", params),
    ])
    |> json.to_string
  let assert Ok(msg) = wire.decode_request(types.Modern20260728, raw)
  gateway.dispatch_normalized(
    state,
    p,
    types.Modern20260728,
    "public",
    raw,
    msg,
    now,
  )
}

fn completed(outcome: types.Outcome) -> String {
  let assert types.Complete(body, _) = outcome
  body
}

fn refusal(outcome: types.Outcome, code: String) {
  let assert types.Refused(error) = outcome
  error.code |> should.equal(code)
}

fn negotiate_tasks(
  state: gateway.GatewayState,
  p: principal.Principal,
  capabilities: json.Json,
) -> gateway.GatewayState {
  let #(outcome, state) =
    transition(
      state,
      p,
      "initialize",
      json.object([
        #("protocolVersion", json.string("2026-07-28")),
        #("capabilities", capabilities),
      ]),
    )
  completed(outcome) |> string.contains("2026-07-28") |> should.be_true
  state
}

fn task_params(task: String) -> json.Json {
  json.object([
    #("planId", json.string("fixture-plan")),
    #("taskId", json.string(task)),
  ])
}

pub fn task_extension_requires_real_session_negotiation_and_runs_lifecycle_test() {
  let p = test_principal("task-owner", "tasks-negotiated")
  let initial = fixture()
  let #(before, untouched) =
    transition(initial, p, "tasks/create", task_params("running"))
  refusal(before, "TASK_EXTENSION_NOT_NEGOTIATED")
  task_extension.size(untouched.tasks) |> should.equal(0)
  let negotiated =
    negotiate_tasks(initial, p, json.object([#("tasks", json.object([]))]))
  let #(created, state) =
    transition(negotiated, p, "tasks/create", task_params("running"))
  let assert Ok(handle) =
    json.parse(completed(created), decode.at(["handleId"], decode.string))
  handle |> should.equal("fixture-plan:running:7")
  task_extension.has_handle(state.tasks, handle) |> should.be_true
  let params = json.object([#("handleId", json.string(handle))])
  list.each(["tasks/get", "tasks/result"], fn(method) {
    let #(outcome, _) = transition(state, p, method, params)
    json.parse(completed(outcome), decode.at(["state"], decode.string))
    |> should.equal(Ok("running"))
    let #(foreign, _) =
      transition(state, test_principal("foreign", "foreign"), method, params)
    refusal(foreign, "CROSS_PRINCIPAL_TASK_HANDLE_FORBIDDEN")
  })
  let #(foreign_cancel, _) =
    transition(
      state,
      test_principal("foreign", "foreign"),
      "tasks/cancel",
      params,
    )
  refusal(foreign_cancel, "CROSS_PRINCIPAL_TASK_HANDLE_FORBIDDEN")
  let #(cancelled, state) = transition(state, p, "tasks/cancel", params)
  let body = completed(cancelled)
  json.parse(body, decode.at(["cancelAcknowledged"], decode.bool))
  |> should.equal(Ok(True))
  json.parse(body, decode.at(["effectStopped"], decode.bool))
  |> should.equal(Ok(False))
  let #(after, _) = transition(state, p, "tasks/get", params)
  json.parse(completed(after), decode.at(["state"], decode.string))
  |> should.equal(Ok("cancel_requested"))
  let #(other_session, _) =
    transition(
      state,
      test_principal("task-owner", "tasks-other-session"),
      "tasks/create",
      task_params("fresh"),
    )
  refusal(other_session, "TASK_EXTENSION_NOT_NEGOTIATED")
}

pub fn task_capability_false_null_missing_and_experimental_test() {
  let p = test_principal("task-owner", "tasks-capability-shapes")
  let initial = fixture()
  list.each(
    [
      json.object([]),
      json.object([#("tasks", json.bool(False))]),
      json.object([#("tasks", json.null())]),
      json.object([
        #("experimental", json.object([#("tasks", json.bool(False))])),
      ]),
      json.object([#("experimental", json.object([#("tasks", json.null())]))]),
    ],
    fn(caps) {
      let state = negotiate_tasks(initial, p, caps)
      let #(outcome, _) =
        transition(state, p, "tasks/create", task_params("running"))
      refusal(outcome, "TASK_EXTENSION_NOT_NEGOTIATED")
    },
  )
  let state =
    negotiate_tasks(
      initial,
      p,
      json.object([
        #("experimental", json.object([#("tasks", json.object([]))])),
      ]),
    )
  let #(created, _) =
    transition(state, p, "tasks/create", task_params("running"))
  completed(created)
  |> string.contains("fixture-plan:running:7")
  |> should.be_true
  let state = negotiate_tasks(state, p, json.object([]))
  let #(reset, _) = transition(state, p, "tasks/create", task_params("running"))
  refusal(reset, "TASK_EXTENSION_NOT_NEGOTIATED")
}

pub fn task_handle_capacity_refuses_new_but_allows_existing_test() {
  let p = test_principal("task-owner", "tasks-capacity")
  let state =
    negotiate_tasks(fixture(), p, json.object([#("tasks", json.object([]))]))
  let #(created, state) =
    transition(state, p, "tasks/create", task_params("running"))
  completed(created)
  |> string.contains("fixture-plan:running:7")
  |> should.be_true
  let record =
    task_extension.SaPlanTaskRecord(
      "fixture-plan",
      "filler",
      "task-owner",
      7,
      True,
      task_extension.RunningTask,
    )
  let full =
    int.range(1, task_extension.max_task_handles, state.tasks, fn(store, n) {
      task_extension.register(store, "filler:" <> int.to_string(n), record)
    })
  task_extension.size(full) |> should.equal(1024)
  let state = gateway.GatewayState(..state, tasks: full)
  let #(refused, next) =
    transition(state, p, "tasks/create", task_params("fresh"))
  refusal(refused, "TASK_HANDLE_CAPACITY_EXCEEDED")
  next.tasks |> should.equal(full)
  let #(existing, next) =
    transition(state, p, "tasks/create", task_params("running"))
  completed(existing)
  |> string.contains("fixture-plan:running:7")
  |> should.be_true
  task_extension.size(next.tasks) |> should.equal(1024)
}

pub fn task_negotiation_session_store_is_bounded_test() {
  let state = fixture()
  let sessions =
    int.range(1, 1025, dict.new(), fn(store, n) {
      dict.insert(store, "session:" <> int.to_string(n), False)
    })
  let state = gateway.GatewayState(..state, negotiated_task_sessions: sessions)
  let params =
    json.object([
      #("protocolVersion", json.string("2026-07-28")),
      #("capabilities", json.object([#("tasks", json.object([]))])),
    ])
  let #(refused, next) =
    transition(
      state,
      test_principal("task-owner", "new-session"),
      "initialize",
      params,
    )
  refusal(refused, "TASK_NEGOTIATION_CAPACITY_EXCEEDED")
  next.negotiated_task_sessions |> should.equal(sessions)
  let #(existing, next) =
    transition(
      state,
      test_principal("task-owner", "session:1"),
      "initialize",
      params,
    )
  completed(existing) |> string.contains("2026-07-28") |> should.be_true
  dict.size(next.negotiated_task_sessions) |> should.equal(1024)
  dict.get(next.negotiated_task_sessions, "session:1") |> should.equal(Ok(True))
}

fn subscription_params(id: String) -> json.Json {
  json.object([
    #("uri", json.string("uos://governance/ev-provenance-ceiling")),
    #("subscriptionId", json.string(id)),
  ])
}

pub fn subscriptions_namespace_ids_and_roundtrip_through_live_gateway_test() {
  let raw =
    json.object([
      #("id", json.int(101)),
      #("method", json.string("resources/subscribe")),
      #("params", subscription_params("roundtrip")),
    ])
    |> json.to_string
  standard(raw)
  |> std_result("subscriptionId")
  |> should.equal(Ok("cutover-operator:roundtrip"))
  let raw =
    json.object([
      #("id", json.int(102)),
      #("method", json.string("resources/unsubscribe")),
      #("params", subscription_params("cutover-operator:roundtrip")),
    ])
    |> json.to_string
  json.parse(standard(raw), decode.at(["result", "unsubscribed"], decode.bool))
  |> should.equal(Ok(True))

  let a = test_principal("actor-a", "sub-a")
  let b = test_principal("actor-b", "sub-b")
  // B's attempt to reserve A's ID remains entirely within B's namespace.
  let #(squat, state) =
    transition(
      fixture(),
      b,
      "resources/subscribe",
      subscription_params("actor-a:shared"),
    )
  json.parse(completed(squat), decode.at(["subscriptionId"], decode.string))
  |> should.equal(Ok("actor-b:actor-a:shared"))
  let #(owned, state) =
    transition(state, a, "resources/subscribe", subscription_params("shared"))
  json.parse(completed(owned), decode.at(["subscriptionId"], decode.string))
  |> should.equal(Ok("actor-a:shared"))
  let #(unsquat, state) =
    transition(
      state,
      b,
      "resources/unsubscribe",
      subscription_params("actor-a:shared"),
    )
  completed(unsquat) |> string.contains("true") |> should.be_true
  subscriptions.read_subscription(
    state.subscriptions,
    types.Modern20260728,
    a,
    "actor-a:shared",
  )
  |> should.be_ok
  let #(unsubscribed, state) =
    transition(
      state,
      a,
      "resources/unsubscribe",
      subscription_params("actor-a:shared"),
    )
  completed(unsubscribed) |> string.contains("true") |> should.be_true
  dict.size(state.subscriptions.subscriptions) |> should.equal(0)
  let #(blank, state) =
    transition(state, a, "resources/subscribe", subscription_params("   "))
  json.parse(completed(blank), decode.at(["subscriptionId"], decode.string))
  |> should.equal(Ok("actor-a:uos://governance/ev-provenance-ceiling"))
  let #(removed, state) =
    transition(state, a, "resources/unsubscribe", subscription_params(""))
  completed(removed) |> string.contains("true") |> should.be_true
  dict.size(state.subscriptions.subscriptions) |> should.equal(0)
}

pub fn subscription_capacity_refuses_without_growing_and_can_recover_test() {
  let p = test_principal("actor-a", "sub-capacity")
  let full =
    int.range(
      1,
      subscriptions.max_subscriptions + 1,
      subscriptions.empty_store(),
      fn(store, n) {
        let assert Ok(next) =
          subscriptions.subscribe(
            store,
            types.Modern20260728,
            p,
            "actor-a:" <> int.to_string(n),
            subscriptions.ResourceSubscription(
              "uos://governance/ev-provenance-ceiling",
            ),
          )
        next
      },
    )
  dict.size(full.subscriptions) |> should.equal(1024)
  let state = gateway.GatewayState(..fixture(), subscriptions: full)
  let #(outcome, next) =
    transition(state, p, "resources/subscribe", subscription_params("new"))
  refusal(outcome, "SUBSCRIPTION_CAPACITY_EXCEEDED")
  let assert types.Refused(error) = outcome
  error.retryability |> should.equal(types.Retryable)
  next.subscriptions |> should.equal(full)
  let #(duplicate, _) =
    transition(state, p, "resources/subscribe", subscription_params("1"))
  refusal(duplicate, "SUBSCRIPTION_ID_ALREADY_EXISTS")
  let #(removed, state) =
    transition(state, p, "resources/unsubscribe", subscription_params("1"))
  completed(removed) |> string.contains("true") |> should.be_true
  let #(replacement, next) =
    transition(state, p, "resources/subscribe", subscription_params("new"))
  completed(replacement) |> string.contains("actor-a:new") |> should.be_true
  dict.size(next.subscriptions.subscriptions) |> should.equal(1024)
}

pub fn logging_completion_and_cancel_notification_live_wiring_test() {
  let logging =
    standard(
      "{\"id\":103,\"method\":\"logging/setLevel\",\"params\":{\"level\":\"info\"}}",
    )
  json.parse(logging, decode.at(["error"], decode.dynamic)) |> should.be_error
  let completion = standard(request("completion/complete"))
  json.parse(
    completion,
    decode.at(["result", "completion", "values"], decode.list(decode.string)),
  )
  |> should.equal(Ok([]))
  json.parse(
    completion,
    decode.at(["result", "completion", "hasMore"], decode.bool),
  )
  |> should.equal(Ok(False))
  gateway.handle_standard_mcp_line(
    "cutover-operator",
    "codex",
    root,
    "cutover-session",
    "public",
    "{\"method\":\"notifications/cancelled\",\"params\":{\"requestId\":103}}",
    now,
  )
  |> should.equal(None)
}

pub fn signed_zenoh_nul_and_json_depth_guards_test() {
  list.each(
    [
      #(
        "{\"id\":1,\"method\":\"ping\",\"data\":\"\u{0000}\"}",
        "ZENOH_NUL_BYTE_FORBIDDEN",
      ),
      #(
        "{\"id\":1,\"method\":\"ping\",\"data\":\"\\u0000\"}",
        "ZENOH_NUL_BYTE_FORBIDDEN",
      ),
      #(
        "{\"id\":1,\"method\":\"ping\",\"data\":"
          <> string.repeat("[", 33)
          <> "0"
          <> string.repeat("]", 33)
          <> "}",
        "ZENOH_JSON_DEPTH_EXCEEDED",
      ),
    ],
    fn(case_data) {
      let original = signed_envelope("cutover-zenoh-test-key")
      let envelope =
        zenoh.SignedZenohEnvelope(
          ..original,
          payload: case_data.0,
          signature: zenoh.compute_signature(
            "cutover-zenoh-test-key",
            original.topic,
            original.reply_topic,
            original.sender_actor,
            original.client_name,
            original.workspace_root,
            original.session_id,
            case_data.0,
          ),
        )
      let assert Error(error) =
        gateway.handle_zenoh_with_secret(
          "cutover-zenoh-test-key",
          "codex",
          types.Modern20260728,
          envelope,
          now,
        )
      error.code |> should.equal(case_data.1)
    },
  )
}

pub fn health_reports_loaded_code_digest_test() {
  let assert Ok(digest) =
    json.parse(
      gateway.gateway_health_json(),
      decode.at(["loaded_beam_sha256"], decode.string),
    )
  string.length(digest) |> should.equal(64)
  list.all(string.to_graphemes(digest), fn(c) {
    string.contains("0123456789abcdef", c)
  })
  |> should.be_true
}

@external(erlang, "mcp_stdio_ffi", "register_or_stop_supervisor")
fn register_or_stop(pid: process.Pid) -> Bool

@external(erlang, "erlang", "process_info")
fn process_links(
  pid: process.Pid,
  key: atom.Atom,
) -> #(atom.Atom, List(process.Pid))

pub fn losing_linked_boot_racer_cannot_kill_untrapping_caller_test() {
  gateway.ensure_started() |> should.be_true
  let reply = process.new_subject()
  let caller =
    process.spawn_unlinked(fn() {
      process.trap_exits(False)
      let dummy = process.spawn(fn() { process.sleep_forever() })
      let monitor = process.monitor(dummy)
      let #(_, before) = process_links(process.self(), atom.create("links"))
      before |> list.contains(dummy) |> should.be_true
      register_or_stop(dummy) |> should.be_false
      let #(_, after) = process_links(process.self(), atom.create("links"))
      after |> list.contains(dummy) |> should.be_false
      let down =
        process.new_selector()
        |> process.select_specific_monitor(monitor, fn(_) { True })
        |> process.selector_receive(2000)
      process.send(reply, down == Ok(True))
    })
  let monitor = process.monitor(caller)
  process.receive(reply, 4000) |> should.equal(Ok(True))
  process.new_selector()
  |> process.select_specific_monitor(monitor, fn(_) { True })
  |> process.selector_receive(1000)
  |> should.equal(Ok(True))
}

pub fn web_metadata_without_origin_has_no_unsolicited_cors_test() {
  let #(status, headers, body) =
    gateway.handle_http_with_config(
      "GET",
      "/.well-known/oauth-protected-resource",
      [],
      "",
      config(),
      now,
    )
  status |> should.equal(200)
  let response = web_server.apply_gateway_response([], status, headers, body)
  http_auth.header(response.headers, "access-control-allow-origin")
  |> should.be_error
  let duplicate =
    web_server.apply_gateway_response(
      [#("Origin", origin), #("origin", origin)],
      status,
      headers,
      body,
    )
  http_auth.header(duplicate.headers, "access-control-allow-origin")
  |> should.be_error
  let invalid =
    web_server.apply_gateway_response(
      [#("Origin", "https://outside.example")],
      status,
      headers,
      body,
    )
  http_auth.header(invalid.headers, "access-control-allow-origin")
  |> should.be_error
}

pub fn web_origin_policy_honors_configured_approved_origins_test() {
  let cfg = gateway.http_auth_config()
  list.each(
    [
      origin,
      "https://vm-1.tail55d152.ts.net:8443",
      "https://nas-99.tail55d152.ts.net:4101",
    ],
    fn(request_origin) {
      let response =
        web_server.apply_gateway_response(
          [#("Origin", request_origin)],
          200,
          [],
          "{}",
        )
      case http_auth.approved_origin(cfg, request_origin) {
        True ->
          http_auth.header(response.headers, "access-control-allow-origin")
          |> should.equal(Ok(request_origin))
        False ->
          http_auth.header(response.headers, "access-control-allow-origin")
          |> should.be_error
      }
    },
  )
}

fn config() -> http_auth.AuthConfig {
  http_auth.AuthConfig(
    [origin],
    origin,
    origin <> "/mcp",
    "mcp:operational",
    "cutover-test-signing-key",
  )
}

fn headers() -> List(#(String, String)) {
  [
    #("Origin", origin),
    #("Content-Type", "application/json"),
    #("Accept", "application/json"),
    #("Mcp-Protocol-Version", "2026-07-28"),
    #("Mcp-Session-Id", "cutover-session"),
  ]
}

fn authenticated_headers_with_scopes(
  scopes: List(String),
) -> List(#(String, String)) {
  let token =
    http_auth.sign_token(
      http_auth.TokenClaims(
        origin,
        origin <> "/mcp",
        "cutover-operator",
        "codex",
        root,
        "cutover-session",
        scopes,
        now - 1,
        now + 60_000,
      ),
      config().signing_secret,
    )
  [#("Authorization", "Bearer " <> token), ..headers()]
}

fn authenticated_headers() -> List(#(String, String)) {
  authenticated_headers_with_scopes(["mcp:operational"])
}

fn request(method: String) -> String {
  json.object([
    #("jsonrpc", json.string("2.0")),
    #("id", json.int(7)),
    #("method", json.string(method)),
  ])
  |> json.to_string
}

fn call(tool: String, args: List(#(String, String))) -> String {
  json.object([
    #("jsonrpc", json.string("2.0")),
    #("id", json.int(9)),
    #("method", json.string("tools/call")),
    #(
      "params",
      json.object([
        #("name", json.string(tool)),
        #(
          "arguments",
          json.object(list.map(args, fn(p) { #(p.0, json.string(p.1)) })),
        ),
      ]),
    ),
  ])
  |> json.to_string
}

fn standard(raw: String) -> String {
  let assert Some(body) =
    gateway.handle_standard_mcp_line(
      "cutover-operator",
      "codex",
      root,
      "cutover-session",
      "public",
      raw,
      now,
    )
  body
}

fn std_result(body: String, field: String) -> Result(String, json.DecodeError) {
  json.parse(body, decode.at(["result", field], decode.string))
}

fn http_payload(raw: String) -> String {
  let #(status, _, body) =
    gateway.handle_http_with_config(
      "POST",
      "/mcp",
      authenticated_headers(),
      raw,
      config(),
      now,
    )
  status |> should.equal(200)
  let assert Ok(payload) =
    json.parse(body, decode.at(["result", "value"], decode.string))
  payload
}

pub fn gateway_actor_is_idempotent_and_candidate_bound_test() {
  gateway.ensure_started() |> should.be_true
  gateway.ensure_started() |> should.be_true
  gateway.is_running() |> should.be_true
  let health = gateway.gateway_health_json()
  json.parse(health, decode.at(["status"], decode.string))
  |> should.equal(Ok("running"))
  json.parse(health, decode.at(["child_id"], decode.string))
  |> should.equal(Ok("mcp_unified_gateway"))
  json.parse(health, decode.at(["total_routes"], decode.int))
  |> should.equal(Ok(101))
  json.parse(health, decode.at(["application_admitted"], decode.bool))
  |> should.equal(Ok(False))
  let assert Ok(candidate) =
    json.parse(health, decode.at(["candidate"], decode.string))
  candidate_id.is_sha256_digest(candidate) |> should.be_true
  candidate |> should.equal(candidate_id.from_root(root))
}

pub fn http_metadata_is_available_without_signing_secret_test() {
  let cfg = http_auth.AuthConfig(..config(), signing_secret: "")
  let #(status, _, body) =
    gateway.handle_http_with_config(
      "GET",
      "/.well-known/oauth-protected-resource",
      [],
      "",
      cfg,
      now,
    )
  status |> should.equal(200)
  json.parse(body, decode.at(["resource"], decode.string))
  |> should.equal(Ok(origin <> "/mcp"))
  json.parse(
    body,
    decode.at(["authorization_servers"], decode.list(decode.string)),
  )
  |> should.equal(Ok([origin]))
  json.parse(
    body,
    decode.at(["bearer_methods_supported"], decode.list(decode.string)),
  )
  |> should.equal(Ok(["header"]))
}

pub fn http_authentication_refuses_missing_token_and_untrusted_origin_test() {
  let #(status, response_headers, _) =
    gateway.handle_http_with_config(
      "POST",
      "/mcp",
      headers(),
      request("initialize"),
      config(),
      now,
    )
  status |> should.equal(401)
  http_auth.header(response_headers, "www-authenticate") |> should.be_ok
  let bad = [
    #("Origin", "https://evil.example"),
    ..list.filter(authenticated_headers(), fn(p) { p.0 != "Origin" })
  ]
  let #(forbidden, _, _) =
    gateway.handle_http_with_config(
      "POST",
      "/mcp",
      bad,
      request("initialize"),
      config(),
      now,
    )
  forbidden |> should.equal(403)
  let #(no_secret, _, _) =
    gateway.handle_http_with_config(
      "POST",
      "/mcp",
      authenticated_headers(),
      request("initialize"),
      http_auth.AuthConfig(..config(), signing_secret: ""),
      now,
    )
  no_secret |> should.equal(401)
}

pub fn authenticated_http_dispatches_live_registries_and_backends_test() {
  http_payload(request("initialize"))
  |> string.contains("uos-mcp-unified-gateway")
  |> should.be_true
  let tools = http_payload(request("tools/list"))
  let assert Ok(definitions) =
    json.parse(tools, decode.at(["tools"], decode.list(decode.dynamic)))
  list.length(definitions) |> should.equal(53)
  http_payload(call("mcp_capability_inventory", []))
  |> string.contains("101")
  |> should.be_true
  http_payload(call("read_file", [#("path", "AGENTS.md")]))
  |> string.contains("Unified Operational System")
  |> should.be_true
  http_payload(
    call("sa_plan_status_for", [
      #("plan", "20261029-1913-mcp-server-completion"),
    ]),
  )
  |> string.contains("canonical_authority")
  |> should.be_true
  http_payload(call("system_health", []))
  |> string.contains("beam_otp29_live")
  |> should.be_true
  http_payload(request("resources/list"))
  |> string.contains("uos://system/mcp-gateway-health")
  |> should.be_true
  http_payload(request("prompts/list"))
  |> string.contains("uos_poodavr_review")
  |> should.be_true
}

pub fn canonical_stdio_both_profiles_and_split_frames_test() {
  list.each([types.Legacy20241105, types.Modern20260728], fn(profile) {
    let raw = call("mcp_capability_inventory", [])
    let assert Ok(frames) =
      gateway.process_stdio_input(
        "cutover-operator",
        "codex",
        root,
        "cutover-session",
        "public",
        profile,
        [
          string.slice(raw, 0, 20),
          string.drop_start(raw, 20) <> "\n",
          request("resources/list") <> "\n",
        ],
        now,
      )
    list.length(frames) |> should.equal(2)
    list.each(frames, fn(frame) {
      json.parse(frame, decode.at(["jsonrpc"], decode.string))
      |> should.equal(Ok("2.0"))
      json.parse(frame, decode.at(["error"], decode.dynamic))
      |> should.be_error
    })
    let payloads =
      list.map(frames, fn(frame) {
        case profile {
          types.Legacy20241105 ->
            json.parse(frame, decode.at(["result"], decode.string))
          types.Modern20260728 ->
            json.parse(frame, decode.at(["result", "value"], decode.string))
        }
      })
    let assert [Ok(inventory), Ok(resources)] = payloads
    inventory |> string.contains("101") |> should.be_true
    resources
    |> string.contains("uos://system/mcp-gateway-health")
    |> should.be_true
  })
  let assert Error(nul) =
    gateway.process_stdio_input(
      "cutover-operator",
      "codex",
      root,
      "cutover-session",
      "public",
      types.Modern20260728,
      ["\u{0000}\n"],
      now,
    )
  nul.code |> should.equal("STDIO_NUL_BYTE_FORBIDDEN")
  let assert Error(escaped) =
    gateway.process_stdio_input(
      "cutover-operator",
      "codex",
      root,
      "cutover-session",
      "public",
      types.Legacy20241105,
      ["\\u0000\n"],
      now,
    )
  escaped.code |> should.equal("STDIO_NUL_BYTE_FORBIDDEN")
  let assert Error(truncated) =
    gateway.process_stdio_input(
      "cutover-operator",
      "codex",
      root,
      "cutover-session",
      "public",
      types.Modern20260728,
      [request("ping")],
      now,
    )
  truncated.code |> should.equal("STDIO_TRUNCATED_FRAME_AT_EOF")
}

pub fn standard_mcp_returns_structured_results_and_silent_notifications_test() {
  standard(
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2024-11-05\"}}",
  )
  |> std_result("protocolVersion")
  |> should.equal(Ok("2024-11-05"))
  standard(request("initialize"))
  |> std_result("protocolVersion")
  |> should.equal(Ok("2026-07-28"))
  let assert Ok(tools) =
    json.parse(
      standard(request("tools/list")),
      decode.at(["result", "tools"], decode.list(decode.dynamic)),
    )
  list.length(tools) |> should.equal(53)
  list.each(
    [
      call("read_file", [#("path", "AGENTS.md")]),
      call("mcp_capability_inventory", []),
    ],
    fn(raw) {
      let body = standard(raw)
      json.parse(
        body,
        decode.at(["result", "_meta", "candidate"], decode.string),
      )
      |> should.equal(Ok(candidate_id.from_root(root)))
      json.parse(body, decode.at(["result", "isError"], decode.bool))
      |> should.equal(Ok(False))
      string.contains(body, "\"isError\":true") |> should.be_false
    },
  )
  standard(request("resources/list"))
  |> string.contains("uos://system/mcp-gateway-health")
  |> should.be_true
  standard(request("resources/templates/list"))
  |> string.contains("uos://docs/{slug}")
  |> should.be_true
  standard(request("prompts/list"))
  |> string.contains("uos_jidoka_rca")
  |> should.be_true
  gateway.handle_standard_mcp_line(
    "a",
    "codex",
    root,
    "s",
    "public",
    "{\"method\":\"notifications/initialized\"}",
    now,
  )
  |> should.equal(None)
  standard(request("ping"))
  |> should.equal("{\"jsonrpc\":\"2.0\",\"id\":7,\"result\":{}}")
}

pub fn standard_mcp_credential_traversal_and_frame_guards_test() {
  list.each(
    [".env", "var/sa-plan/uos.sqlite3", "../AGENTS.md", "/etc/passwd"],
    fn(path) {
      let body = standard(call("read_file", [#("path", path)]))
      json.parse(body, decode.at(["result", "isError"], decode.bool))
      |> should.equal(Ok(True))
      string.contains(body, "PATH_SECURITY_VIOLATION") |> should.be_true
    },
  )
  standard("{\"id\":1,\"method\":\"ping\",\"nul\":\"\\u0000\"}")
  |> string.contains("STDIO_NUL_BYTE_FORBIDDEN")
  |> should.be_true
  let deep = string.repeat("[", 33) <> "0" <> string.repeat("]", 33)
  standard("{\"id\":1,\"method\":\"ping\",\"data\":" <> deep <> "}")
  |> string.contains("STDIO_JSON_DEPTH_EXCEEDED")
  |> should.be_true
  standard(string.repeat("x", 1_048_577))
  |> string.contains("STDIO_FRAME_TOO_LARGE")
  |> should.be_true
}

fn signed_envelope(secret: String) -> zenoh.SignedZenohEnvelope {
  let envelope =
    zenoh.SignedZenohEnvelope(
      "indrajaal/mcp/request/codex/test1",
      "indrajaal/mcp/response/codex/test1",
      "cutover-operator",
      "codex",
      root,
      "cutover-session",
      call("mcp_capability_inventory", []),
      "",
    )
  zenoh.SignedZenohEnvelope(
    ..envelope,
    signature: zenoh.compute_signature(
      secret,
      envelope.topic,
      envelope.reply_topic,
      envelope.sender_actor,
      envelope.client_name,
      envelope.workspace_root,
      envelope.session_id,
      envelope.payload,
    ),
  )
}

pub fn signed_zenoh_dispatch_and_forgery_refusal_test() {
  let envelope = signed_envelope("cutover-zenoh-test-key")
  let assert Ok(Some(#(reply, body))) =
    gateway.handle_zenoh_with_secret(
      "cutover-zenoh-test-key",
      "codex",
      types.Modern20260728,
      envelope,
      now,
    )
  reply |> should.equal(envelope.reply_topic)
  body |> string.contains("101") |> should.be_true
  let assert Error(forged) =
    gateway.handle_zenoh_with_secret(
      "cutover-zenoh-test-key",
      "codex",
      types.Modern20260728,
      zenoh.SignedZenohEnvelope(..envelope, signature: "forged"),
      now,
    )
  forged.code |> should.equal("ZENOH_SIGNATURE_INVALID")
  let assert Error(empty) =
    gateway.handle_zenoh_with_secret(
      "",
      "codex",
      types.Modern20260728,
      envelope,
      now,
    )
  empty.code |> should.equal("ZENOH_SECRET_REQUIRED")
  gateway.handle_zenoh_raw(envelope.topic, "{}") |> should.equal(None)
  gateway.handle_zenoh_raw("wrong/topic", "not json") |> should.equal(None)
}

pub fn immutable_six_core_source_candidate_test() {
  candidate_id.from_root(root)
  |> should.equal(
    "sha256:5fb7a77609e9f41f8368fc5a761435dec6519736a00f4642d6e986ca3e8e1663",
  )
}

pub fn standard_resources_prompts_and_fresh_observation_test() {
  let resource =
    standard(
      "{\"jsonrpc\":\"2.0\",\"id\":31,\"method\":\"resources/read\",\"params\":{\"uri\":\"uos://governance/ev-provenance-ceiling\"}}",
    )
  let assert Ok([text]) =
    json.parse(
      resource,
      decode.at(
        ["result", "contents"],
        decode.list(decode.at(["text"], decode.string)),
      ),
    )
  json.parse(text, decode.at(["admitted_ev_ceiling"], decode.int))
  |> should.equal(Ok(93))
  let prompt =
    standard(
      "{\"jsonrpc\":\"2.0\",\"id\":32,\"method\":\"prompts/get\",\"params\":{\"name\":\"uos_poodavr_review\"}}",
    )
  json.parse(prompt, decode.at(["result", "advisory_only"], decode.bool))
  |> should.equal(Ok(True))
  json.parse(prompt, decode.at(["result", "effect_authority"], decode.bool))
  |> should.equal(Ok(False))
  let assert Some(health) =
    gateway.handle_standard_mcp_line(
      "cutover-operator",
      "codex",
      root,
      "cutover-session",
      "public",
      call("system_health", []),
      now + 60_000,
    )
  let assert Ok([text]) =
    json.parse(
      health,
      decode.at(
        ["result", "content"],
        decode.list(decode.at(["text"], decode.string)),
      ),
    )
  json.parse(text, decode.at(["observed_at_ms"], decode.int))
  |> should.equal(Ok(now + 60_000))
  json.parse(text, decode.at(["age_ms"], decode.int)) |> should.equal(Ok(0))
  let assert Some(foreign) =
    gateway.handle_standard_mcp_line(
      "foreign",
      "codex",
      "/foreign",
      "s",
      "public",
      "{\"id\":33,\"method\":\"resources/read\",\"params\":{\"uri\":\"uos://governance/ev-provenance-ceiling\"}}",
      now,
    )
  foreign |> string.contains("PRINCIPAL_WORKSPACE_MISMATCH") |> should.be_true
  standard(request("Unknown"))
  |> string.contains("METHOD_NOT_FOUND")
  |> should.be_true
}

fn encode_envelope(envelope: zenoh.SignedZenohEnvelope) -> String {
  json.object([
    #("reply_topic", json.string(envelope.reply_topic)),
    #("sender_actor", json.string(envelope.sender_actor)),
    #("client_name", json.string(envelope.client_name)),
    #("workspace_root", json.string(envelope.workspace_root)),
    #("session_id", json.string(envelope.session_id)),
    #("payload", json.string(envelope.payload)),
    #("signature", json.string(envelope.signature)),
  ])
  |> json.to_string
}

pub fn raw_zenoh_uses_configured_secret_and_pins_actual_topic_test() {
  // Never mutate the process environment. Configured deployments exercise
  // positive raw ingress; an unset secret must always refuse it.
  let secret = case get_env("UOS_MCP_ZENOH_SHARED_SECRET") {
    Ok(s) -> s
    Error(_) -> ""
  }
  let envelope = signed_envelope(secret)
  case secret {
    "" ->
      gateway.handle_zenoh_raw(envelope.topic, encode_envelope(envelope))
      |> should.equal(None)
    _ -> {
      let assert Some(#(reply, body)) =
        gateway.handle_zenoh_raw(envelope.topic, encode_envelope(envelope))
      reply |> should.equal(envelope.reply_topic)
      body |> string.contains("101") |> should.be_true
    }
  }
  let forged = zenoh.SignedZenohEnvelope(..envelope, signature: "forged")
  gateway.handle_zenoh_raw(envelope.topic, encode_envelope(forged))
  |> should.equal(None)
  gateway.handle_zenoh_raw(
    "indrajaal/mcp/request/codex/foreign",
    encode_envelope(envelope),
  )
  |> should.equal(None)
}

pub fn zenoh_unauthenticated_read_file_environ_is_dropped_test() {
  gateway.handle_zenoh_raw(
    "indrajaal/mcp/request/c1/r1",
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"read_file\",\"arguments\":{\"path\":\"/proc/self/environ\"}}}",
  )
  |> should.equal(None)
}

pub fn http_nul_byte_and_excess_json_depth_rejected_test() {
  let #(raw_nul_status, _, raw_nul_body) =
    gateway.handle_http_with_config(
      "POST",
      "/mcp",
      authenticated_headers(),
      "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\",\"params\":{\"x\":\""
        <> "\u{0000}"
        <> "\"}}",
      config(),
      now,
    )
  raw_nul_status |> should.equal(400)
  raw_nul_body |> string.contains("HTTP_NUL_BYTE_FORBIDDEN") |> should.be_true

  let #(escaped_nul_status, _, escaped_nul_body) =
    gateway.handle_http_with_config(
      "POST",
      "/mcp",
      authenticated_headers(),
      "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\",\"params\":{\"x\":\"\\\\u0000\"}}",
      config(),
      now,
    )
  escaped_nul_status |> should.equal(400)
  escaped_nul_body
  |> string.contains("HTTP_NUL_BYTE_FORBIDDEN")
  |> should.be_true

  let deep = string.repeat("{\"a\":", 33) <> "1" <> string.repeat("}", 33)
  let #(depth_status, _, depth_body) =
    gateway.handle_http_with_config(
      "POST",
      "/mcp",
      authenticated_headers(),
      deep,
      config(),
      now,
    )
  depth_status |> should.equal(400)
  depth_body
  |> string.contains("HTTP_JSON_DEPTH_EXCEEDED")
  |> should.be_true
}

pub fn http_private_route_header_requires_matching_token_scope_test() {
  let low_scope_headers = [
    #("uos-mcp-route", "development"),
    ..authenticated_headers_with_scopes(["mcp:operational"])
  ]
  let #(forbidden_status, _, forbidden_body) =
    gateway.handle_http_with_config(
      "POST",
      "/mcp",
      low_scope_headers,
      request("tools/list"),
      config(),
      now,
    )
  forbidden_status |> should.equal(200)
  forbidden_body
  |> string.contains("HTTP_ROUTE_SCOPE_FORBIDDEN")
  |> should.be_true
  forbidden_body |> string.contains("\"tools\":[") |> should.be_false

  let dev_scope_headers = [
    #("uos-mcp-route", "development"),
    ..authenticated_headers_with_scopes(["mcp:operational", "mcp:development"])
  ]
  let #(allowed_status, _, allowed_body) =
    gateway.handle_http_with_config(
      "POST",
      "/mcp",
      dev_scope_headers,
      request("tools/list"),
      config(),
      now,
    )
  allowed_status |> should.equal(200)
  let assert Ok(payload) =
    json.parse(allowed_body, decode.at(["result", "value"], decode.string))
  let assert Ok(tools) =
    json.parse(payload, decode.at(["tools"], decode.list(decode.dynamic)))
  list.length(tools) |> should.equal(21)
}

pub fn http_oauth_metadata_and_401_emit_cors_and_absolute_resource_metadata_test() {
  let #(metadata_status, metadata_headers, _) =
    gateway.handle_http_with_config(
      "GET",
      "/.well-known/oauth-protected-resource",
      [#("Origin", origin), #("Accept", "application/json")],
      "",
      config(),
      now,
    )
  metadata_status |> should.equal(200)
  http_auth.header(metadata_headers, "access-control-allow-origin")
  |> should.equal(Ok(origin))

  let #(unauthorized_status, unauthorized_headers, _) =
    gateway.handle_http_with_config(
      "POST",
      "/mcp",
      headers(),
      request("initialize"),
      config(),
      now,
    )
  unauthorized_status |> should.equal(401)
  let assert Ok(challenge) =
    http_auth.header(unauthorized_headers, "www-authenticate")
  challenge
  |> string.contains(
    "https://nas-1.tail55d152.ts.net:4101/.well-known/oauth-protected-resource",
  )
  |> should.be_true
}
