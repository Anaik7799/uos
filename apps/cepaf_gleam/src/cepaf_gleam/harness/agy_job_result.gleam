import gleam/dynamic/decode
import gleam/json
import gleam/string

const max_stdout_bytes = 1_048_576

const lease_safety_margin_seconds = 30

const nanoseconds_per_second = 1_000_000_000

/// Pure snapshot of a job claim row fetched by the caller from the store.
/// The caller-supplied record is not authority by itself; `authorize` performs
/// a pure fail-closed check assuming the caller fetched the authoritative row.
pub type JobClaim {
  JobClaim(
    id: String,
    worker: String,
    lease_owner: String,
    attempt: Int,
    state: String,
    lease_until_ns: Int,
  )
}

/// Verified model response completion payload.
/// Represents ONLY that the model returned a non-empty response string for a
/// conversation; it never implies test success, admission, or task completion.
pub type Completion {
  Completion(conversation_id: String, response: String)
}

/// Fail-closed authorization of a claimed job row before execution.
pub fn authorize(
  claim: JobClaim,
  expected_id: String,
  expected_worker: String,
  expected_attempt: Int,
  now_ns: Int,
  runtime_seconds: Int,
) -> Result(Nil, String) {
  let required_lease_until_ns =
    now_ns
    + { runtime_seconds + lease_safety_margin_seconds }
    * nanoseconds_per_second

  case
    string.trim(expected_id) == ""
    || string.trim(claim.id) == ""
    || claim.id != expected_id
  {
    True -> Error("invalid or mismatched job id")
    False ->
      case
        string.trim(expected_worker) == ""
        || string.trim(claim.worker) == ""
        || string.trim(claim.lease_owner) == ""
        || claim.worker != expected_worker
        || claim.lease_owner != expected_worker
      {
        True -> Error("invalid or mismatched worker or lease_owner")
        False ->
          case
            expected_attempt <= 0
            || claim.attempt <= 0
            || claim.attempt != expected_attempt
          {
            True -> Error("invalid or mismatched attempt")
            False ->
              case claim.state != "executing" {
                True -> Error("job state must be executing")
                False ->
                  case runtime_seconds < 1 || runtime_seconds > 900 {
                    True -> Error("runtime_seconds must be in 1..900")
                    False ->
                      case now_ns <= 0 {
                        True -> Error("now_ns must be positive")
                        False ->
                          case claim.lease_until_ns < required_lease_until_ns {
                            True ->
                              Error(
                                "lease_until_ns does not cover runtime plus 30s safety margin",
                              )
                            False -> Ok(Nil)
                          }
                      }
                  }
              }
          }
      }
  }
}

/// Fail-closed classifier for raw CLI execution output.
pub fn classify(
  exit_code: Int,
  timed_out: Bool,
  stderr: String,
  stdout: String,
) -> Result(Completion, String) {
  let has_print_timeout =
    string.contains(string.lowercase(stderr), "print timeout")

  case timed_out || has_print_timeout {
    True -> Error("execution timed out")
    False ->
      case exit_code != 0 {
        True -> Error("non-zero exit code")
        False ->
          case string.byte_size(stdout) > max_stdout_bytes {
            True -> Error("stdout exceeds 1048576 bytes")
            False -> parse_and_validate_payload(stdout)
          }
      }
  }
}

fn parse_and_validate_payload(stdout: String) -> Result(Completion, String) {
  let decoder = {
    use status <- decode.field("status", decode.string)
    use response <- decode.field("response", decode.string)
    use conversation_id <- decode.field("conversation_id", decode.string)
    decode.success(#(status, response, conversation_id))
  }

  case json.parse(stdout, decoder) {
    Error(_) -> Error("invalid JSON or missing required fields")
    Ok(#(status, response, conversation_id)) ->
      case status != "SUCCESS" {
        True -> Error("status must be SUCCESS")
        False ->
          case string.trim(response) == "" {
            True -> Error("response must be non-empty")
            False ->
              case string.trim(conversation_id) == "" {
                True -> Error("conversation_id must be non-empty")
                False ->
                  Ok(Completion(
                    conversation_id: conversation_id,
                    response: response,
                  ))
              }
          }
      }
  }
}
