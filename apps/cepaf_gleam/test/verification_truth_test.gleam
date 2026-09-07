import cepaf_gleam/verification/evidence_truth as truth
import gleam/list
import gleeunit/should

const candidate_root = "../.."
const runtime_receipt_sha = "000be681ed631163960f7876c992bf8a4a74973bc74caba52184e68bde8560a2"
const formal_receipt_sha = "bea5c13db9cb2a62552d747f435cb20e67c7edb44829ce8141365470985f38db"

fn valid_request() -> truth.VerificationRequest {
  truth.VerificationRequest(
    candidate_root: candidate_root,
    candidate_change_id: "change-e03",
    candidate_commit_id: "commit-e03",
    input_sha256: "input-e03",
    now_unix_seconds: 2000,
    max_receipt_age_seconds: 300,
    runtime_receipt: truth.ReceiptFile("apps/cepaf_gleam/test/fixtures/e03/candidate/receipts/runtime.json", runtime_receipt_sha),
    formal_receipt: truth.ReceiptFile("apps/cepaf_gleam/test/fixtures/e03/candidate/receipts/formal.json", formal_receipt_sha),
    existing_document: True,
    claimed_token_gated: True,
    claimed_parity: True,
    metric_inputs: [truth.MetricInput("coverage", 9, 10, "input-e03")],
  )
}

pub fn exact_missing_fixture_fails_closed_test() {
  let decision = truth.evaluate_fixture(
    "{\"runtime_receipt\":\"missing\",\"formal_receipt\":\"missing\",\"existing_document\":true,\"claimed_token_gated\":true,\"claimed_parity\":true,\"metric_inputs\":[]}",
  )
  decision.admitted |> should.be_false()
  decision.status |> should.equal("UNRUN")
  decision.exit_code |> should.equal(1)
  decision.metrics_available |> should.be_false()
  decision.missing_denominators |> should.equal(["metric_inputs"])
  truth.required_aspects |> list.length |> should.equal(17)
}

pub fn checked_receipts_admit_only_bound_candidate_test() {
  let decision = truth.evaluate(valid_request())
  decision.admitted |> should.be_true()
  decision.status |> should.equal("ADMITTED")
  decision.exit_code |> should.equal(0)
  decision.metrics_available |> should.be_true()

  let changed = truth.evaluate(
    truth.VerificationRequest(..valid_request(), candidate_commit_id: "changed"),
  )
  changed.admitted |> should.be_false()
  changed.status |> should.equal("REJECTED")
}

pub fn changed_inputs_and_staleness_revoke_admission_test() {
  let changed_input = truth.evaluate(
    truth.VerificationRequest(..valid_request(), input_sha256: "other-input"),
  )
  changed_input.admitted |> should.be_false()
  changed_input.status |> should.equal("REJECTED")

  let stale = truth.evaluate(
    truth.VerificationRequest(..valid_request(), now_unix_seconds: 2301),
  )
  stale.admitted |> should.be_false()
  stale.status |> should.equal("REJECTED")
}

pub fn document_and_claim_flags_have_no_admission_authority_test() {
  let decision = truth.evaluate(
    truth.VerificationRequest(
      ..valid_request(),
      runtime_receipt: truth.Missing,
      formal_receipt: truth.Missing,
    ),
  )
  decision.existing_document |> should.be_true()
  decision.claimed_token_gated |> should.be_true()
  decision.claimed_parity |> should.be_true()
  decision.admitted |> should.be_false()
}

pub fn missing_or_zero_denominators_are_visible_test() {
  let absent = truth.evaluate(
    truth.VerificationRequest(..valid_request(), metric_inputs: []),
  )
  absent.metrics_available |> should.be_false()
  absent.missing_denominators |> should.equal(["metric_inputs"])

  let zero = truth.evaluate(
    truth.VerificationRequest(
      ..valid_request(),
      metric_inputs: [truth.MetricInput("coverage", 0, 0, "input-e03")],
    ),
  )
  zero.metrics_available |> should.be_false()
  zero.missing_denominators |> should.equal(["coverage"])
  zero.admitted |> should.be_false()
}

pub fn arbitrary_receipt_strings_never_become_checked_receipts_test() {
  let decision = truth.evaluate_fixture(
    "{\"runtime_receipt\":\"same-digest\",\"formal_receipt\":\"same-digest\",\"existing_document\":true,\"claimed_token_gated\":true,\"claimed_parity\":true,\"metric_inputs\":[1]}",
  )
  decision.admitted |> should.be_false()
  decision.status |> should.equal("REJECTED")
}
