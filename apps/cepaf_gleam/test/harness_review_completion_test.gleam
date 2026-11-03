//// Ordinary private fixtures only. IO callbacks below are DATA examples, not
//// authenticated task/grant evidence. Actual public providers are never used.

import cepaf_gleam/harness/admission as a
import cepaf_gleam/harness/operations as ops
import cepaf_gleam/harness/review_completion as c
import cepaf_gleam/harness/review_dispatch
import cepaf_gleam/mcp/candidate_id
import cepaf_gleam/mcp/principal
import cepaf_gleam/mcp/registry
import cepaf_gleam/mcp/runtime_gateway as gateway
import cepaf_gleam/mcp/supervisor
import cepaf_gleam/mcp/types
import cepaf_gleam/mcp/wire
import envoy
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/json
import gleam/list
import gleam/string
import gleeunit/should
import simplifile

@external(erlang, "cepaf_gleam_ffi", "system_time_nanos")
fn now_ns() -> Int

pub fn strict_request_ceiling_is_distinct_from_retained_daily_liability_test() {
  let assert Ok(p) =
    c.prepare(
      c.PiOpenRouterArgon,
      "ordinary-review",
      "Ordinary fixture review",
      128,
    )
  { c.worst_case(p) < 20_000_000 } |> should.be_true
  c.retained_reservation_nanodollars |> should.equal(250_000_000)
  let maximum = 391 - string.byte_size(c.system_prompt)
  let assert Ok(edge) =
    c.prepare(
      c.PiOpenRouterArgon,
      "ordinary-edge",
      string.repeat("x", maximum),
      512,
    )
  c.worst_case(edge) |> should.equal(19_996_000)
  let assert Error("review_price_bound") =
    c.prepare(
      c.PiOpenRouterArgon,
      "ordinary-edge",
      string.repeat("x", maximum + 1),
      512,
    )
  let assert Error(_) =
    c.prepare(
      c.PiOpenRouterArgon,
      "ordinary-review",
      string.repeat("x", 500),
      512,
    )
}

pub fn other_backends_are_not_claimed_operational_test() {
  list.each([c.Claude, c.Agy, c.Codex], fn(b) {
    let assert Error("review_backend_unavailable") =
      c.prepare(b, "ordinary-review", "Review", 128)
    Nil
  })
}

pub fn actual_private_ledger_and_pinned_pi_sdk_fact_keep_cost_unknown_test() {
  let assert Ok(dir) = envoy.get("UOS_PI_REVIEW_CASE")
  let assert Ok(reserved) = simplifile.read(dir <> "/reservation.json")
  let assert Ok(reply) = simplifile.read(dir <> "/pi-reply.json")
  let assert Ok(p) =
    c.prepare(
      c.PiOpenRouterArgon,
      review_dispatch.logical_call_id(
        "uos/private-review",
        "TARGET",
        "ordinary-review",
      ),
      "Ordinary fixture review",
      128,
    )
  let events = process.new_subject()
  let io =
    c.Io(
      fn() {
        process.send(events, "authorize")
        Ok(Nil)
      },
      fn(_) {
        process.send(events, "reserve")
        Ok(reserved)
      },
      fn(_) {
        process.send(events, "invoke")
        Ok(c.Exchange(reply, c.Reaped))
      },
    )
  let assert Ok(output) = c.execute(p, io)
  list.each(["authorize", "reserve", "authorize", "invoke"], fn(expected) {
    process.receive(events, 1000) |> should.equal(Ok(expected))
  })
  json.parse(output, decode.at(["status"], decode.string))
  |> should.equal(Ok("ADVICE_OBSERVED_COST_UNKNOWN"))
  string.contains(output, "\"actual_provider_cost\":null") |> should.be_true
  string.contains(output, "\"automatic_retry\":false") |> should.be_true
}

pub fn production_transport_is_source_gated_not_a_config_flag_test() {
  review_dispatch.readiness()
  |> should.equal(Error(
    "review_transport_unavailable_clean_env_post_fence_runtime_closure",
  ))
  let output = review_dispatch.availability_json() |> json.to_string
  string.contains(output, "PREPARATION_ONLY_TRANSPORT_UNAVAILABLE")
  |> should.be_true
  let assert Error(
    "review_transport_unavailable_clean_env_post_fence_runtime_closure",
  ) =
    review_dispatch.prepare_available(
      c.PiOpenRouterArgon,
      "ordinary-gated",
      "Review",
      128,
    )
  ops.effect_readiness("harness_agent_review")
  |> should.equal(Error(
    "review_transport_unavailable_clean_env_post_fence_runtime_closure",
  ))
  // This readiness predicate grants nothing; the old build path still fences.
  ops.effect_readiness("harness_build") |> should.equal(Ok(Nil))
}

pub fn logical_paid_id_has_no_worker_grant_or_attempt_namespace_test() {
  // Independent Cryptokit SHA256 golden over plan NUL task NUL intent.
  review_dispatch.logical_call_id(
    "uos/private-review",
    "TARGET",
    "ordinary-review",
  )
  |> should.equal(
    "agent-review:734e80431d2cc32b7e4582047d9778ef95da9704fa928012b2c6d577eb7fe0b2",
  )
}

// Fixed fixture setup, not an MCP tool or production IO configuration.
pub fn write_case_files() {
  let assert Ok(dir) = envoy.get("UOS_PI_REVIEW_CASE")
  let assert Ok(p) =
    c.prepare(
      c.PiOpenRouterArgon,
      review_dispatch.logical_call_id(
        "uos/private-review",
        "TARGET",
        "ordinary-review",
      ),
      "Ordinary fixture review",
      128,
    )
  let assert Ok(_) = simplifile.write(dir <> "/body.json", c.body(p))
  let assert Ok(_) =
    simplifile.write(dir <> "/ledger-request.json", c.ledger_request(p))
  Nil
}

pub fn existing_gateway_refuses_ungranted_review_before_any_model_call_test() {
  let assert Error(_) = a.load()
  let assert Ok(root) = envoy.get("UOS_PI_REVIEW_ROOT")
  let assert Ok(spec) = registry.lookup("successor", "harness_agent_review")
  spec.effect_class |> should.equal(types.Mutating)
  let candidate = candidate_id.from_root(root)
  let assert Ok(pool) = supervisor.start_worker_pool_for_candidate(1, candidate)
  let assert Ok(supervised) = supervisor.start_supervised_gateway()
  let state = gateway.new_state(root, candidate, pool, supervised)
  let p =
    principal.from_launcher_env(
      "ordinary-review-reader",
      types.ClientProfile("codex"),
      root,
      "ordinary-review-session",
    )
  let raw =
    json.object([
      #("jsonrpc", json.string("2.0")),
      #("id", json.int(1)),
      #("method", json.string("tools/call")),
      #(
        "params",
        json.object([
          #("name", json.string("harness_agent_review")),
          #(
            "arguments",
            json.object([
              #("intent_id", json.string("ordinary-review")),
              #("backend", json.string("pi")),
              #("prompt", json.string("Ordinary fixture review")),
              #("max_tokens", json.string("128")),
            ]),
          ),
        ]),
      ),
    ])
    |> json.to_string
  let assert Ok(msg) = wire.decode_request(types.Modern20260728, raw)
  let #(outcome, _) =
    gateway.dispatch_normalized(
      state,
      p,
      types.Modern20260728,
      "successor",
      raw,
      msg,
      now_ns() / 1_000_000,
    )
  let output = gateway.standard_response(msg.id, msg.method, outcome)
  string.contains(output, "ROUTE_GRANT_REQUIRED") |> should.be_true
}
