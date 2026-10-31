//// Regressions from independent read-only Wave2 review. Backend actions below
//// are in-memory counters; they grant no operational mutation authority.

import cepaf_gleam/mcp/candidate_id
import cepaf_gleam/mcp/admission
import cepaf_gleam/mcp/principal
import cepaf_gleam/mcp/route_convergence
import cepaf_gleam/mcp/receipts
import cepaf_gleam/mcp/runtime_gateway as gateway
import cepaf_gleam/mcp/types
import cepaf_gleam/mcp/worker
import cepaf_gleam/mcp/wire
import gleam/dict
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should

@external(erlang, "mcp_review_resilience_test_ffi", "chronological_replay")
fn chronological_replay() -> Result(Nil, String)

pub fn newest_twenty_readonly_commits_survive_full_ledger_and_owner_restart_test() {
  chronological_replay() |> should.equal(Ok(Nil))
}

@external(erlang, "mcp_review_resilience_test_ffi", "private_owner_fault")
fn private_owner_fault(phase: String, check: fn(process.Subject(gateway.Message)) -> types.Outcome) -> Result(Nil, String)

fn private_fault(phase: String) {
  let root = "/home/an/NAS-setup/uos"
  let p = principal.from_launcher_env("codex", types.ClientProfile("codex"), root, "wave25-private-death")
  let ticket = admission.GrantTicket("wave25-in-memory-only", types.TaskScopedMutation, False, 9_999_999_999_999, root)
  private_owner_fault(phase, fn(subject) {
    gateway.dispatch_private_actor_with_timeouts(subject, p, "successor",
      "{\"params\":{\"arguments\":{\"intent_id\":\"wave25-" <> phase <> "\"}}}",
      wire.NormalizedMessage(wire.IntId(71), "tools/call", [#("name", "harness_read_file"), #("intent_id", "wave25-" <> phase)], ""),
      fn(_, route, tool, _, _) { Ok(gateway.PrivateBinding(
        Some(route_convergence.RouteGrant(route, [tool], ticket)),
        Some(admission.TaskFence("wave25-fixture", "read-only", "codex", 1, admission.TaskExecuting, ticket.expires_at_ms, Some(ticket))),
        fn() { #(Ok("{\"fixture\":true}"), None) },
      )) }, 1500, case phase { "late" -> 20 _ -> 1500 })
  }) |> should.equal(Ok(Nil))
}

pub fn private_reservation_owner_death_refuses_in_under_half_a_second_test() { private_fault("reserve") }
pub fn private_commit_owner_death_is_uncertain_in_under_half_a_second_test() { private_fault("commit") }

@external(erlang, "mcp_review_resilience_test_ffi", "native_guardian_recovery")
fn native_guardian_recovery() -> Result(Nil, String)

pub fn missing_native_guardian_recovers_without_crashing_ingress_test() {
  native_guardian_recovery() |> should.equal(Ok(Nil))
}

@external(erlang, "mcp_review_resilience_test_ffi", "registration_publication")
fn registration_publication() -> Result(Nil, String)

pub fn losing_supervisor_registration_restores_the_surviving_subject_test() {
  registration_publication() |> should.equal(Ok(Nil))
}

@external(erlang, "mcp_review_resilience_test_ffi", "native_minimum_budget")
fn native_minimum_budget() -> Result(Nil, String)

pub fn native_grants_require_the_original_timeout_minimum_budget_test() {
  native_minimum_budget() |> should.equal(Ok(Nil))
}

pub fn private_late_commit_reply_cannot_accumulate_in_the_caller_mailbox_test() { private_fault("late") }

fn committed(tool: String) -> receipts.ReceiptLedger {
  let #(first, ledger) =
    worker.run_isolated_with_receipts(
      receipts.new_ledger(candidate_id.current()),
      intent_id: "review-large-effect",
      route: "public",
      tool: tool,
      payload_hash: "review-payload-bound",
      action: fn() {
        worker.WorkerSuccess(
          "{\"payload\":\"" <> string.repeat("x", 20_000) <> "\"}",
        )
      },
    )
  let assert types.Complete(_, _) = first
  ledger
}

pub fn oversized_committed_effect_retains_replay_fence_and_never_reexecutes_test() {
  let bounded = gateway.bound_receipt_ledger(committed("plan_add"))
  dict.has_key(bounded.entries, "review-large-effect") |> should.be_true()
  let ran = process.new_subject()
  let #(replayed, _) =
    worker.run_isolated_with_receipts(
      bounded,
      intent_id: "review-large-effect",
      route: "public",
      tool: "plan_add",
      payload_hash: "review-payload-bound",
      action: fn() {
        process.send(ran, True)
        worker.WorkerSuccess("{\"duplicate_effect\":true}")
      },
    )
  process.receive(ran, 0) |> should.equal(Error(Nil))
  let assert types.Refused(error) = replayed
  error.code |> should.equal("REPLAY_PAYLOAD_NOT_RETAINED")
  error.retryability |> should.equal(types.ReconcileFirst)
}

pub fn oversized_readonly_payload_may_be_discarded_without_effect_risk_test() {
  let bounded = gateway.bound_receipt_ledger(committed("read_file"))
  dict.has_key(bounded.entries, "review-large-effect") |> should.equal(False)
}

@external(erlang, "mcp_review_resilience_test_ffi", "guardian_publication")
fn guardian_publication() -> Result(Nil, String)

pub fn recovered_guardian_publishes_only_after_both_ets_heirs_are_armed_test() {
  guardian_publication() |> should.equal(Ok(Nil))
}

@external(erlang, "mcp_review_resilience_test_ffi", "classification_cache_budget")
fn classification_cache_budget(ledger: receipts.ReceiptLedger) -> Result(Nil, String)

pub fn serial_checkpoints_classify_readonly_routes_at_most_once_per_loaded_code_test() {
  let #(first, ledger) =
    worker.run_isolated_with_receipts(
      receipts.new_ledger(candidate_id.current()),
      intent_id: "review-small-readonly",
      route: "public",
      tool: "read_file",
      payload_hash: "review-small-payload",
      action: fn() { worker.WorkerSuccess("{}") },
    )
  let assert types.Complete(_, _) = first
  classification_cache_budget(ledger) |> should.equal(Ok(Nil))
}

@external(erlang, "mcp_review_resilience_test_ffi", "ungranted_private_while_suspended")
fn ungranted_private_while_suspended() -> Result(Nil, String)

pub fn missing_private_grant_refuses_before_queuing_behind_suspended_owner_test() {
  ungranted_private_while_suspended() |> should.equal(Ok(Nil))
}

pub fn every_backpressure_wire_error_is_explicitly_retryable_test() {
  list.each(["GATEWAY_TIMEOUT", "GATEWAY_OVERLOADED", "RECEIPT_LEDGER_CAPACITY_EXCEEDED"], fn(code) {
    let response = gateway.standard_response(wire.IntId(71), "tools/call",
      types.Refused(types.ToolError(code, "before any effect", types.NonRetryable)))
    json.parse(response,decode.at(["error","code"],decode.int))
    |> should.equal(Ok(-32_001))
    json.parse(response,decode.at(["error","data","retryable"],decode.bool))
    |> should.equal(Ok(True))
    json.parse(response,decode.at(["error","data","code"],decode.string))
    |> should.equal(Ok(code))
  })
}

@external(erlang, "mcp_startup_prefetch_test_ffi", "run")
fn startup_prefetch() -> Result(Nil, String)

pub fn production_initialize_defers_sql_until_first_real_planning_request_test() {
  startup_prefetch() |> should.equal(Ok(Nil))
}
