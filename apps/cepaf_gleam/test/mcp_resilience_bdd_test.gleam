//// Given/When/Then regression scenarios for bounded MCP resilience.

import cepaf_gleam/mcp/adapters/planning_read
import cepaf_gleam/mcp/candidate_id
import cepaf_gleam/mcp/http_auth
import cepaf_gleam/mcp/principal
import cepaf_gleam/mcp/receipts
import cepaf_gleam/mcp/resources
import cepaf_gleam/mcp/runtime_gateway as gateway
import cepaf_gleam/mcp/server
import cepaf_gleam/mcp/subscriptions
import cepaf_gleam/mcp/supervisor
import cepaf_gleam/mcp/transports/zenoh
import cepaf_gleam/mcp/types
import cepaf_gleam/mcp/wire
import cepaf_gleam/mcp/worker
import gleam/dict
import gleam/dynamic/decode
import gleam/erlang/atom
import gleam/erlang/process
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleeunit/should
import simplifile

const root = "/home/an/NAS-setup/uos"

@external(erlang, "erlang", "exit")
fn terminate(pid: process.Pid, reason: atom.Atom) -> Bool

@external(erlang, "timer", "sleep")
fn sleep(ms: Int) -> Nil

pub fn given_invalid_request_when_rejected_then_integer_id_is_preserved_test() {
  let assert Some(response) =
    gateway.handle_standard_mcp_line(
      "codex",
      "codex",
      root,
      "r-invalid-id",
      "public",
      "{\"jsonrpc\":17,\"id\":77,\"method\":\"ping\"}",
      1,
    )
  json.parse(response, decode.at(["id"], decode.int)) |> should.equal(Ok(77))
}

pub fn given_public_typed_arguments_when_called_then_request_succeeds_test() {
  let assert Some(response) =
    gateway.handle_standard_mcp_line(
      "codex",
      "codex",
      root,
      "r-typed",
      "public",
      "{\"jsonrpc\":\"2.0\",\"id\":42,\"method\":\"tools/call\",\"params\":{\"name\":\"mcp_capability_inventory\",\"arguments\":{\"number\":95,\"flag\":true,\"nil\":null,\"array\":[1],\"object\":{\"x\":2}}}}",
      1,
    )
  json.parse(response, decode.at(["id"], decode.int)) |> should.equal(Ok(42))
  json.parse(response, decode.at(["result", "isError"], decode.bool))
  |> should.equal(Ok(False))
}

pub fn given_1030_resources_when_read_then_cache_never_exceeds_1024_test() {
  let p =
    principal.from_launcher_env(
      "codex",
      types.ClientProfile("codex"),
      root,
      "cache-bdd",
    )
  let entries =
    int.range(0, 1030, [], fn(acc, n) {
      [
        resources.ResourceEntry(
          "uos://r/" <> int.to_string(n),
          "entry",
          "application/json",
          resources.PublicResource,
          "codex",
          root,
          "{}",
        ),
        ..acc
      ]
    })
  let registry = resources.registry(entries, [])
  let cache =
    list.fold(entries, resources.empty_cache(), fn(cache, entry) {
      let assert Ok(#(_, next)) =
        resources.read_resource(registry, cache, p, entry.uri)
      next
    })
  should.be_true(dict.size(cache.entries) <= 1024)
}

pub fn given_supervised_handle_when_child_dies_then_handle_recovers_test() {
  let assert Ok(g) = supervisor.start_supervised_gateway()
  let assert Ok(child) = process.subject_owner(g.gateway_subject)
  process.unlink(child)
  let _ = terminate(child, atom.create("kill"))
  sleep(10)
  let alive = supervisor.is_gateway_alive(g)
  process.unlink(g.supervisor_pid)
  let _ = terminate(g.supervisor_pid, atom.create("kill"))
  alive |> should.be_true
}

@external(erlang, "ets", "insert")
fn seed_ledger(
  table: atom.Atom,
  entry: #(#(atom.Atom, String), receipts.ReceiptLedger),
) -> Bool

@external(erlang, "persistent_term", "get")
fn current_owner(
  key: atom.Atom,
  fallback: Option(process.Subject(gateway.Message)),
) -> Option(process.Subject(gateway.Message))

@external(erlang, "erlang", "element")
fn snapshot_pool(
  index: Int,
  snapshot: gateway.PrivateSnapshot,
) -> supervisor.WorkerPool

fn live_ledger() -> receipts.ReceiptLedger {
  let assert Some(subject) =
    current_owner(atom.create("uos_mcp_runtime_gateway_subject"), None)
  let reply = process.new_subject()
  let p =
    principal.from_launcher_env(
      "codex",
      types.ClientProfile("codex"),
      root,
      "ledger-bdd",
    )
  process.send(subject, gateway.Snapshot(p, reply))
  let assert Ok(snapshot) = process.receive(reply, 1000)
  snapshot_pool(2, snapshot).ledger
}

fn kill_owner_and_wait() {
  let assert Some(subject) =
    current_owner(atom.create("uos_mcp_runtime_gateway_subject"), None)
  let assert Ok(pid) = process.subject_owner(subject)
  let _ = terminate(pid, atom.create("kill"))
  // Full-capacity chronology migration is real work; observe replacement
  // readiness against a bounded deadline instead of assuming a 20ms sleep.
  wait_owner_ready(monotonic_ms(atom.create("millisecond")) + 1000)
  |> should.be_true
}

@external(erlang, "erlang", "monotonic_time")
fn monotonic_ms(unit: atom.Atom) -> Int

fn wait_owner_ready(deadline: Int) -> Bool {
  case gateway.is_running() {
    True -> True
    False -> case monotonic_ms(atom.create("millisecond")) >= deadline {
      True -> False
      False -> { sleep(2) wait_owner_ready(deadline) }
    }
  }
}

pub fn given_ledger_mirror_when_owner_crashes_then_latches_and_replay_survive_test() {
  gateway.ensure_started() |> should.be_true
  let cand = candidate_id.from_root(root)
  let entries =
    int.range(0, 4100, dict.new(), fn(acc, n) {
      let id = "committed-" <> int.to_string(n)
      let outcome =
        types.Complete(
          "{\"ok\":true}",
          types.EvidenceRecord(
            cand,
            "public",
            "ping",
            "declared",
            "implemented",
            "observed",
            "unrun",
            "not_admitted",
            "fixture",
          ),
        )
      dict.insert(
        acc,
        id,
        receipts.ReceiptEntry(
          id,
          "public",
          "ping",
          "fixture",
          cand,
          receipts.OutcomeCommitted(outcome),
        ),
      )
    })
  let entries =
    int.range(0, 3, entries, fn(acc, n) {
      let id = "uncertain-" <> int.to_string(n)
      dict.insert(
        acc,
        id,
        receipts.ReceiptEntry(
          id,
          "public",
          "ping",
          "fixture",
          cand,
          receipts.EffectUncertain(types.UncertainReceipt(
            id,
            "public",
            "ping",
            "interrupted",
            cand,
          )),
        ),
      )
    })
  let key = root <> ":" <> cand
  seed_ledger(atom.create("uos_mcp_durable_ledger_ets"), #(
    #(atom.create("ledger"), key),
    receipts.ReceiptLedger(cand, entries),
  ))
  |> should.be_true
  kill_owner_and_wait()
  let restored = live_ledger()
  list.each(["uncertain-0", "uncertain-1", "uncertain-2"], fn(id) {
    let #(outcome, _) =
      worker.run_isolated_with_receipts(
        restored,
        id,
        "public",
        "ping",
        "fixture",
        fn() { panic as "Uncertain replay must not execute" },
      )
    let assert types.Refused(error) = outcome
    error.code |> should.equal("UNCERTAIN_RECEIPT_RECONCILE_REQUIRED")
  })
  let committed =
    restored.entries
    |> dict.values
    |> list.filter(fn(entry) {
      case entry.state {
        receipts.OutcomeCommitted(_) -> True
        _ -> False
      }
    })
  list.length(committed) |> should.equal(4096)
  let assert [entry, ..] = committed
  let #(outcome, _) =
    worker.run_isolated_with_receipts(
      restored,
      entry.intent_id,
      "public",
      "ping",
      "fixture",
      fn() { panic as "Committed replay must not execute" },
    )
  let assert types.Complete(body, _) = outcome
  body |> should.equal("{\"ok\":true}")
  seed_ledger(atom.create("uos_mcp_durable_ledger_ets"), #(
    #(atom.create("ledger"), key),
    receipts.new_ledger(cand),
  ))
  |> should.be_true
  kill_owner_and_wait()
}

