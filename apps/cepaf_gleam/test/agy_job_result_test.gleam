import cepaf_gleam/harness/agy_job_result.{type JobClaim, Completion, JobClaim}
import gleam/string
import gleeunit/should

const base_now_ns = 1_700_000_000_000_000_000

const ns_per_sec = 1_000_000_000

fn valid_claim() -> JobClaim {
  JobClaim(
    id: "uos/agy-operations/20261024-0642/result-classifier",
    worker: "agy-argon-runner-20261024",
    lease_owner: "agy-argon-runner-20261024",
    attempt: 1,
    state: "executing",
    lease_until_ns: base_now_ns + 360 * ns_per_sec,
  )
}

pub fn classify_valid_success_response_test() {
  let stdout =
    "{\"status\":\"SUCCESS\",\"response\":\"Implemented module\",\"conversation_id\":\"conv-123\"}"

  agy_job_result.classify(0, False, "", stdout)
  |> should.equal(
    Ok(Completion(conversation_id: "conv-123", response: "Implemented module")),
  )
}

pub fn classify_rejects_actual_empty_success_timeout_failure_test() {
  let stdout =
    "{\"status\":\"SUCCESS\",\"response\":\"\",\"conversation_id\":\"4046ce60-2545-496a-adfa-1b77728a06bb\"}"

  agy_job_result.classify(0, False, "", stdout)
  |> should.be_error

  let whitespace_stdout =
    "{\"status\":\"SUCCESS\",\"response\":\"   \\n\\t  \",\"conversation_id\":\"4046ce60-2545-496a-adfa-1b77728a06bb\"}"

  agy_job_result.classify(0, False, "", whitespace_stdout)
  |> should.be_error
}

pub fn classify_rejects_explicit_and_diagnostic_timeout_test() {
  let valid_stdout =
    "{\"status\":\"SUCCESS\",\"response\":\"ok\",\"conversation_id\":\"conv-1\"}"

  agy_job_result.classify(0, True, "", valid_stdout)
  |> should.be_error

  agy_job_result.classify(
    0,
    False,
    "WARN: Print Timeout while waiting for stream",
    valid_stdout,
  )
  |> should.be_error
}

pub fn classify_rejects_nonzero_exit_test() {
  let valid_stdout =
    "{\"status\":\"SUCCESS\",\"response\":\"ok\",\"conversation_id\":\"conv-1\"}"

  agy_job_result.classify(1, False, "", valid_stdout)
  |> should.be_error

  agy_job_result.classify(-1, False, "", valid_stdout)
  |> should.be_error
}

pub fn classify_rejects_malformed_and_missing_json_fields_test() {
  agy_job_result.classify(0, False, "", "{not-json")
  |> should.be_error

  agy_job_result.classify(
    0,
    False,
    "",
    "{\"status\":\"SUCCESS\",\"response\":\"ok\"}",
  )
  |> should.be_error

  agy_job_result.classify(
    0,
    False,
    "",
    "{\"status\":\"FAILED\",\"response\":\"ok\",\"conversation_id\":\"conv-1\"}",
  )
  |> should.be_error

  agy_job_result.classify(
    0,
    False,
    "",
    "{\"status\":\"SUCCESS\",\"response\":\"ok\",\"conversation_id\":\"\"}",
  )
  |> should.be_error
}

pub fn classify_stdout_byte_limit_boundary_test() {
  let prefix =
    "{\"status\":\"SUCCESS\",\"conversation_id\":\"c1\",\"response\":\""
  let suffix = "\"}"
  let overhead = string.byte_size(prefix) + string.byte_size(suffix)
  let exact_body = string.repeat("a", 1_048_576 - overhead)
  let exact_stdout = prefix <> exact_body <> suffix

  agy_job_result.classify(0, False, "", exact_stdout)
  |> should.be_ok

  let oversized_stdout = prefix <> exact_body <> "a" <> suffix
  agy_job_result.classify(0, False, "", oversized_stdout)
  |> should.be_error
}

