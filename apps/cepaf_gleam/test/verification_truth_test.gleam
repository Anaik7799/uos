import gleeunit/should

pub type VerificationInput {
  VerificationInput(
    runtime_receipt: String,
    formal_receipt: String,
    existing_document: Bool,
    claimed_token_gated: Bool,
    claimed_parity: Bool,
    metric_inputs: List(Float),
  )
}

pub type VerificationDecision {
  VerificationDecision(
    admitted: Bool,
    status: String,
    exit_code: Int,
    metrics_available: Bool,
  )
}

pub fn evaluate_verification_truth(input: VerificationInput) -> VerificationDecision {
  let has_runtime = input.runtime_receipt != "missing" && input.runtime_receipt != ""
  let has_formal = input.formal_receipt != "missing" && input.formal_receipt != ""
  let admitted = has_runtime && has_formal && input.existing_document

  let status = case admitted {
    True -> "ADMITTED"
    False -> "UNRUN"
  }

  let exit_code = case admitted {
    True -> 0
    False -> 1
  }

  let metrics_available = case input.metric_inputs {
    [] -> False
    _ -> True
  }

  VerificationDecision(
    admitted: admitted,
    status: status,
    exit_code: exit_code,
    metrics_available: metrics_available,
  )
}

pub fn missing_receipts_fail_admission_test() {
  let input = VerificationInput(
    runtime_receipt: "missing",
    formal_receipt: "missing",
    existing_document: True,
    claimed_token_gated: True,
    claimed_parity: True,
    metric_inputs: [],
  )

  let decision = evaluate_verification_truth(input)
  decision.admitted |> should.be_false()
  decision.status |> should.equal("UNRUN")
  decision.exit_code |> should.equal(1)
  decision.metrics_available |> should.be_false()
}

pub fn valid_receipts_admit_test() {
  let input = VerificationInput(
    runtime_receipt: "RCPT-RUNTIME-001",
    formal_receipt: "RCPT-FORMAL-001",
    existing_document: True,
    claimed_token_gated: True,
    claimed_parity: True,
    metric_inputs: [1.0, 2.0, 3.0],
  )

  let decision = evaluate_verification_truth(input)
  decision.admitted |> should.be_true()
  decision.status |> should.equal("ADMITTED")
  decision.exit_code |> should.equal(0)
  decision.metrics_available |> should.be_true()
}
