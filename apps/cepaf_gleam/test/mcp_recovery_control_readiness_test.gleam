//// Ordinary real public-gateway readiness only. No authorizing private .inc,
//// key/custody provider, production configuration, task DB or effect callback.

import cepaf_gleam/mcp/adapters/planning_read
import cepaf_gleam/mcp/adapters/recovery_control
import cepaf_gleam/mcp/candidate_id
import cepaf_gleam/mcp/principal
import cepaf_gleam/mcp/registry
import cepaf_gleam/mcp/runtime_gateway as gateway
import cepaf_gleam/mcp/supervisor
import cepaf_gleam/mcp/types
import cepaf_gleam/mcp/wire
import envoy
import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/string
import gleeunit/should

@external(erlang, "cepaf_gleam_ffi", "system_time_nanos")
fn now_ns() -> Int

fn request(
  method: String,
  params: json.Json,
) -> #(String, wire.NormalizedMessage) {
  let raw =
    json.object([
      #("jsonrpc", json.string("2.0")),
      #("id", json.int(1)),
      #("method", json.string(method)),
      #("params", params),
    ])
    |> json.to_string
  let assert Ok(msg) = wire.decode_request(types.Modern20260728, raw)
  #(raw, msg)
}

pub fn registered_gateway_status_is_held_without_task_fence_test() {
  // The driver owns this unique source-bound workspace with NO Sa-plan DB.
  // An absent prerequisite is a real UNKNOWN observation, never invented rows.
  let assert Ok(root) = envoy.get("UOS_READINESS_FIXTURE_ROOT")
  let candidate = candidate_id.from_root(root)
  candidate_id.is_valid(candidate) |> should.be_true
  let assert Ok(pool) = supervisor.start_worker_pool_for_candidate(1, candidate)
  let assert Ok(supervised) = supervisor.start_supervised_gateway()
  let state = gateway.new_state(root, candidate, pool, supervised)
  let assert Ok(owner) = gateway.start_state_owner(state)
  let p =
    principal.from_launcher_env(
      "ordinary-readiness-reader",
      types.ClientProfile("codex"),
      root,
      "readiness-session",
    )
  let #(list_raw, list_msg) = request("tools/list", json.object([]))
  let assert types.Complete(listed, _) =
    gateway.dispatch_public_actor(
      owner.data,
      p,
      types.Modern20260728,
      "public",
      list_raw,
      list_msg,
      now_ns() / 1_000_000,
    )
  string.contains(listed, "recovery_control_status") |> should.be_true
  let assert Ok(spec) = registry.lookup("public", "recovery_control_status")
  spec.effect_class |> should.equal(types.ReadOnly)
  let #(raw, msg) =
    request(
      "tools/call",
      json.object([
        #("name", json.string("recovery_control_status")),
        #(
          "arguments",
          json.object([#("plan_id", json.string(recovery_control.fixed_plan))]),
        ),
      ]),
    )
  let assert types.Complete(payload, evidence) =
    gateway.dispatch_public_actor(
      owner.data,
      p,
      types.Modern20260728,
      "public",
      raw,
      msg,
      now_ns() / 1_000_000,
    )
  evidence.candidate |> should.equal(candidate)
  evidence.admission_state |> should.equal("not_admitted")
  json.parse(payload, decode.at(["status"], decode.string))
  |> should.equal(Ok("HELD"))
  json.parse(payload, decode.at(["production_binding"], decode.string))
  |> should.equal(Ok("UNCONFIGURED_BY_CONSTRUCTION"))
  json.parse(payload, decode.at(["plan_observation", "status"], decode.string))
  |> should.equal(Ok("UNKNOWN"))
  json.parse(payload, decode.at(["mutation_enabled"], decode.bool))
  |> should.equal(Ok(False))
  json.parse(payload, decode.at(["signing_enabled"], decode.bool))
  |> should.equal(Ok(False))
  json.parse(payload, decode.at(["candidate"], decode.string))
  |> should.equal(Ok(candidate))
}

pub fn observed_counts_do_not_create_lease_or_effect_authority_test() {
  let store =
    planning_read.sample_canonical_store(recovery_control.fixed_plan, [
      planning_read.CanonicalTaskRow(
        recovery_control.fixed_plan,
        "synthetic-executing",
        "Synthetic count only",
        "executing",
        "private-reader",
        1,
      ),
    ])
  let assert types.Complete(raw, _) =
    recovery_control.observe(
      store,
      "candidate-data-only",
      1,
      dict.from_list([#("plan_id", recovery_control.fixed_plan)]),
    )
  json.parse(raw, decode.at(["plan_observation", "executing"], decode.int))
  |> should.equal(Ok(1))
  json.parse(
    raw,
    decode.at(["plan_observation", "lease_validity"], decode.string),
  )
  |> should.equal(Ok("NOT_ASSESSED"))
  json.parse(raw, decode.at(["status"], decode.string))
  |> should.equal(Ok("HELD"))
  json.parse(raw, decode.at(["mutation_enabled"], decode.bool))
  |> should.equal(Ok(False))
}
