//// One ordinary local gateway/resource flow. Fixture principal, not live OIDC.
//// No metadata DB/provider, task DB, signer, key, or effect callback is supplied.

import cepaf_gleam/mcp/adapters/recovery_control
import cepaf_gleam/mcp/candidate_id
import cepaf_gleam/mcp/principal
import cepaf_gleam/mcp/runtime_gateway as gateway
import cepaf_gleam/mcp/supervisor
import cepaf_gleam/mcp/types
import cepaf_gleam/mcp/wire
import envoy
import gleam/dynamic/decode
import gleam/json
import gleam/string
import gleeunit/should

const metadata_uri = "uos://governance/recovery-trust-discovery"

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

pub fn ordinary_gateway_private_metadata_unknown_and_status_held_test() {
  let assert Ok(root) = envoy.get("UOS_READINESS_FIXTURE_ROOT")
  let candidate = candidate_id.from_root(root)
  candidate_id.is_valid(candidate) |> should.be_true
  let assert Ok(pool) = supervisor.start_worker_pool_for_candidate(1, candidate)
  let assert Ok(supervised) = supervisor.start_supervised_gateway()
  let state = gateway.new_state(root, candidate, pool, supervised)
  let assert Ok(owner) = gateway.start_state_owner(state)
  let p =
    principal.from_launcher_env(
      "ordinary-metadata-reader",
      types.ClientProfile("codex"),
      root,
      "metadata-session",
    )
  let #(raw, msg) = request("resources/list", json.object([]))
  let assert types.Complete(listed, _) =
    gateway.dispatch_public_actor(
      owner.data,
      p,
      types.Modern20260728,
      "public",
      raw,
      msg,
      now_ns() / 1_000_000,
    )
  string.contains(listed, metadata_uri) |> should.be_true
  let #(raw, msg) =
    request(
      "resources/read",
      json.object([
        #("uri", json.string(metadata_uri)),
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
  let assert Ok([metadata]) =
    json.parse(
      payload,
      decode.at(["contents"], decode.list(decode.at(["text"], decode.string))),
    )
  json.parse(metadata, decode.at(["status"], decode.string))
  |> should.equal(Ok("UNKNOWN"))
  json.parse(metadata, decode.at(["reason"], decode.string))
  |> should.equal(Ok("PROVIDER_UNCONFIGURED"))
  json.parse(metadata, decode.at(["authority"], decode.string))
  |> should.equal(Ok("NONE"))
  json.parse(metadata, decode.at(["trusted_roster"], decode.bool))
  |> should.equal(Ok(False))
  json.parse(metadata, decode.at(["custody_verified"], decode.bool))
  |> should.equal(Ok(False))
  json.parse(metadata, decode.at(["keys"], decode.list(decode.string)))
  |> should.equal(Ok([]))
  let #(raw, msg) =
    request(
      "tools/call",
      json.object([
        #("name", json.string("recovery_control_status")),
        #(
          "arguments",
          json.object([
            #("plan_id", json.string(recovery_control.fixed_plan)),
          ]),
        ),
      ]),
    )
  let assert types.Complete(status, _) =
    gateway.dispatch_public_actor(
      owner.data,
      p,
      types.Modern20260728,
      "public",
      raw,
      msg,
      now_ns() / 1_000_000,
    )
  json.parse(status, decode.at(["status"], decode.string))
  |> should.equal(Ok("HELD"))
  json.parse(status, decode.at(["mutation_enabled"], decode.bool))
  |> should.equal(Ok(False))
  json.parse(status, decode.at(["signing_enabled"], decode.bool))
  |> should.equal(Ok(False))
  json.parse(
    status,
    decode.at(["trust_metadata_resource", "uri"], decode.string),
  )
  |> should.equal(Ok(metadata_uri))
  json.parse(
    status,
    decode.at(["trust_metadata_resource", "access"], decode.string),
  )
  |> should.equal(Ok("PRINCIPAL_PRIVATE"))
}
