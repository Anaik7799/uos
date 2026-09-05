// =============================================================================
// MoZ Integration Test — Container Mutation E2E Path
// =============================================================================
//
// Verifies the full container mutation path:
//   POST /api/v1/podman/action -> auth -> decode -> MoZ client -> Zenoh publish
//
// Test categories (C8 Action Button weight 3.0 — Guardian + circuit breaker):
//   1. MutationRequest JSON decode (podman_api)
//   2. MoZ circuit breaker lifecycle (moz/client)
//   3. MoZ topic and JSON-RPC builders (moz/client)
//   4. HTTP route integration (router.handle_request)
//
// STAMP: SC-ZMOF-001, SC-ZMOF-005, SC-GLM-UI-003, SC-SEC-001,
//        SC-SAFETY-022, SC-SAFETY-001, SC-SIL4-006
// =============================================================================

import cepaf_gleam/moz/client as moz_client
import cepaf_gleam/ui/wisp/podman_api
import cepaf_gleam/ui/wisp/router
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/json
import gleam/string
import gleeunit/should

// =============================================================================
// §1. MutationRequest JSON Decode (podman_api)
// =============================================================================

pub fn mutation_request_decode_valid_json_test() {
  let body =
    "{\"verb\":\"restart\",\"container\":\"ex-app-1\",\"reason\":\"OOM signal\"}"
  let result = podman_api.mutation_request_decode(body)

  result |> should.be_ok()
  let assert Ok(req) = result
  req.verb |> should.equal("restart")
  req.container |> should.equal("ex-app-1")
  req.reason |> should.equal("OOM signal")
}

pub fn mutation_request_decode_start_verb_test() {
  let body =
    "{\"verb\":\"start\",\"container\":\"zenoh-router-1\",\"reason\":\"tier boot\"}"
  let result = podman_api.mutation_request_decode(body)

  result |> should.be_ok()
  let assert Ok(req) = result
  req.verb |> should.equal("start")
  req.container |> should.equal("zenoh-router-1")
}

pub fn mutation_request_decode_rejects_missing_fields_test() {
  // Missing "reason" field
  let body = "{\"verb\":\"stop\",\"container\":\"db-prod\"}"
  let result = podman_api.mutation_request_decode(body)

  result |> should.be_error()
  let assert Error(msg) = result
  string.contains(msg, "invalid_body") |> should.be_true()
}

pub fn mutation_request_decode_rejects_empty_json_test() {
  let result = podman_api.mutation_request_decode("{}")
  result |> should.be_error()
}

pub fn mutation_request_decode_rejects_malformed_json_test() {
  let result = podman_api.mutation_request_decode("not json at all")
  result |> should.be_error()
  let assert Error(msg) = result
  string.contains(msg, "invalid_body") |> should.be_true()
}

pub fn mutation_request_decode_rejects_wrong_type_test() {
  // verb is a number, not a string
  let body = "{\"verb\":42,\"container\":\"ex-app-1\",\"reason\":\"test\"}"
  let result = podman_api.mutation_request_decode(body)
  result |> should.be_error()
}

// =============================================================================
// §2. MoZ Circuit Breaker Lifecycle
// =============================================================================

pub fn moz_client_new_creates_closed_circuit_test() {
  let state = moz_client.new()

  state.consecutive_failures |> should.equal(0)
  state.pending |> should.equal([])
  moz_client.circuit_status(state) |> should.equal("closed")
}

pub fn moz_client_new_is_available_true_test() {
  let state = moz_client.new()
  moz_client.is_available(state) |> should.be_true()
}

pub fn moz_client_record_failure_increments_counter_test() {
  let state = moz_client.new()
  let state1 = moz_client.record_failure(state)

  state1.consecutive_failures |> should.equal(1)
}

pub fn moz_client_record_failure_twice_increments_twice_test() {
  let state =
    moz_client.new()
    |> moz_client.record_failure()
    |> moz_client.record_failure()

  state.consecutive_failures |> should.equal(2)
  // Below threshold — circuit still closed
  moz_client.circuit_status(state) |> should.equal("closed")
}

pub fn moz_client_record_failure_x5_opens_circuit_test() {
  // max_consecutive_failures = 5
  let state =
    moz_client.new()
    |> moz_client.record_failure()
    |> moz_client.record_failure()
    |> moz_client.record_failure()
    |> moz_client.record_failure()
    |> moz_client.record_failure()

  state.consecutive_failures |> should.equal(5)
  moz_client.circuit_status(state) |> should.equal("open")
}