pub fn given_committed_call_when_owner_restarts_then_committed_receipt_is_retained_test() {
  gateway.ensure_started() |> should.be_true
  let _ =
    gateway.handle_standard_mcp_line(
      "codex",
      "codex",
      root,
      "normal-durable",
      "public",
      "{\"jsonrpc\":\"2.0\",\"id\":100,\"method\":\"tools/call\",\"params\":{\"name\":\"mcp_capability_inventory\",\"arguments\":{\"intent_id\":\"normal-durable-call\"}}}",
      1,
    )
  let before = live_ledger()
  should.be_true(dict.size(before.entries) > 0)
  kill_owner_and_wait()
  let after = live_ledger()
  after.entries |> should.equal(before.entries)
}

pub fn given_unresolved_store_full_when_new_intent_arrives_then_fail_before_effect_test() {
  gateway.ensure_started() |> should.be_true
  let cand = candidate_id.from_root(root)
  let pending =
    int.range(0, 4096, dict.new(), fn(acc, n) {
      let id = "pending-" <> int.to_string(n)
      dict.insert(
        acc,
        id,
        receipts.ReceiptEntry(
          id,
          "public",
          "ping",
          "fixture",
          cand,
          receipts.IntentRecorded,
        ),
      )
    })
  let key = root <> ":" <> cand
  seed_ledger(atom.create("uos_mcp_durable_ledger_ets"), #(
    #(atom.create("ledger"), key),
    receipts.ReceiptLedger(cand, pending),
  ))
  |> should.be_true
  kill_owner_and_wait()
  let assert Some(response) =
    gateway.handle_standard_mcp_line(
      "codex",
      "codex",
      root,
      "capacity",
      "public",
      "{\"jsonrpc\":\"2.0\",\"id\":101,\"method\":\"tools/call\",\"params\":{\"name\":\"mcp_capability_inventory\",\"arguments\":{\"intent_id\":\"cannot-record-new\"}}}",
      1,
    )
  // Retryable capacity failure is a JSON-RPC server error, per Wave2 taxonomy.
  json.parse(response, decode.at(["error", "code"], decode.int))
  |> should.equal(Ok(-32_001))
  let refused =
    json.parse(response, decode.at(["error", "message"], decode.string))
    |> result.unwrap("")
  seed_ledger(atom.create("uos_mcp_durable_ledger_ets"), #(
    #(atom.create("ledger"), key),
    receipts.new_ledger(cand),
  ))
  |> should.be_true
  kill_owner_and_wait()
  should.be_true(string.contains(refused, "RECEIPT_LEDGER_CAPACITY_EXCEEDED"))
}