pub fn authorize_valid_and_boundary_runtime_test() {
  let claim_min =
    JobClaim(
      ..valid_claim(),
      lease_until_ns: base_now_ns + { 1 + 30 } * ns_per_sec,
    )
  agy_job_result.authorize(
    claim_min,
    "uos/agy-operations/20261024-0642/result-classifier",
    "agy-argon-runner-20261024",
    1,
    base_now_ns,
    1,
  )
  |> should.equal(Ok(Nil))

  let claim_max =
    JobClaim(
      ..valid_claim(),
      lease_until_ns: base_now_ns + { 900 + 30 } * ns_per_sec,
    )
  agy_job_result.authorize(
    claim_max,
    "uos/agy-operations/20261024-0642/result-classifier",
    "agy-argon-runner-20261024",
    1,
    base_now_ns,
    900,
  )
  |> should.equal(Ok(Nil))

  agy_job_result.authorize(
    claim_max,
    "uos/agy-operations/20261024-0642/result-classifier",
    "agy-argon-runner-20261024",
    1,
    base_now_ns,
    0,
  )
  |> should.be_error

  agy_job_result.authorize(
    claim_max,
    "uos/agy-operations/20261024-0642/result-classifier",
    "agy-argon-runner-20261024",
    1,
    base_now_ns,
    901,
  )
  |> should.be_error
}

pub fn authorize_rejects_wrong_owner_id_attempt_state_test() {
  let claim = valid_claim()

  agy_job_result.authorize(
    claim,
    "uos/agy-operations/20261024-0642/other-job",
    "agy-argon-runner-20261024",
    1,
    base_now_ns,
    300,
  )
  |> should.be_error

  agy_job_result.authorize(
    claim,
    "",
    "agy-argon-runner-20261024",
    1,
    base_now_ns,
    300,
  )
  |> should.be_error

  agy_job_result.authorize(
    claim,
    "uos/agy-operations/20261024-0642/result-classifier",
    "other-worker",
    1,
    base_now_ns,
    300,
  )
  |> should.be_error

  let mismatched_lease_owner =
    JobClaim(..claim, lease_owner: "stolen-lease-owner")
  agy_job_result.authorize(
    mismatched_lease_owner,
    "uos/agy-operations/20261024-0642/result-classifier",
    "agy-argon-runner-20261024",
    1,
    base_now_ns,
    300,
  )
  |> should.be_error

  agy_job_result.authorize(
    claim,
    "uos/agy-operations/20261024-0642/result-classifier",
    "agy-argon-runner-20261024",
    2,
    base_now_ns,
    300,
  )
  |> should.be_error

  let zero_attempt = JobClaim(..claim, attempt: 0)
  agy_job_result.authorize(
    zero_attempt,
    "uos/agy-operations/20261024-0642/result-classifier",
    "agy-argon-runner-20261024",
    0,
    base_now_ns,
    300,
  )
  |> should.be_error

  let wrong_state = JobClaim(..claim, state: "pending")
  agy_job_result.authorize(
    wrong_state,
    "uos/agy-operations/20261024-0642/result-classifier",
    "agy-argon-runner-20261024",
    1,
    base_now_ns,
    300,
  )
  |> should.be_error
}

pub fn authorize_rejects_expired_or_insufficient_lease_and_invalid_now_test() {
  let insufficient_lease =
    JobClaim(
      ..valid_claim(),
      lease_until_ns: base_now_ns + { 300 + 30 } * ns_per_sec - 1,
    )

  agy_job_result.authorize(
    insufficient_lease,
    "uos/agy-operations/20261024-0642/result-classifier",
    "agy-argon-runner-20261024",
    1,
    base_now_ns,
    300,
  )
  |> should.be_error

  let expired_lease = JobClaim(..valid_claim(), lease_until_ns: base_now_ns - 1)

  agy_job_result.authorize(
    expired_lease,
    "uos/agy-operations/20261024-0642/result-classifier",
    "agy-argon-runner-20261024",
    1,
    base_now_ns,
    300,
  )
  |> should.be_error

  agy_job_result.authorize(
    valid_claim(),
    "uos/agy-operations/20261024-0642/result-classifier",
    "agy-argon-runner-20261024",
    1,
    0,
    300,
  )
  |> should.be_error
}
