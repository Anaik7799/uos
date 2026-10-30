//// Acceptance tests for the Feature Evidence MCP adapter (T13).
////
//// Verifies strict epistemic separation: completed tasks without a
//// candidate-bound execution receipt are never counted as complete; receipts
//// for a non-active candidate are stale; a summary wrapper can never override
//// a raw review verdict; and capability inventory keeps declaration,
//// implementation, observation, formal verification, and admission distinct
//// under the immutable EV93 ceiling.

import cepaf_gleam/mcp/adapters/features.{
  type ExecutionReceipt, CapabilityRecord, ExecutionReceipt,
  FeatureEvidenceStore, capability_inventory, compute_progress, execute,
  harness_execution_progress, harness_system_feature_observations,
  mcp_capability_inventory,
}
import cepaf_gleam/mcp/types.{type Outcome, Complete, Refused, ToolError}
import gleam/dict
import gleam/option.{type Option, None, Some}
import gleam/string
import gleeunit/should

fn base_receipt(
  task_id: String,
  candidate: String,
  raw: Option(String),
  wrapper: Option(String),
) -> ExecutionReceipt {
  ExecutionReceipt(
    feature_or_task_id: task_id,
    candidate_commit: candidate,
    exit_code: 0,
    raw_review_verdict: raw,
    wrapper_verdict: wrapper,
    output_sha256: "sha-" <> task_id,
  )
}

fn expect_refused(outcome: Outcome, code: String) -> Nil {
  case outcome {
    Refused(ToolError(actual, _, _)) -> actual |> should.equal(code)
    _ -> should.fail()
  }
}

pub fn completed_task_without_receipt_is_not_complete_test() {
  let store =
    FeatureEvidenceStore(
      active_candidate: "cand-A",
      admitted_ev_ceiling: 93,
      capabilities: [],
      completed_task_ids: ["T-missing"],
      receipts: dict.new(),
      intents: dict.new(),
    )

  let report = compute_progress(store)
  report.verified_complete_count |> should.equal(0)
  report.unverified_missing_receipt_count |> should.equal(1)
  report.stale_receipt_count |> should.equal(0)

  harness_system_feature_observations(store, "T-missing")
  |> expect_refused("MISSING_EXECUTION_RECEIPT")
}