@external(erlang, "sys", "suspend")
fn suspend(pid: process.Pid) -> Nil

@external(erlang, "sys", "resume")
fn resume(pid: process.Pid) -> Nil

pub fn given_300_concurrent_calls_when_owner_pauses_then_overload_is_shed_test() {
  gateway.ensure_started() |> should.be_true
  let assert Some(subject) =
    current_owner(atom.create("uos_mcp_runtime_gateway_subject"), None)
  let assert Ok(owner) = process.subject_owner(subject)
  suspend(owner)
  let reply = process.new_subject()
  let _ =
    int.range(0, 300, Nil, fn(_, n) {
      let _ =
        process.spawn(fn() {
          let response =
            gateway.handle_standard_mcp_line(
              "codex",
              "codex",
              root,
              "overload-" <> int.to_string(n),
              "public",
              "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}",
              1,
            )
            |> option.unwrap("")
          process.send(reply, string.contains(response, "GATEWAY_OVERLOADED"))
        })
      Nil
    })
  sleep(100)
  resume(owner)
  let shed =
    int.range(0, 300, 0, fn(count, _) {
      let assert Ok(overloaded) = process.receive(reply, 3000)
      count
      + case overloaded {
        True -> 1
        False -> 0
      }
    })
  should.be_true(shed >= 44)
  gateway.is_running() |> should.be_true
}

pub fn given_inflight_caller_killed_when_next_call_arrives_then_slot_recovers_test() {
  gateway.ensure_started() |> should.be_true
  let entered = process.new_subject()
  let pid =
    process.spawn_unlinked(fn() {
      let _ =
        gateway.with_inflight_slot(1, fn() {
          process.send(entered, True)
          sleep(3000)
          types.Refused(types.ToolError("FINISHED", "finished", types.Retryable))
        })
      Nil
    })
  process.receive(entered, 1000) |> should.equal(Ok(True))
  let _ = terminate(pid, atom.create("kill"))
  sleep(10)
  gateway.with_inflight_slot(1, fn() {
    types.Refused(types.ToolError("FREE", "free", types.Retryable))
  })
  |> should.equal(
    types.Refused(types.ToolError("FREE", "free", types.Retryable)),
  )
}

pub fn given_observation_without_explicit_intent_when_repeated_then_no_replay_cache_test() {
  gateway.ensure_started() |> should.be_true
  let before = live_ledger()
  let _ =
    gateway.handle_standard_mcp_line(
      "codex",
      "codex",
      root,
      "fresh-read-bdd",
      "public",
      "{\"jsonrpc\":\"2.0\",\"id\":111,\"method\":\"tools/call\",\"params\":{\"name\":\"mcp_capability_inventory\",\"arguments\":{\"read_probe\":\"fresh-not-idempotent\"}}}",
      1,
    )
  live_ledger().entries |> should.equal(before.entries)
}

const origin = "https://nas-1.tail55d152.ts.net:4101"

const fixture_now = 2_000_000

const fixture_secret = "bdd-only-noncredential-secret"

fn bdd_config() -> http_auth.AuthConfig {
  http_auth.AuthConfig(
    [origin],
    origin,
    origin <> "/mcp",
    "mcp:operational",
    fixture_secret,
  )
}

fn bdd_headers(
  agent: String,
  version: String,
  route: String,
) -> List(#(String, String)) {
  let token =
    http_auth.sign_token(
      http_auth.TokenClaims(
        origin,
        origin <> "/mcp",
        agent,
        agent,
        root,
        "bdd-" <> agent,
        ["mcp:operational", "mcp:development", "mcp:successor"],
        fixture_now - 1,
        fixture_now + 60_000,
      ),
      fixture_secret,
    )
  [
    #("Origin", origin),
    #("Content-Type", "application/json"),
    #("Accept", "application/json"),
    #("Mcp-Protocol-Version", version),
    #("Mcp-Session-Id", "bdd-" <> agent),
    #("uos-mcp-route", route),
    #("Authorization", "Bearer " <> token),
  ]
}

