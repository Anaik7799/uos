//// T22 documentation/dashboard truth tests.
////
//// These are negative controls for the epistemic release gates: refusal and
//// other non-operational verdicts must never be documented as operational,
//// a completed task count alone can never turn the dashboard green, and a
//// summary wrapper claim can never override a raw review verdict.

import cepaf_gleam/mcp/epistemic_gates.{
  type CapabilityVerdict, type MatrixCell, type ReviewRecord, MatrixCell,
  Operational, Refused, ReviewRecord, Stale, Unavailable, Unknown,
  compute_dashboard_readiness, dev_verified_status, evaluate_dev_acceptance,
  hold_status, not_admitted, reconcile_review_verdict,
  render_capability_doc_status,
}
import cepaf_gleam/mcp/types.{type ToolError, ToolError}
import gleam/string
import gleeunit/should

fn review(
  candidate: String,
  raw_verdict: String,
  critical_findings: Int,
) -> ReviewRecord {
  ReviewRecord(
    reviewer: "independent-reviewer",
    candidate_id: candidate,
    raw_verdict: raw_verdict,
    critical_findings: critical_findings,
  )
}

fn error_code(result: Result(String, ToolError)) -> String {
  case result {
    Error(ToolError(code, _, _)) -> code
    Ok(_) -> "OK"
  }
}

fn assert_non_operational(status: String) -> Nil {
  status |> should.not_equal("operational")
  status |> should.not_equal("admitted")
  status |> should.not_equal("operational_verified_dev")
  status |> string.contains("non_operational") |> should.be_true
  status |> string.contains("admitted") |> should.be_false
  Nil
}

pub fn refusal_is_not_operational_in_docs_test() {
  render_capability_doc_status(Operational("fresh runtime probe"))
  |> should.equal("operational_verified_dev")

  let refused =
    render_capability_doc_status(Refused("TOOL_UNAVAILABLE", "backend error"))
  refused |> should.equal("refused_non_operational:TOOL_UNAVAILABLE")
  assert_non_operational(refused)

  let unavailable =
    render_capability_doc_status(Unavailable("no runtime binding"))
  unavailable |> should.equal("unavailable_non_operational:no runtime binding")
  assert_non_operational(unavailable)

  let unknown = render_capability_doc_status(Unknown("runtime_not_probed"))
  unknown |> should.equal("unknown_non_operational:runtime_not_probed")
  assert_non_operational(unknown)

  let stale: CapabilityVerdict = Stale("cand-B")
  let stale_status = render_capability_doc_status(stale)
  stale_status |> should.equal("stale_non_operational:cand-B")
  assert_non_operational(stale_status)
}

pub fn completed_task_alone_cannot_turn_dashboard_green_test() {
  // Every task completed, but no positive cell evidence and no reviews.
  compute_dashboard_readiness(10, 10, 0, 5, "cand-A", [])
  |> should.equal(hold_status)

  // Cells covered, but still no independent review.
  compute_dashboard_readiness(10, 10, 5, 5, "cand-A", [])
  |> should.equal(hold_status)

  // Reviews present, but no positive cell coverage.
  compute_dashboard_readiness(10, 10, 0, 5, "cand-A", [
    review("cand-A", "PASS", 0),
  ])
  |> should.equal(hold_status)

  // A failing raw review keeps the dashboard on hold.
  compute_dashboard_readiness(10, 10, 5, 5, "cand-A", [
    review("cand-A", "FAIL", 0),
  ])
  |> should.equal(hold_status)

  // Only full evidence plus independent raw-PASS reviews is development ready,
  // and even then it is never a sovereign system admission.
  compute_dashboard_readiness(10, 10, 5, 5, "cand-A", [
    review("cand-A", "PASS", 0),
  ])
  |> should.equal(dev_verified_status)
  dev_verified_status
  |> string.contains("NOT_SYSTEM_ADMITTED")
  |> should.be_true
  dev_verified_status |> should.not_equal("admitted")
  dev_verified_status |> should.not_equal("admitted_system")
}

pub fn raw_review_cannot_be_overridden_test() {
  // A failing raw review with a claiming wrapper is a fail-closed conflict.
  reconcile_review_verdict(review("cand-A", "FAIL", 0), "cand-A", "PASS")
  |> error_code
  |> should.equal("WRAPPER_RAW_REVIEW_CONFLICT")

  reconcile_review_verdict(review("cand-A", "REJECTED", 0), "cand-A", "GREEN")
  |> error_code
  |> should.equal("RAW_REVIEW_BLOCKING")

  reconcile_review_verdict(review("cand-A", "HOLD", 1), "cand-A", "OVERRIDE")
  |> error_code
  |> should.equal("RAW_REVIEW_BLOCKING")

  // Stale candidate review is rejected even when the wrapper claims PASS.
  reconcile_review_verdict(review("cand-B", "FAIL", 0), "cand-A", "PASS")
  |> error_code
  |> should.equal("RAW_REVIEW_BLOCKING")

  // Only an active-candidate raw PASS is accepted; the wrapper is irrelevant.
  reconcile_review_verdict(review("cand-A", "pass", 0), "cand-A", "OVERRIDE")
  |> error_code
  |> should.equal("OK")
  reconcile_review_verdict(review("cand-A", "PASS", 0), "cand-A", "")
  |> error_code
  |> should.equal("OK")

  // A sovereign grant cannot manufacture admission without a raw review.
  let core_cells: List(MatrixCell) = [
    MatrixCell("core-tools", "core", "cand-A", True, False),
    MatrixCell("core-resources", "core", "cand-A", True, False),
  ]
  let no_review_decision =
    evaluate_dev_acceptance("cand-A", core_cells, True, True, [], True)
  no_review_decision.system_admission |> should.equal(not_admitted)
  no_review_decision.core_dev_ready |> should.be_false
  no_review_decision.mcp_full_dev_ready |> should.be_false
}