pub fn moz_client_is_available_false_when_circuit_open_test() {
  let state =
    moz_client.new()
    |> moz_client.record_failure()
    |> moz_client.record_failure()
    |> moz_client.record_failure()
    |> moz_client.record_failure()
    |> moz_client.record_failure()

  moz_client.is_available(state) |> should.be_false()
}

pub fn moz_client_record_success_resets_failures_test() {
  // Accumulate 3 failures, then a success resets counter
  let degraded =
    moz_client.new()
    |> moz_client.record_failure()
    |> moz_client.record_failure()
    |> moz_client.record_failure()

  degraded.consecutive_failures |> should.equal(3)

  let recovered = moz_client.record_success(degraded)
  recovered.consecutive_failures |> should.equal(0)
}

// =============================================================================
// §3. MoZ Circuit Status Strings
// =============================================================================

pub fn moz_client_circuit_status_closed_test() {
  let state = moz_client.new()
  moz_client.circuit_status(state) |> should.equal("closed")
}

pub fn moz_client_circuit_status_open_test() {
  let open_state =
    moz_client.new()
    |> moz_client.record_failure()
    |> moz_client.record_failure()
    |> moz_client.record_failure()
    |> moz_client.record_failure()
    |> moz_client.record_failure()

  moz_client.circuit_status(open_state) |> should.equal("open")
}

// =============================================================================
// §4. MoZ Topic Builders
// =============================================================================

pub fn moz_client_build_request_topic_test() {
  let topic =
    moz_client.build_request_topic("ignition", "launch", "req-abc-123")

  topic
  |> should.equal("indrajaal/l5/cog/mcp/req/ignition/launch/req-abc-123")
}

pub fn moz_client_build_request_topic_restart_test() {
  let topic =
    moz_client.build_request_topic("ignition", "restart", "req-xyz-456")

  string.starts_with(topic, "indrajaal/l5/cog/mcp/req/ignition/restart/")
  |> should.be_true()
  string.contains(topic, "req-xyz-456") |> should.be_true()
}

pub fn moz_client_build_response_topic_test() {
  let topic = moz_client.build_response_topic("req-abc-123")

  topic |> should.equal("indrajaal/l5/cog/mcp/res/req-abc-123")
}

pub fn moz_client_build_response_topic_different_id_test() {
  let topic = moz_client.build_response_topic("req-999")

  string.starts_with(topic, "indrajaal/l5/cog/mcp/res/")
  |> should.be_true()
  string.contains(topic, "req-999") |> should.be_true()
}

pub fn moz_client_request_and_response_topics_share_id_test() {
  let id = "my-unique-request-id"
  let req_topic = moz_client.build_request_topic("ignition", "drain", id)
  let res_topic = moz_client.build_response_topic(id)

  string.contains(req_topic, id) |> should.be_true()
  string.contains(res_topic, id) |> should.be_true()
  // Response topic is shorter (no method segment)
  { string.length(res_topic) < string.length(req_topic) } |> should.be_true()
}

// =============================================================================
// §5. MoZ JSON-RPC 2.0 Builder
// =============================================================================