fn bdd_request(
  method: String,
  version: String,
  params: List(#(String, json.Json)),
) -> String {
  json.object([
    #("jsonrpc", json.string("2.0")),
    #("id", json.int(42)),
    #("method", json.string(method)),
    #(
      "params",
      json.object([#("protocolVersion", json.string(version)), ..params]),
    ),
  ])
  |> json.to_string
}

fn bdd_envelope(
  agent: String,
  id: String,
  raw: String,
) -> zenoh.SignedZenohEnvelope {
  let e =
    zenoh.SignedZenohEnvelope(
      "indrajaal/mcp/request/" <> agent <> "/" <> id,
      "indrajaal/mcp/response/" <> agent <> "/" <> id,
      agent,
      agent,
      root,
      "bdd-" <> agent,
      raw,
      "",
    )
  zenoh.SignedZenohEnvelope(
    ..e,
    signature: zenoh.compute_signature(
      fixture_secret,
      e.topic,
      e.reply_topic,
      agent,
      agent,
      root,
      e.session_id,
      raw,
    ),
  )
}

fn bdd_wire_body(body: String, profile: types.ProtocolProfile) -> String {
  case profile {
    types.Legacy20241105 ->
      // Canonical stdio/Zenoh retain the legacy string envelope; native MCP
      // HTTP supplies the same verified payload in result.value. Both arms
      // must decode an actual string, and the matrix asserts its semantics.
      json.parse(
        body,
        decode.one_of(decode.at(["result"], decode.string), [
          decode.at(["result", "value"], decode.string),
        ]),
      )
      |> result.unwrap("ERROR:" <> body)
    types.Modern20260728 ->
      json.parse(body, decode.at(["result", "value"], decode.string))
      |> result.unwrap("ERROR:" <> body)
  }
}

fn bdd_transport(
  agent: String,
  transport: String,
  profile: types.ProtocolProfile,
  route: String,
  raw: String,
) -> String {
  let version = case profile {
    types.Legacy20241105 -> "2024-11-05"
    types.Modern20260728 -> "2026-07-28"
  }
  case transport {
    "stdio" -> {
      let assert Ok([body]) =
        gateway.process_stdio_input(
          agent,
          agent,
          root,
          "bdd-" <> agent,
          route,
          profile,
          [raw <> "\n"],
          fixture_now,
        )
      json.parse(body, decode.at(["id"], decode.int)) |> should.equal(Ok(42))
      bdd_wire_body(body, profile)
    }
    "http" -> {
      let #(status, _, body) =
        gateway.handle_http_with_config(
          "POST",
          "/mcp",
          bdd_headers(agent, version, route),
          raw,
          bdd_config(),
          fixture_now,
        )
      status |> should.equal(200)
      json.parse(body, decode.at(["id"], decode.int)) |> should.equal(Ok(42))
      bdd_wire_body(body, profile)
    }
    _ -> {
      let assert Ok(Some(#(_, body))) =
        gateway.handle_zenoh_with_secret(
          fixture_secret,
          agent,
          profile,
          bdd_envelope(agent, "matrix", raw),
          fixture_now,
        )
      json.parse(body, decode.at(["id"], decode.int)) |> should.equal(Ok(42))
      bdd_wire_body(body, profile)
    }
  }
}

fn given_agent_when_transport_profile_plane_matrix_then_counts_and_typed_public_are_honest(
  agent: String,
) {
  list.each([types.Legacy20241105, types.Modern20260728], fn(profile) {
    let version = case profile {
      types.Legacy20241105 -> "2024-11-05"
      types.Modern20260728 -> "2026-07-28"
    }
    list.each(["stdio", "http", "zenoh"], fn(transport) {
      list.each(["public", "development", "successor"], fn(route) {
        // Zenoh is intentionally public-only: an untrusted route label cannot expose private tools.
        let expected = case transport, route {
          "zenoh", _ | _, "public" -> 53
          _, "development" -> 21
          _, _ -> 15
        }
        let body =
          bdd_transport(
            agent,
            transport,
            profile,
            route,
            bdd_request("tools/list", version, [#("route", json.string(route))]),
          )
        json.parse(body, decode.at(["tools"], decode.list(decode.dynamic)))
        |> result.map(list.length)
        |> should.equal(Ok(expected))
      })
      let args =
        json.object([
          #("benefit", json.int(95)),
          #("cost", json.int(5)),
          #("flag", json.bool(True)),
        ])
      let body =
        bdd_transport(
          agent,
          transport,
          profile,
          "public",
          bdd_request("tools/call", version, [
            #("name", json.string("preflight_check")),
            #("arguments", args),
          ]),
        )
      string.contains(body, "preflight_toolchain") |> should.be_true
      string.contains(body, "\"exit_code\":0") |> should.be_true
    })
  })
}

pub fn given_agy_when_all_transports_profiles_planes_then_bdd_matrix_test() {
  given_agent_when_transport_profile_plane_matrix_then_counts_and_typed_public_are_honest(
    "agy",
  )
}

pub fn given_claude_when_all_transports_profiles_planes_then_bdd_matrix_test() {
  given_agent_when_transport_profile_plane_matrix_then_counts_and_typed_public_are_honest(
    "claude",
  )
}

pub fn given_codex_when_all_transports_profiles_planes_then_bdd_matrix_test() {
  given_agent_when_transport_profile_plane_matrix_then_counts_and_typed_public_are_honest(
    "codex",
  )
}

pub fn given_pi_when_all_transports_profiles_planes_then_bdd_matrix_test() {
  given_agent_when_transport_profile_plane_matrix_then_counts_and_typed_public_are_honest(
    "pi",
  )
}

pub fn given_invalid_http_request_when_rejected_then_same_session_remains_usable_test() {
  let headers = bdd_headers("codex", "2026-07-28", "public")
  let #(status, _, body) =
    gateway.handle_http_with_config(
      "POST",
      "/mcp",
      headers,
      "{\"jsonrpc\":false,\"id\":77,\"method\":\"ping\"}",
      bdd_config(),
      fixture_now,
    )
  status |> should.equal(400)
  json.parse(body, decode.at(["id"], decode.int)) |> should.equal(Ok(77))
  let #(status, _, _) =
    gateway.handle_http_with_config(
      "POST",
      "/mcp",
      headers,
      bdd_request("ping", "2026-07-28", []),
      bdd_config(),
      fixture_now,
    )
  status |> should.equal(200)
  let assert Some(bad) =
    gateway.handle_standard_mcp_line(
      "codex",
      "codex",
      root,
      "bdd-recovery",
      "public",
      "{\"jsonrpc\":\"2.0\",\"id\":77,\"method\":\"not-a-method\"}",
      fixture_now,
    )
  json.parse(bad, decode.at(["id"], decode.int)) |> should.equal(Ok(77))
  let assert Some(pong) =
    gateway.handle_standard_mcp_line(
      "codex",
      "codex",
      root,
      "bdd-recovery",
      "public",
      "{\"jsonrpc\":\"2.0\",\"id\":78,\"method\":\"ping\"}",
      fixture_now,
    )
  json.parse(pong, decode.at(["id"], decode.int)) |> should.equal(Ok(78))
}

pub fn given_subscriptions_at_capacity_when_exceeded_then_refusal_preserves_normal_use_test() {
  let p =
    principal.from_launcher_env(
      "codex",
      types.ClientProfile("codex"),
      root,
      "capacity",
    )
  let store =
    int.range(0, 1024, subscriptions.empty_store(), fn(store, n) {
      let assert Ok(next) =
        subscriptions.subscribe(
          store,
          types.Modern20260728,
          p,
          "s-" <> int.to_string(n),
          subscriptions.ResourceSubscription("uos://r"),
        )
      next
    })
  let assert Error(error) =
    subscriptions.subscribe(
      store,
      types.Modern20260728,
      p,
      "overflow",
      subscriptions.ResourceSubscription("uos://r"),
    )
  error.code |> should.equal("SUBSCRIPTION_CAPACITY_EXCEEDED")
  let store =
    int.range(0, 128, store, fn(store, _) {
      let assert Ok(next) =
        subscriptions.push_notification(store, "s-0", "payload")
      next
    })
  let assert Error(error) =
    subscriptions.push_notification(store, "s-0", "overflow")
  error.code |> should.equal("SUBSCRIPTION_BACKPRESSURE_LIMIT")
  subscriptions.pending_notifications(store, types.Modern20260728, p, "s-0")
  |> result.map(list.length)
  |> should.equal(Ok(128))
}

@external(erlang, "mcp_stdio_ffi", "zenoh_sse_loopback_fixture")
fn sse_flood_fixture(
  valid: String,
  forged: String,
  ping: String,
  start: fn(Int) -> Result(process.Pid, String),
) -> Result(#(String, String), String)

fn sample(envelope: zenoh.SignedZenohEnvelope) -> String {
  let object =
    json.object([
      #("reply_topic", json.string(envelope.reply_topic)),
      #("sender_actor", json.string(envelope.sender_actor)),
      #("client_name", json.string(envelope.client_name)),
      #("workspace_root", json.string(envelope.workspace_root)),
      #("session_id", json.string(envelope.session_id)),
      #("payload", json.string(envelope.payload)),
      #("signature", json.string(envelope.signature)),
    ])
  "data: "
  <> json.to_string(
    json.object([
      #("key", json.string(envelope.topic)),
      #("value", object),
      #("encoding", json.string("application/json")),
    ]),
  )
  <> "\r\n\r\n"
}

pub fn given_split_sse_stream_when_100_forged_frames_overflow_and_eof_then_recovers_test() {
  let valid =
    bdd_envelope("codex", "loop1", bdd_request("tools/list", "2026-07-28", []))
  let forged = zenoh.SignedZenohEnvelope(..valid, signature: "forged")
  let ping =
    bdd_envelope("codex", "loop2", bdd_request("ping", "2026-07-28", []))
  let flood = string.repeat(sample(forged) <> "data: {bad-json}\n\n", 100)
  let assert Ok(#(tools, pong)) =
    sse_flood_fixture(sample(valid), flood, sample(ping), fn(port) {
      gateway.start_zenoh_sse_subscriber_for_test(
        "127.0.0.1",
        port,
        fixture_secret,
      )
    })
  let assert Ok(body) =
    json.parse(tools, decode.at(["result", "value"], decode.string))
  json.parse(body, decode.at(["tools"], decode.list(decode.dynamic)))
  |> result.map(list.length)
  |> should.equal(Ok(53))
  json.parse(pong, decode.at(["id"], decode.int)) |> should.equal(Ok(42))
  gateway.is_running() |> should.be_true
}

@external(erlang, "mcp_stdio_ffi", "zenoh_sse_atomics_fixture")
fn atomics_freshness_fixture(
  start: fn(Int) -> Result(process.Pid, String),
) -> Result(Nil, String)

pub fn given_registered_sse_when_chunks_refresh_then_zero_hot_path_persistent_term_writes_test() {
  atomics_freshness_fixture(fn(port) {
    gateway.start_zenoh_sse_subscriber_with_options(
      "127.0.0.1",
      port,
      "atomics-fixture-secret",
      True,
      0,
      150,
    )
  })
  |> should.equal(Ok(Nil))
}

fn fixture_transition(
  state: gateway.GatewayState,
  p: principal.Principal,
  method: String,
  params: List(#(String, json.Json)),
) -> #(types.Outcome, gateway.GatewayState) {
  let raw = bdd_request(method, "2026-07-28", params)
  let assert Ok(msg) = wire.decode_request(types.Modern20260728, raw)
  gateway.dispatch_normalized(
    state,
    p,
    types.Modern20260728,
    "public",
    raw,
    msg,
    fixture_now,
  )
}

pub fn given_four_principals_when_private_resource_subscription_and_task_crossed_then_refused_test() {
  let assert Ok(pool) =
    supervisor.start_worker_pool_for_candidate(1, candidate_id.from_root(root))
  let assert Ok(g) = supervisor.start_supervised_gateway()
  let state = gateway.new_state(root, pool.ledger.candidate, pool, g)
  let rows =
    list.map(["agy", "claude", "codex", "pi"], fn(actor) {
      planning_read.CanonicalTaskRow(
        "bdd-plan",
        actor,
        "Fixture executing task",
        "executing",
        actor,
        1,
      )
    })
  let state =
    gateway.GatewayState(
      ..state,
      backends: server.ServerBackends(
        ..state.backends,
        planning_read: planning_read.AvailableStore("bdd-plan", rows),
      ),
    )
  let _ =
    list.fold(["agy", "claude", "codex", "pi"], state, fn(state, actor) {
      let p =
        principal.from_launcher_env(
          actor,
          types.ClientProfile(actor),
          root,
          "isolated-" <> actor,
        )
      let other =
        principal.from_launcher_env(
          "other-" <> actor,
          types.ClientProfile(actor),
          root,
          "foreign",
        )
      let registry =
        resources.registry(
          [
            resources.ResourceEntry(
              "uos://private/r",
              "private",
              "application/json",
              resources.PrivatePrincipalResource,
              actor,
              root,
              "{}",
            ),
          ],
          [],
        )
      let assert Error(error) =
        resources.read_resource(
          registry,
          resources.empty_cache(),
          other,
          "uos://private/r",
        )
      error.code |> should.equal("CROSS_PRINCIPAL_RESOURCE_FORBIDDEN")
      let assert Ok(store) =
        subscriptions.subscribe(
          subscriptions.empty_store(),
          types.Modern20260728,
          p,
          "bound",
          subscriptions.ResourceSubscription("uos://r"),
        )
      let assert Error(error) =
        subscriptions.read_subscription(
          store,
          types.Modern20260728,
          other,
          "bound",
        )
      error.code |> should.equal("CROSS_PRINCIPAL_SUBSCRIPTION_FORBIDDEN")
      let #(_, state) =
        fixture_transition(state, p, "initialize", [
          #("capabilities", json.object([#("tasks", json.object([]))])),
        ])
      let #(created, state) =
        fixture_transition(state, p, "tasks/create", [
          #("planId", json.string("bdd-plan")),
          #("taskId", json.string(actor)),
        ])
      let assert types.Complete(created_body, evidence) = created
      evidence.candidate |> should.equal(pool.ledger.candidate)
      let assert Ok(handle) =
        json.parse(created_body, decode.at(["handleId"], decode.string))
      let params = [#("handleId", json.string(handle))]
      list.each(["tasks/get", "tasks/result", "tasks/cancel"], fn(method) {
        let #(foreign, _) = fixture_transition(state, other, method, params)
        let assert types.Refused(error) = foreign
        error.code |> should.equal("CROSS_PRINCIPAL_TASK_HANDLE_FORBIDDEN")
      })
      let #(get, _) = fixture_transition(state, p, "tasks/get", params)
      let assert types.Complete(_, _) = get
      let #(cancel, state) =
        fixture_transition(state, p, "tasks/cancel", params)
      let assert types.Complete(body, _) = cancel
      json.parse(body, decode.at(["cancelAcknowledged"], decode.bool))
      |> should.equal(Ok(True))
      json.parse(body, decode.at(["effectStopped"], decode.bool))
      |> should.equal(Ok(False))
      state
    })
  process.unlink(g.supervisor_pid)
  let _ = terminate(g.supervisor_pid, atom.create("kill"))
  Nil
}

@external(erlang, "erlang", "monotonic_time")
fn clock(unit: atom.Atom) -> Int

pub fn given_warm_gateway_when_128_ping_callers_burst_then_no_boot_lock_convoy_test() {
  gateway.ensure_started() |> should.be_true
  let reply = process.new_subject()
  let begin = clock(atom.create("millisecond"))
  let _ =
    int.range(0, 128, Nil, fn(_, _) {
      let _ =
        process.spawn_unlinked(fn() {
          let body =
            gateway.handle_standard_mcp_line(
              "codex",
              "codex",
              root,
              "warm",
              "public",
              "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}",
              1,
            )
          process.send(reply, body != None)
        })
      Nil
    })
  let _ =
    int.range(0, 128, Nil, fn(_, _) {
      process.receive(reply, 3000) |> should.equal(Ok(True))
    })
  let elapsed = clock(atom.create("millisecond")) - begin
  should.be_true(elapsed < 500)
}

pub fn given_bad_bearer_http_flood_when_rejected_then_no_boot_lock_convoy_test() {
  gateway.ensure_started() |> should.be_true
  let reply = process.new_subject()
  let begin = clock(atom.create("millisecond"))
  let headers =
    bdd_headers("codex", "2026-07-28", "public")
    |> list.filter(fn(h) { h.0 != "Authorization" })
  let _ =
    int.range(0, 128, Nil, fn(_, _) {
      let _ =
        process.spawn_unlinked(fn() {
          let #(status, _, _) =
            gateway.handle_http_with_config(
              "POST",
              "/mcp",
              [#("Authorization", "Bearer forged"), ..headers],
              bdd_request("ping", "2026-07-28", []),
              bdd_config(),
              fixture_now,
            )
          process.send(reply, status)
        })
      Nil
    })
  let _ =
    int.range(0, 128, Nil, fn(_, _) {
      process.receive(reply, 3000) |> should.equal(Ok(401))
    })
  should.be_true(clock(atom.create("millisecond")) - begin < 500)
}

pub fn given_queued_read_calls_when_owner_killed_then_replies_follow_restarted_owner_test() {
  gateway.ensure_started() |> should.be_true
  let assert Some(subject) =
    current_owner(atom.create("uos_mcp_runtime_gateway_subject"), None)
  let assert Ok(owner) = process.subject_owner(subject)
  suspend(owner)
  let reply = process.new_subject()
  let callers =
    int.range(0, 16, [], fn(pids, _) {
      let pid =
        process.spawn_unlinked(fn() {
          let body =
            gateway.handle_standard_mcp_line(
              "codex",
              "codex",
              root,
              "mid-flight",
              "public",
              "{\"jsonrpc\":\"2.0\",\"id\":55,\"method\":\"tools/list\"}",
              1,
            )
            |> option.unwrap("")
          process.send(reply, string.contains(body, "\"tools\""))
        })
      [pid, ..pids]
    })
  sleep(10)
  let _ = terminate(owner, atom.create("kill"))
  let recovered = case process.receive(reply, 300) {
    Ok(True) ->
      int.range(1, 16, True, fn(ok, _) {
        ok && process.receive(reply, 100) == Ok(True)
      })
    _ -> False
  }
  list.each(callers, fn(pid) {
    let _ = terminate(pid, atom.create("kill"))
    Nil
  })
  recovered |> should.be_true
}

@external(erlang, "erlang", "whereis")
fn registered_pid(name: atom.Atom) -> process.Pid

pub fn given_supervisor_in_restart_gap_when_ingress_boots_then_loser_never_publishes_test() {
  gateway.ensure_started() |> should.be_true
  let sup = registered_pid(atom.create("uos_mcp_runtime_gateway_sup"))
  let assert Some(before) =
    current_owner(atom.create("uos_mcp_runtime_gateway_subject"), None)
  let assert Ok(owner) = process.subject_owner(before)
  suspend(sup)
  let _ = terminate(owner, atom.create("kill"))
  let _ = gateway.ensure_started()
  let observed =
    current_owner(atom.create("uos_mcp_runtime_gateway_subject"), None)
  resume(sup)
  sleep(20)
  observed |> should.equal(Some(before))
  gateway.is_running() |> should.be_true
}

pub fn given_private_snapshot_queued_when_owner_killed_then_ungranted_call_refuses_promptly_test() {
  gateway.ensure_started() |> should.be_true
  let assert Some(subject) =
    current_owner(atom.create("uos_mcp_runtime_gateway_subject"), None)
  let assert Ok(owner) = process.subject_owner(subject)
  suspend(owner)
  let reply = process.new_subject()
  let caller =
    process.spawn_unlinked(fn() {
      let body =
        gateway.handle_standard_mcp_line(
          "codex-bdd-ungranted",
          "codex",
          root,
          "private-mid-flight",
          "successor",
          "{\"jsonrpc\":\"2.0\",\"id\":56,\"method\":\"tools/call\",\"params\":{\"name\":\"harness_status\",\"arguments\":{}}}",
          1,
        )
        |> option.unwrap("")
      process.send(reply, string.contains(body, "ROUTE_GRANT_REQUIRED"))
    })
  sleep(10)
  let _ = terminate(owner, atom.create("kill"))
  let observed = process.receive(reply, 300)
  let _ = terminate(caller, atom.create("kill"))
  observed |> should.equal(Ok(True))
}

pub fn given_cached_gateway_health_when_read_then_observation_is_live_not_boot_snapshot_test() {
  let assert Ok(pool) =
    supervisor.start_worker_pool_for_candidate(1, candidate_id.from_root(root))
  let assert Ok(g) = supervisor.start_supervised_gateway()
  let state = gateway.new_state(root, pool.ledger.candidate, pool, g)
  let uri = "uos://system/mcp-gateway-health"
  let registry =
    resources.registry(
      [
        resources.ResourceEntry(
          uri,
          "health",
          "application/json",
          resources.PublicResource,
          "",
          root,
          "stale-boot-health",
        ),
      ],
      [],
    )
  let p =
    principal.from_launcher_env(
      "codex",
      types.ClientProfile("codex"),
      root,
      "health-refresh",
    )
  let assert Ok(#(_, cache)) =
    resources.read_resource(registry, resources.empty_cache(), p, uri)
  let state =
    gateway.GatewayState(..state, resources: registry, resource_cache: cache)
  let #(outcome, _) =
    fixture_transition(state, p, "resources/read", [#("uri", json.string(uri))])
  let assert types.Complete(body, _) = outcome
  process.unlink(g.supervisor_pid)
  let _ = terminate(g.supervisor_pid, atom.create("kill"))
  string.contains(body, "stale-boot-health") |> should.be_false
  string.contains(body, "zenoh_subscriber_alive") |> should.be_true
}

pub fn given_ungranted_private_burst_when_serialized_then_no_global_retry_backoff_convoy_test() {
  gateway.ensure_started() |> should.be_true
  let reply = process.new_subject()
  let begin = clock(atom.create("millisecond"))
  let _ =
    int.range(0, 128, Nil, fn(_, _) {
      let _ =
        process.spawn_unlinked(fn() {
          let body =
            gateway.handle_standard_mcp_line(
              "codex-bdd-ungranted",
              "codex",
              root,
              "private-burst",
              "successor",
              "{\"jsonrpc\":\"2.0\",\"id\":57,\"method\":\"tools/call\",\"params\":{\"name\":\"harness_status\",\"arguments\":{}}}",
              1,
            )
            |> option.unwrap("")
          process.send(reply, string.contains(body, "ROUTE_GRANT_REQUIRED"))
        })
      Nil
    })
  let _ =
    int.range(0, 128, Nil, fn(_, _) {
      process.receive(reply, 3000) |> should.equal(Ok(True))
    })
  should.be_true(clock(atom.create("millisecond")) - begin < 1000)
}

@external(erlang, "mcp_stdio_ffi", "run_workspace_bounded_cd")
fn bounded_command(
  path: String,
  args: List(String),
  cwd: String,
  timeout: Int,
) -> Result(#(Int, String), String)

@external(erlang, "erlang", "system_info")
fn count_system(metric: atom.Atom) -> Int

fn meter_ports(
  stop: process.Subject(Nil),
  peak: Int,
  reply: process.Subject(Int),
) {
  case process.receive(stop, 1) {
    Ok(Nil) -> process.send(reply, peak)
    Error(_) ->
      meter_ports(
        stop,
        int.max(peak, count_system(atom.create("port_count"))),
        reply,
      )
  }
}

pub fn given_64_native_prefetches_when_slow_then_backend_ports_are_bounded_test() {
  let baseline = count_system(atom.create("port_count"))
  let ready = process.new_subject()
  let measured = process.new_subject()
  let _ =
    process.spawn_unlinked(fn() {
      let stop = process.new_subject()
      process.send(ready, stop)
      meter_ports(stop, baseline, measured)
    })
  let assert Ok(stop) = process.receive(ready, 1000)
  let replies = process.new_subject()
  let _ =
    int.range(0, 64, Nil, fn(_, _) {
      let _ =
        process.spawn_unlinked(fn() {
          process.send(
            replies,
            bounded_command("/usr/bin/sleep", ["0.1"], root, 3000),
          )
        })
      Nil
    })
  let _ =
    int.range(0, 64, Nil, fn(_, _) {
      process.receive(replies, 4000) |> should.equal(Ok(Ok(#(0, ""))))
    })
  process.send(stop, Nil)
  let assert Ok(peak) = process.receive(measured, 1000)
  should.be_true(peak - baseline <= 16)
}

pub fn given_mirrored_replay_with_foreign_candidate_when_rehydrated_then_fail_closed_test() {
  let raw =
    "{\"jsonrpc\":\"2.0\",\"id\":58,\"method\":\"tools/call\",\"params\":{\"name\":\"mcp_capability_inventory\",\"arguments\":{\"intent_id\":\"candidate-replay-check\"}}}"
  let _ =
    gateway.handle_standard_mcp_line(
      "codex",
      "codex",
      root,
      "candidate-replay",
      "public",
      raw,
      1,
    )
  let ledger = live_ledger()
  let entries =
    dict.map_values(ledger.entries, fn(_, entry) {
      case entry.state {
        receipts.OutcomeCommitted(types.Complete(body, evidence)) ->
          case string.ends_with(entry.intent_id, ":candidate-replay-check") {
            True ->
              receipts.ReceiptEntry(
                ..entry,
                state: receipts.OutcomeCommitted(types.Complete(
                  body,
                  types.EvidenceRecord(
                    ..evidence,
                    candidate: "foreign-candidate",
                  ),
                )),
              )
            False -> entry
          }
        _ -> entry
      }
    })
  let key = root <> ":" <> ledger.candidate
  seed_ledger(atom.create("uos_mcp_durable_ledger_ets"), #(
    #(atom.create("ledger"), key),
    receipts.ReceiptLedger(..ledger, entries: entries),
  ))
  |> should.be_true
  kill_owner_and_wait()
  let assert Some(body) =
    gateway.handle_standard_mcp_line(
      "codex",
      "codex",
      root,
      "candidate-replay",
      "public",
      raw,
      1,
    )
  seed_ledger(atom.create("uos_mcp_durable_ledger_ets"), #(
    #(atom.create("ledger"), key),
    receipts.new_ledger(ledger.candidate),
  ))
  |> should.be_true
  kill_owner_and_wait()
  json.parse(body, decode.at(["result", "isError"], decode.bool))
  |> should.equal(Ok(True))
  string.contains(body, "CANDIDATE") |> should.be_true
}

pub fn given_short_sqlite_writer_lock_when_planning_prefetched_then_waits_within_budget_test() {
  let fixture =
    root <> "/var/harness/20261030-2325-mcp-resilience/sqlite-busy-fixture"
  let db = fixture <> "/var/sa-plan/uos.sqlite3"
  let marker = fixture <> "/writer-ready"
  let assert Ok(Nil) =
    simplifile.create_directory_all(fixture <> "/var/sa-plan")
  let _ = simplifile.delete(marker)
  let _ = simplifile.delete(db)
  let schema =
    "CREATE TABLE sa_plan_task(plan_id TEXT,id TEXT,title TEXT,state TEXT,worker TEXT,attempt INTEGER); INSERT INTO sa_plan_task VALUES('20261029-1913-mcp-server-completion','fixture','fixture only, not execution authority','executing','fixture-worker',1);"
  bounded_command("/usr/bin/sqlite3", [db, schema], fixture, 3000)
  |> should.equal(Ok(#(0, "")))
  let finished = process.new_subject()
  let _ =
    process.spawn_unlinked(fn() {
      let script =
        "{ printf 'BEGIN EXCLUSIVE;\\n.shell touch %s\\n' \"$2\"; sleep 0.25; printf 'COMMIT;\\n'; } | /usr/bin/sqlite3 \"$1\""
      process.send(
        finished,
        bounded_command(
          "/bin/bash",
          ["-c", script, "fixture", db, marker],
          fixture,
          3000,
        ),
      )
    })
  wait_fixture_marker(marker, 100)
  let assert Ok(pool) =
    supervisor.start_worker_pool_for_candidate(1, candidate_id.from_root(root))
  let assert Ok(g) = supervisor.start_supervised_gateway()
  let state = gateway.new_state(fixture, pool.ledger.candidate, pool, g)
  let observed = case state.backends.planning_read {
    planning_read.AvailableStore(_, [_]) -> True
    _ -> False
  }
  process.receive(finished, 3000) |> should.equal(Ok(Ok(#(0, ""))))
  process.unlink(g.supervisor_pid)
  let _ = terminate(g.supervisor_pid, atom.create("kill"))
  let assert Ok(Nil) = simplifile.delete(marker)
  let assert Ok(Nil) = simplifile.delete(db)
  observed |> should.be_true
}

fn wait_fixture_marker(path: String, attempts: Int) {
  case simplifile.is_file(path), attempts > 0 {
    Ok(True), _ -> Nil
    _, True -> {
      sleep(2)
      wait_fixture_marker(path, attempts - 1)
    }
    _, False -> panic as "SQLite fixture writer did not acquire its lock"
  }
}
