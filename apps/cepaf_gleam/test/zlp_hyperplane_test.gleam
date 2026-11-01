//// 9-Modality Testing Gold Standard Verification Suite for `UOS-ZLP-v3`
//// (Supervised Lean 4.33.0 + Zig 0.16.0 + Gleam/OTP 29.0.5 + MCP + Zenoh Port Hyperplane)
////
//// Covers:
//// 1. Unit: Lean 4 `@[export]` C-ABI `verify_frame`, `scale_budget_gate`, `risk_priority_score`
//// 2. System: Live `:8080` Zenoh SSE push + `zenoh.handle_envelope_with_zlp` + `indrajaal_native_zenoh`
//// 3. TDD: 9 deterministic Red-Green security & constitutional invariant traps
//// 4. BDD: 4A Two-Lane out-of-order HoL overtaking + 4B post-`SIGKILL` Dual-ETS Zenoh SSE auto-replay
//// 5. Performance: Supervised `gen_server` + OS port RTT latency quantiles
//// 6. Scalability: 16 concurrent BEAM actors hammering lock-free `persistent_term` shard router
//// 7. Property-Based: 1,000 randomized out-of-order/replay/expired 64-window steps vs pure Oracle
//// 8. Adversarial Fuzzing: 2,500 hostile binary payloads (`0` worker crashes, Perceus `excl == 1`)
//// 9. Chaos Engineering: 6 staggered multi-shard `kill -9` strikes under live actor traffic

import cepaf_gleam/mcp/principal
import cepaf_gleam/mcp/supervisor
import cepaf_gleam/mcp/transports/zenoh
import cepaf_gleam/mcp/transports/zlp_hyperplane
import cepaf_gleam/mcp/types.{
  type Outcome, Complete, EvidenceRecord, Legacy20241105,
}
import cepaf_gleam/mcp/wire
import cepaf_gleam/otp_app
import cepaf_gleam/substrate/beam_cache
import cepaf_gleam/ui/wisp/router
import cepaf_gleam/zenoh/client as zenoh_client
import gleam/bit_array
import gleam/erlang/process
import gleam/list
import gleam/option.{Some}
import gleam/string
import gleeunit/should

@external(erlang, "zlp_v3_test_ffi", "is_zenoh_8080_reachable")
fn is_zenoh_8080_reachable() -> Bool