pub fn wrong_candidate_receipt_is_stale_test() {
  let stale_receipt = base_receipt("T1", "cand-B", None, None)
  let store =
    FeatureEvidenceStore(
      active_candidate: "cand-A",
      admitted_ev_ceiling: 93,
      capabilities: [],
      completed_task_ids: ["T1"],
      receipts: dict.from_list([#("T1", stale_receipt)]),
      intents: dict.new(),
    )

  let report = compute_progress(store)
  report.verified_complete_count |> should.equal(0)
  report.unverified_missing_receipt_count |> should.equal(1)
  report.stale_receipt_count |> should.equal(1)

  harness_system_feature_observations(store, "T1")
  |> expect_refused("STALE_CANDIDATE_RECEIPT")
}

pub fn failed_non_completed_receipt_is_not_verified_test() {
  let receipt =
    ExecutionReceipt(
      feature_or_task_id: "T-inflight",
      candidate_commit: "cand-A",
      exit_code: 1,
      raw_review_verdict: None,
      wrapper_verdict: None,
      output_sha256: "sha-inflight",
    )
  let store =
    FeatureEvidenceStore(
      active_candidate: "cand-A",
      admitted_ev_ceiling: 93,
      capabilities: [],
      completed_task_ids: [],
      receipts: dict.from_list([#("T-inflight", receipt)]),
      intents: dict.new(),
    )

  case harness_system_feature_observations(store, "T-inflight") {
    Complete(payload, _) -> {
      string.contains(payload, "\"exit_code\":1") |> should.be_true()
      string.contains(payload, "\"verified_for_active_candidate\":false")
      |> should.be_true()
    }
    _ -> should.fail()
  }
}

pub fn completed_task_with_failed_receipt_refused_test() {
  let receipt =
    ExecutionReceipt(
      feature_or_task_id: "T-failed",
      candidate_commit: "cand-A",
      exit_code: 1,
      raw_review_verdict: None,
      wrapper_verdict: None,
      output_sha256: "sha-failed",
    )
  let store =
    FeatureEvidenceStore(
      active_candidate: "cand-A",
      admitted_ev_ceiling: 93,
      capabilities: [],
      completed_task_ids: ["T-failed"],
      receipts: dict.from_list([#("T-failed", receipt)]),
      intents: dict.new(),
    )

  harness_system_feature_observations(store, "T-failed")
  |> expect_refused("FAILED_EXECUTION_RECEIPT")
}

pub fn wrapper_raw_verdict_conflict_rejected_test() {
  let conflict_receipt =
    base_receipt("T2", "cand-A", Some("HOLD"), Some("APPROVED"))
  let store =
    FeatureEvidenceStore(
      active_candidate: "cand-A",
      admitted_ev_ceiling: 93,
      capabilities: [],
      completed_task_ids: ["T2"],
      receipts: dict.from_list([#("T2", conflict_receipt)]),
      intents: dict.new(),
    )

  harness_system_feature_observations(store, "T2")
  |> expect_refused("WRAPPER_RAW_VERDICT_CONFLICT")

  harness_execution_progress(store)
  |> expect_refused("WRAPPER_RAW_VERDICT_CONFLICT")
}

pub fn wrapper_pass_and_lowercase_approved_conflict_test() {
  let pass_receipt =
    base_receipt("T-pass", "cand-A", Some("REJECTED"), Some("PASS"))
  let pass_store =
    FeatureEvidenceStore(
      active_candidate: "cand-A",
      admitted_ev_ceiling: 93,
      capabilities: [],
      completed_task_ids: ["T-pass"],
      receipts: dict.from_list([#("T-pass", pass_receipt)]),
      intents: dict.new(),
    )

  harness_system_feature_observations(pass_store, "T-pass")
  |> expect_refused("WRAPPER_RAW_VERDICT_CONFLICT")

  let lower_receipt =
    base_receipt("T-lower", "cand-A", Some("REJECTED"), Some("approved"))
  let lower_store =
    FeatureEvidenceStore(
      active_candidate: "cand-A",
      admitted_ev_ceiling: 93,
      capabilities: [],
      completed_task_ids: ["T-lower"],
      receipts: dict.from_list([#("T-lower", lower_receipt)]),
      intents: dict.new(),
    )

  harness_system_feature_observations(lower_store, "T-lower")
  |> expect_refused("WRAPPER_RAW_VERDICT_CONFLICT")
}

pub fn execute_requires_task_or_feature_id_test() {
  let store =
    FeatureEvidenceStore(
      active_candidate: "cand-A",
      admitted_ev_ceiling: 93,
      capabilities: [],
      completed_task_ids: [],
      receipts: dict.new(),
      intents: dict.new(),
    )

  execute(store, "harness_system_feature_observations", dict.new())
  |> expect_refused("MISSING_ARGUMENT")

  execute(
    store,
    "harness_system_feature_observations",
    dict.from_list([#("task_id", ""), #("feature_id", "")]),
  )
  |> expect_refused("MISSING_ARGUMENT")
}

pub fn capability_inventory_keeps_five_epistemic_states_and_ev93_ceiling_test() {
  let capability =
    CapabilityRecord(
      id: "cap-1",
      route: "public",
      declaration_state: "declared",
      implementation_state: "implemented",
      execution_state: "observed",
      formal_state: "verified",
      admission_state: "not_admitted",
    )
  let store =
    FeatureEvidenceStore(
      active_candidate: "cand-A",
      admitted_ev_ceiling: 93,
      capabilities: [capability],
      completed_task_ids: [],
      receipts: dict.new(),
      intents: dict.new(),
    )

  let inventory = capability_inventory(store) |> should.be_ok
  inventory.total_routes |> should.equal(101)
  inventory.public_routes |> should.equal(65)
  inventory.development_routes |> should.equal(21)
  inventory.successor_routes |> should.equal(15)
  inventory.declared_count |> should.equal(1)
  inventory.implemented_count |> should.equal(1)
  inventory.observed_count |> should.equal(1)
  inventory.formal_count |> should.equal(1)
  inventory.admitted_count |> should.equal(0)

  let over_ceiling =
    FeatureEvidenceStore(
      active_candidate: "cand-A",
      admitted_ev_ceiling: 94,
      capabilities: [capability],
      completed_task_ids: [],
      receipts: dict.new(),
      intents: dict.new(),
    )
  mcp_capability_inventory(over_ceiling)
  |> expect_refused("PROVENANCE_CEILING_VIOLATION")
}