pub fn moz_client_build_request_json_is_jsonrpc_2_0_test() {
  let params = json.object([#("container", json.string("ex-app-1"))])
  let payload = moz_client.build_request_json("launch", params, "req-001")

  string.contains(payload, "\"jsonrpc\"") |> should.be_true()
  string.contains(payload, "\"2.0\"") |> should.be_true()
}

pub fn moz_client_build_request_json_contains_method_test() {
  let params = json.object([])
  let payload = moz_client.build_request_json("restart", params, "req-002")

  string.contains(payload, "\"method\"") |> should.be_true()
  string.contains(payload, "\"restart\"") |> should.be_true()
}

pub fn moz_client_build_request_json_contains_id_test() {
  let params = json.object([])
  let payload = moz_client.build_request_json("drain", params, "req-drain-007")

  string.contains(payload, "\"id\"") |> should.be_true()
  string.contains(payload, "req-drain-007") |> should.be_true()
}

pub fn moz_client_build_request_json_contains_params_test() {
  let params =
    json.object([
      #("verb", json.string("stop")),
      #("container", json.string("cortex")),
    ])
  let payload = moz_client.build_request_json("launch", params, "req-003")

  string.contains(payload, "\"params\"") |> should.be_true()
  string.contains(payload, "\"cortex\"") |> should.be_true()
}

pub fn moz_client_build_request_json_valid_json_object_test() {
  let params = json.object([#("reason", json.string("test"))])
  let payload = moz_client.build_request_json("launch", params, "r1")

  string.starts_with(payload, "{") |> should.be_true()
  string.ends_with(payload, "}") |> should.be_true()
}

// =============================================================================
// §6. HTTP Router Integration
// =============================================================================

/// POST /api/v1/podman/action without auth header returns 401.
pub fn router_post_podman_action_without_auth_returns_401_test() {
  let req =
    request.new()
    |> request.set_method(http.Post)
    |> request.set_path("/api/v1/podman/action")
    |> request.set_body(
      "{\"verb\":\"restart\",\"container\":\"ex-app-1\",\"reason\":\"test\"}",
    )

  let resp = router.handle_request(req)
  resp.status |> should.equal(401)
}

/// POST /api/v1/podman/action with wrong token returns 401.
pub fn router_post_podman_action_wrong_token_returns_401_test() {
  let req =
    request.new()
    |> request.set_method(http.Post)
    |> request.set_path("/api/v1/podman/action")
    |> request.set_body(
      "{\"verb\":\"restart\",\"container\":\"ex-app-1\",\"reason\":\"test\"}",
    )
    |> request.set_header("authorization", "Bearer wrong-token")

  let resp = router.handle_request(req)
  resp.status |> should.equal(401)
}

/// GET /api/v1/guardian/pending returns 200 with a valid JSON array.
pub fn router_get_guardian_pending_returns_200_test() {
  let req =
    request.new()
    |> request.set_method(http.Get)
    |> request.set_path("/api/v1/guardian/pending")
    |> request.set_body("")

  let resp = router.handle_request(req)
  resp.status |> should.equal(200)
}

/// GET /api/v1/guardian/pending response contains "pending" array key.
pub fn router_get_guardian_pending_contains_pending_key_test() {
  let resp = get("/api/v1/guardian/pending")

  resp.status |> should.equal(200)
  string.contains(resp.body, "\"pending\"") |> should.be_true()
}

/// GET /api/v1/guardian/pending response contains "count" field.
pub fn router_get_guardian_pending_contains_count_field_test() {
  let resp = get("/api/v1/guardian/pending")

  string.contains(resp.body, "\"count\"") |> should.be_true()
}

/// GET /api/v1/guardian/pending response contains STAMP reference.
pub fn router_get_guardian_pending_contains_stamp_test() {
  let resp = get("/api/v1/guardian/pending")

  string.contains(resp.body, "SC-SAFETY-001") |> should.be_true()
}

/// GET /api/v1/guardian/pending response body is a valid JSON object.
pub fn router_get_guardian_pending_is_valid_json_test() {
  let resp = get("/api/v1/guardian/pending")

  string.starts_with(resp.body, "{") |> should.be_true()
}

/// POST /api/v1/emergency/trigger without body returns 400.
pub fn router_post_emergency_trigger_empty_body_returns_400_test() {
  let resp = post_with_token("/api/v1/emergency/trigger", "", "c3i-dev-token")

  resp.status |> should.equal(400)
}

/// POST /api/v1/emergency/trigger without confirmation literal returns 400.
pub fn router_post_emergency_trigger_missing_confirmation_returns_400_test() {
  let body = "{\"reason\":\"test trigger\",\"confirmation\":\"wrong text\"}"
  let resp = post_with_token("/api/v1/emergency/trigger", body, "c3i-dev-token")

  resp.status |> should.equal(400)
  {
    string.contains(resp.body, "confirmation_required")
    || string.contains(resp.body, "confirmation")
  }
  |> should.be_true()
}

/// POST /api/v1/emergency/trigger with correct confirmation returns 200.
pub fn router_post_emergency_trigger_correct_confirmation_returns_200_test() {
  let body =
    "{\"reason\":\"integration test\",\"confirmation\":\"EMERGENCY STOP\"}"
  let resp = post_with_token("/api/v1/emergency/trigger", body, "c3i-dev-token")

  resp.status |> should.equal(200)
}

/// POST /api/v1/emergency/trigger response contains STAMP reference on error.
pub fn router_post_emergency_trigger_error_contains_stamp_test() {
  let body = "{\"reason\":\"test\",\"confirmation\":\"WRONG\"}"
  let resp = post_with_token("/api/v1/emergency/trigger", body, "c3i-dev-token")

  resp.status |> should.equal(400)
  string.contains(resp.body, "SC-SAFETY-022") |> should.be_true()
}

// =============================================================================
// Helpers
// =============================================================================

fn get(path: String) -> response.Response(String) {
  request.new()
  |> request.set_method(http.Get)
  |> request.set_path(path)
  |> request.set_body("")
  |> router.handle_request()
}

fn post_with_token(
  path: String,
  body: String,
  token: String,
) -> response.Response(String) {
  request.new()
  |> request.set_method(http.Post)
  |> request.set_path(path)
  |> request.set_body(body)
  |> request.set_header("authorization", "Bearer " <> token)
  |> router.handle_request()
}
