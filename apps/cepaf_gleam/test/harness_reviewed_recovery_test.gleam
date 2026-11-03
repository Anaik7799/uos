//// Ordinary DATA binding and actual default-refusing gateway only. No review
//// APPROVE, trusted grant, task write or authenticated reviewer is fabricated.

import cepaf_gleam/harness/admission as a
import cepaf_gleam/harness/files
import cepaf_gleam/harness/operations as ops
import cepaf_gleam/harness/value
import cepaf_gleam/mcp/admission as route_admission
import cepaf_gleam/mcp/candidate_id
import cepaf_gleam/mcp/principal
import cepaf_gleam/mcp/registry
import cepaf_gleam/mcp/route_convergence
import cepaf_gleam/mcp/runtime_gateway as gateway
import cepaf_gleam/mcp/supervisor
import cepaf_gleam/mcp/types
import cepaf_gleam/mcp/wire
import envoy
import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import simplifile

@external(erlang, "cepaf_gleam_ffi", "system_time_nanos")
fn now_ns() -> Int

pub fn actual_full_cli_report_binds_exact_snapshot_and_old_set_as_data_test() {
  let assert Ok(dir) = envoy.get("UOS_REVIEWED_RECOVERY_CASE")
  let assert Ok(proposal) = simplifile.read(dir <> "/admission-proposal.json")
  let assert Ok(raw) = simplifile.read(dir <> "/full-cli-report.json")
  let assert Ok(p) = a.recovery_proposal_data(proposal)
  let assert Ok(observed) = a.recovery_bind_observation_data(p, raw, now_ns())
  let output = a.recovery_observation_json(observed) |> json.to_string
  json.parse(output, decode.at(["status"], decode.string))
  |> should.equal(Ok("BOUND_OBSERVATION_DATA_ONLY"))
  json.parse(output, decode.at(["effect_authority"], decode.bool))
  |> should.equal(Ok(False))
  json.parse(output, decode.at(["authority"], decode.string))
  |> should.equal(Ok("NONE"))
  json.parse(output, decode.at(["report_sha256"], decode.string))
  |> should.equal(Ok(files.digest(raw)))
}

pub fn metadata_read_delegation_is_exact_target_data_not_identity_test() {
  let reviewer =
    value.Object([
      #("plan_id", value.Text("uos/private-reviewed-recovery")),
      #("task_id", value.Text("review")),
      #("worker", value.Text("reviewer-data-label")),
      #("session_id", value.Text("session-data-label")),
      #("attempt", value.Integer(1)),
    ])
  let document =
    value.Object([
      #(
        "recovery_review_tasks",
        value.Array([
          value.Object([
            #("target_plan", value.Text("uos/private-reviewed-recovery")),
            #("target_task", value.Text("target")),
            #("reviewer", reviewer),
          ]),
        ]),
      ),
    ])
  a.recovery_review_read_delegated(
    document,
    reviewer,
    "uos/private-reviewed-recovery",
    "target",
  )
  |> should.equal(Ok(Nil))
  // This is a predicate over DATA. No read_task, grant, APPROVE or execution.
}

pub fn typed_route_policy_allows_only_preparation_without_constructing_a_fence_test() {
  // An in-memory policy-input example, NOT an authenticated harness Grant or
  // completed review. No resolver/backend/prepare is called. Real missing-grant
  // refusal is exercised separately through dispatch_normalized below.
  let root = "/private/policy-data"
  let context =
    route_admission.AdmissionContext(
      principal.from_launcher_env(
        "policy-input-label",
        types.ClientProfile("codex"),
        root,
        "policy-session-label",
      ),
      route_admission.EnforcedMode,
      1000,
      root,
      None,
    )
  let ticket =
    route_admission.GrantTicket(
      "NOT_AN_AUTHENTICATED_GRANT",
      types.ScopedObservation,
      False,
      2000,
      root,
    )
  let assert Ok(call) =
    route_convergence.admit_converged(
      context,
      Some(route_convergence.RouteGrant(
        "successor",
        ["harness_recovery_prepare"],
        ticket,
      )),
      "successor",
      "harness_recovery_prepare",
      dict.new(),
    )
  call.spec.effect_class |> should.equal(types.ReadOnly)
  call.attempt |> should.equal(None)
  context.task_fence |> should.equal(None)
}

pub fn actual_gateway_readonly_prepare_refuses_without_grant_test() {
  let assert Ok(root) = envoy.get("UOS_REVIEWED_RECOVERY_ROOT")
  let assert Error(_) = a.load()
  let assert Ok(spec) = registry.lookup("successor", "harness_recovery_prepare")
  spec.effect_class |> should.equal(types.ReadOnly)
  list.contains(ops.names, "harness_recovery_prepare") |> should.be_true
  let candidate = candidate_id.from_root(root)
  let assert Ok(pool) = supervisor.start_worker_pool_for_candidate(1, candidate)
  let assert Ok(supervised) = supervisor.start_supervised_gateway()
  let state = gateway.new_state(root, candidate, pool, supervised)
  let p =
    principal.from_launcher_env(
      "ordinary-recovery-reader",
      types.ClientProfile("codex"),
      root,
      "ordinary-recovery-session",
    )
  let raw =
    json.object([
      #("jsonrpc", json.string("2.0")),
      #("id", json.int(1)),
      #("method", json.string("tools/call")),
      #(
        "params",
        json.object([
          #("name", json.string("harness_recovery_prepare")),
          #(
            "arguments",
            json.object([
              #("plan", json.string("uos/private-reviewed-recovery")),
              #("task", json.string("target")),
              #("intent_id", json.string("ordinary-prepare-only")),
              #(
                "review_path",
                json.string("governance/planning/unavailable.json"),
              ),
              #("review_sha256", json.string(string.repeat("0", 64))),
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