@external(erlang, "zlp_v3_test_ffi", "run_two_lane_hol_bdd")
fn run_two_lane_hol_bdd() -> Result(#(Int, Int, Int), String)

@external(erlang, "zlp_v3_test_ffi", "run_sigkill_sse_replay_bdd")
fn run_sigkill_sse_replay_bdd() -> Result(#(Int, Int), String)

@external(erlang, "zlp_v3_test_ffi", "run_performance_quantiles")
fn run_performance_quantiles(count: Int) -> Result(#(Int, Int), String)

@external(erlang, "zlp_v3_test_ffi", "run_scalability_swarm")
fn run_scalability_swarm(
  num_actors: Int,
  calls_per_actor: Int,
) -> Result(Int, String)

@external(erlang, "zlp_v3_test_ffi", "run_property_sliding_window")
fn run_property_sliding_window(trials: Int) -> Result(Int, String)

@external(erlang, "zlp_v3_test_ffi", "run_adversarial_fuzzing")
fn run_adversarial_fuzzing(trials: Int) -> Result(Int, String)

@external(erlang, "zlp_v3_test_ffi", "run_multi_shard_chaos")
fn run_multi_shard_chaos(calls_per_actor: Int) -> Result(Int, String)

@external(erlang, "zlp_v3_test_ffi", "test_indrajaal_native_zenoh_bridge")
fn test_indrajaal_native_zenoh_bridge() -> Result(Int, String)

fn complete_handler(
  _principal: principal.Principal,
  message: wire.NormalizedMessage,
) -> Outcome {
  Complete(
    message.canonical_json,
    EvidenceRecord(
      candidate: "zlp-v3-test",
      route: "zenoh/zlp",
      tool: "ping",
      declaration_state: "declared",
      implementation_state: "implemented",
      execution_state: "executed",
      formal_state: "verified",
      admission_state: "development",
      output_sha256: "0",
    ),
  )
}

pub fn zlp_v3_constitutional_provenance_and_unit_modality_1_test() {
  // SC-PROVENANCE-001 constitutional ceiling invariants
  zlp_hyperplane.admitted_ev_ceiling |> should.equal(93)
  zlp_hyperplane.system_admitted |> should.be_false()

  zlp_hyperplane.is_binary_available() |> should.be_true()
  let assert Ok(4) = supervisor.ensure_zlp_hyperplane_pool(shards: 4)
  supervisor.is_zlp_hyperplane_running() |> should.be_true()

  let assert Ok(_) = zlp_hyperplane.reset_shard(0)
  let assert Ok(health) = zlp_hyperplane.shard_health(0)
  { health.os_pid > 0 } |> should.be_true()
  health.excl |> should.equal(1)

  // Modality 1 (Unit): Direct Lean 4 @[export] verify_frame + scale_budget_gate + risk_priority_score
  let assert Ok(receipt) =
    zlp_hyperplane.verify_frame_on_shard(
      0,
      1,
      True,
      bit_array.from_string("{\"op\":\"unit\",\"ok\":true}"),
    )
  receipt.excl |> should.equal(1)
  { receipt.value > 0 } |> should.be_true()

  // 2 * 3 * 4 * 5 * 6 = 720, writers=1 (<2), spent=9,750,000 (<= 9,750,000), now=100 < lease=200
  let assert Ok(risk_receipt) =
    zlp_hyperplane.eval_scale_and_risk(
      active_writers: 1,
      active_reviewers: 0,
      is_writer_req: True,
      daily_spent_micro_usd: 9_750_000,
      now_us: 100,
      lease_expires_us: 200,
      safety_ready: True,
      dep_ready: True,
      criticality: 2,
      stpa: 3,
      fmea: 4,
      dependency: 5,
      impact: 6,
    )
  risk_receipt.excl |> should.equal(1)
  risk_receipt.lane_or_sub |> should.equal(1)
  risk_receipt.value |> should.equal(720)
}

pub fn zlp_v3_tdd_nine_fail_closed_traps_modality_3_test() {
  let assert Ok(4) = supervisor.ensure_zlp_hyperplane_pool(shards: 4)

  // Trap 1: Forbidden c3i/a2a payload prefix (Theorem T14, status 5)
  let assert Error(r1) =
    zlp_hyperplane.verify_frame_on_shard(
      1,
      0,
      False,
      bit_array.from_string("c3i/a2a/hijack"),
    )
  r1.status_code |> should.equal(5)
  r1.excl |> should.equal(1)

  // Trap 2: Forbidden c3i/a2a Zenoh publish topic (status 5)
  let assert Error(r2) =
    zlp_hyperplane.zenoh_publish("c3i/a2a/hijack", "{\"x\":1}")
  r2.status_code |> should.equal(5)

  // Trap 3: Directory traversal '..' in Zenoh topic (status 5)
  let assert Error(r3) =
    zlp_hyperplane.zenoh_publish("uos/sandbox/../escape", "{\"x\":1}")
  r3.status_code |> should.equal(5)

  // Trap 4: Leading '/' root Zenoh subscription barred (status 5)
  let assert Error(r4) =
    zlp_hyperplane.zenoh_subscribe("/leading_slash_barred", process.self())
  r4.status_code |> should.equal(5)

  // Trap 5: Zen 5 AVX-512 512-bit NUL-byte trap (status 2)
  let assert Error(r5) =
    zlp_hyperplane.verify_frame_on_shard(1, 0, True, <<"{\"a\":\"", 0, "\"}">>)
  r5.status_code |> should.equal(2)
  r5.excl |> should.equal(1)

  // Trap 6: JSON depth 33 > 32 overflow trap (status 3)
  let deep33 = string.repeat("[", 33) <> "1" <> string.repeat("]", 33)
  let assert Error(r6) =
    zlp_hyperplane.verify_frame_on_shard(
      1,
      0,
      True,
      bit_array.from_string(deep33),
    )
  r6.status_code |> should.equal(3)

  // Trap 7: Budget cap 9,750,001 + 250,000 > 10,000,000 micro-USD (Theorem T17, status 6)
  let assert Error(r7) =
    zlp_hyperplane.eval_scale_and_risk(
      1,
      0,
      True,
      9_750_001,
      100,
      200,
      True,
      True,
      2,
      3,
      4,
      5,
      6,
    )
  r7.status_code |> should.equal(6)

  // Trap 8: Strict `now_us < lease_expires_us` fence (`200 < 200` is False, status 6)
  let assert Error(r8) =
    zlp_hyperplane.eval_scale_and_risk(
      1,
      0,
      True,
      100_000,
      200,
      200,
      True,
      True,
      2,
      3,
      4,
      5,
      6,
    )
  r8.status_code |> should.equal(6)

  // Trap 9: Dependency unready (`dep_ready = False`) -> RiskScore == 0 (Theorem T18, status 6)
  let assert Error(r9) =
    zlp_hyperplane.eval_scale_and_risk(
      1,
      0,
      True,
      100_000,
      100,
      200,
      True,
      False,
      2,
      3,
      4,
      5,
      6,
    )
  r9.status_code |> should.equal(6)
  r9.value |> should.equal(0)
}

pub fn zlp_v3_gleam_zenoh_envelope_and_live_sse_system_modality_2_test() {
  let assert Ok(4) = supervisor.ensure_zlp_hyperplane_pool(shards: 4)
  list.each([0, 1, 2, 3], fn(s) {
    let assert Ok(_) = zlp_hyperplane.reset_shard(s)
    Nil
  })

  // Authenticated Gleam SignedZenohEnvelope + ZLP 64-window anti-replay gate (SC-HARNESS-MCP-001)
  let secret = "zlp-shared-secret"
  let topic = "indrajaal/mcp/request/client-zlp/req-42"
  let reply_topic = "indrajaal/mcp/response/client-zlp/req-42"
  let payload = "{\"jsonrpc\":\"2.0\",\"id\":\"42\",\"method\":\"ping\"}"
  let sig =
    zenoh.compute_signature(
      secret,
      topic,
      reply_topic,
      "actor-zlp",
      "agy-client",
      "/home/an/NAS-setup/uos",
      "sess-42",
      payload,
    )
  let env =
    zenoh.SignedZenohEnvelope(
      topic: topic,
      reply_topic: reply_topic,
      sender_actor: "actor-zlp",
      client_name: "agy-client",
      workspace_root: "/home/an/NAS-setup/uos",
      session_id: "sess-42",
      payload: payload,
      signature: sig,
    )

  let assert Ok(#(receipt, Some(#(pinned_reply, wire_body)))) =
    zenoh.handle_envelope_with_zlp(
      shared_secret: secret,
      profile: Legacy20241105,
      expected_client_id: "client-zlp",
      seq_id: 777,
      envelope: env,
      handler: complete_handler,
    )
  receipt.excl |> should.equal(1)
  { receipt.value > 0 } |> should.be_true()
  pinned_reply |> should.equal(reply_topic)
  string.contains(wire_body, "\"jsonrpc\":\"2.0\"") |> should.be_true()

  // Live Zenoh :8080 SSE push + indrajaal_native_zenoh bridge when router is reachable
  case is_zenoh_8080_reachable() {
    False -> Nil
    True -> {
      let sub_topic = "uos/sandbox/zlp_v3_gleam_test/system/**"
      let pub_topic = "uos/sandbox/zlp_v3_gleam_test/system/evt1"
      let assert Ok(#(shard_id, sub_receipt)) =
        zlp_hyperplane.zenoh_subscribe(sub_topic, process.self())
      sub_receipt.excl |> should.equal(1)
      process.sleep(80)
      zlp_hyperplane.flush_zenoh_pushes()

      let assert Ok(pub_receipt) =
        zlp_hyperplane.zenoh_publish(
          pub_topic,
          "{\"event\":\"live_gleam_zlp_sse_ok\",\"seq\":1}",
        )
      pub_receipt.excl |> should.equal(1)

      let assert Ok(push_evt) = zlp_hyperplane.await_zenoh_push(3000)
      push_evt.shard_id |> should.equal(shard_id)
      push_evt.excl |> should.equal(1)
      { push_evt.digest > 0 } |> should.be_true()
      string.contains(push_evt.json_payload, "live_gleam_zlp_sse_ok")
      |> should.be_true()

      // Verify upgraded indrajaal_native_zenoh.erl (open_session, subscribe, put)
      let assert Ok(_) = test_indrajaal_native_zenoh_bridge()
      Nil
    }
  }
}

pub fn zlp_v3_bdd_perf_scale_property_fuzz_chaos_modalities_4_to_9_test() {
  let assert Ok(4) = supervisor.ensure_zlp_hyperplane_pool(shards: 4)

  // Modality 4A (BDD): Two-Lane out-of-order HoL elimination
  let assert Ok(#(fast_p50_us, fast_total_us, heavy_total_us)) =
    run_two_lane_hol_bdd()
  { fast_p50_us < 1000 } |> should.be_true()
  { fast_total_us < heavy_total_us } |> should.be_true()

  // Modality 4B (BDD): Post-SIGKILL Dual-ETS Zenoh SSE auto-replay (when :8080 live)
  case is_zenoh_8080_reachable() {
    False -> Nil
    True -> {
      let assert Ok(#(pre_pid, post_pid)) = run_sigkill_sse_replay_bdd()
      { pre_pid != post_pid } |> should.be_true()
    }
  }

  // Modality 5 (Performance): Supervised gen_server + OS Port RTT quantiles
  let assert Ok(#(p50_us, p99_us)) = run_performance_quantiles(2000)
  { p50_us < 500 } |> should.be_true()
  { p99_us < 5000 } |> should.be_true()

  // Modality 6 (Scalability): 16 concurrent BEAM actors x 1,000 RPCs = 16,000 calls
  let assert Ok(rps) = run_scalability_swarm(16, 1000)
  { rps > 20_000 } |> should.be_true()

  // Modality 7 (Property-Based): 1,000 randomized 64-window steps vs pure reference Oracle
  let assert Ok(1000) = run_property_sliding_window(1000)

  // Modality 8 (Adversarial Fuzzing): 2,500 hostile binary frames, 0 crashes, excl == 1
  let assert Ok(fuzz_pid) = run_adversarial_fuzzing(2500)
  { fuzz_pid > 0 } |> should.be_true()

  // Modality 9 (Chaos Engineering): 6 staggered multi-shard kill -9 strikes under 8-actor load
  let assert Ok(chaos_ok_calls) = run_multi_shard_chaos(800)
  { chaos_ok_calls > 5000 } |> should.be_true()
  zlp_hyperplane.stop()
}

pub fn zlp_v3_project_integration_zenoh_client_otp_app_and_wisp_api_test() {
  // 1. OTP Application boot integration (otp_app.start/0)
  let app_state = otp_app.start()
  app_state.started |> should.be_true()
  beam_cache.get_config("zlp:hyperplane_pool") |> should.equal(Ok("running"))
  beam_cache.get_config("zlp:hyperplane_shards") |> should.equal(Ok("4"))

  // 2. Wisp HTTP Cockpit API telemetry (/api/v1/zlp/status & /api/zlp/health) while pool is running
  let running_json = router.route("/api/v1/zlp/status")
  string.contains(running_json, "\"backend\":\"uos_zlp_v3_otp29_port\"")
  |> should.be_true()
  string.contains(running_json, "\"status\":\"healthy\"") |> should.be_true()
  string.contains(running_json, "\"pool_running\":true") |> should.be_true()
  string.contains(running_json, "\"lean_theorems_proved\":20")
  |> should.be_true()
  string.contains(running_json, "\"zero_sorry_ax\":true") |> should.be_true()
  string.contains(running_json, "\"admitted_ev_ceiling\":93")
  |> should.be_true()
  string.contains(running_json, "\"application_admitted\":false")
  |> should.be_true()
  string.contains(running_json, "\"system_admitted\":false")
  |> should.be_true()
  string.contains(running_json, "\"shard_id\":0") |> should.be_true()

  let alias_json = router.route("/api/zlp/health")
  string.contains(alias_json, "\"backend\":\"uos_zlp_v3_otp29_port\"")
  |> should.be_true()

  // 3. Project-wide zenoh/client.gleam upgrade (ZlpHyperplaneSession + backward-compatible RestSession)
  let assert Ok(zlp_sess) = zenoh_client.open_zlp(4)
  zenoh_client.backend(zlp_sess) |> should.equal("zlp_v3_otp29_port")
  zenoh_client.supports_subscriptions(zlp_sess) |> should.be_true()

  let assert Ok(pref_sess) = zenoh_client.open_prefer_zlp("{}")
  zenoh_client.backend(pref_sess) |> should.equal("zlp_v3_otp29_port")
  zenoh_client.supports_subscriptions(pref_sess) |> should.be_true()

  // Fail-closed topic confinement through zenoh_client.put
  let assert Error(refusal_msg) =
    zenoh_client.put(zlp_sess, "c3i/a2a/hijack", "{\"x\":1}")
  string.contains(refusal_msg, "zlp_refused(status=5") |> should.be_true()

  case is_zenoh_8080_reachable() {
    False -> Nil
    True -> {
      // Legacy open("{}") backward compatibility: RestSession keeps supports_subscriptions == False
      let assert Ok(rest_sess) = zenoh_client.open("{}")
      zenoh_client.supports_subscriptions(rest_sess) |> should.be_false()
      zenoh_client.subscribe(
        rest_sess,
        "uos/sandbox/zlp_client_test/**",
        process.self(),
      )
      |> should.equal(Error("zenoh_rest_subscriptions_unsupported"))

      // Live subscribe + put + push delivery + get through zenoh_client ZlpHyperplaneSession
      let sub_key = "uos/sandbox/zlp_client_integration/**"
      let pub_key = "uos/sandbox/zlp_client_integration/item1"
      let assert Ok(Nil) =
        zenoh_client.subscribe(zlp_sess, sub_key, process.self())
      process.sleep(80)
      zlp_hyperplane.flush_zenoh_pushes()

      let assert Ok(Nil) =
        zenoh_client.put(
          zlp_sess,
          pub_key,
          "{\"client\":\"zenoh_client_zlp_ok\"}",
        )
      let assert Ok(evt) = zlp_hyperplane.await_zenoh_push(3000)
      string.contains(evt.json_payload, "zenoh_client_zlp_ok")
      |> should.be_true()

      let assert Ok(get_body) = zenoh_client.get(zlp_sess, pub_key)
      string.starts_with(string.trim(get_body), "[") |> should.be_true()
    }
  }

  // 4. Clean teardown & standby probe verification
  zlp_hyperplane.stop()
  let standby_json = router.route("/api/v1/zlp/status")
  string.contains(standby_json, "\"status\":\"standby\"") |> should.be_true()
  string.contains(standby_json, "\"pool_running\":false") |> should.be_true()
}
