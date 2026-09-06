//// Candidate-bound production evidence evaluation.
////
//// Receipt names, historical documents, claimed capability gates, and claimed
//// parity never grant credit. A receipt is checked from bytes under the explicit
//// candidate root and binds its candidate, inputs, time window, result, and the
//// SHA-256 of an allowlisted producer artifact in that same candidate.

import gleam/json
import gleam/dynamic/decode
import gleam/list

pub type ReceiptLocator {
  Missing
  InvalidLocator(value: String)
  ReceiptFile(path: String, expected_sha256: String)
}

pub type MetricInput {
  MetricInput(name: String, numerator: Int, denominator: Int, input_sha256: String)
}

pub type VerificationRequest {
  VerificationRequest(
    candidate_root: String,
    candidate_change_id: String,
    candidate_commit_id: String,
    input_sha256: String,
    now_unix_seconds: Int,
    max_receipt_age_seconds: Int,
    runtime_receipt: ReceiptLocator,
    formal_receipt: ReceiptLocator,
    existing_document: Bool,
    claimed_token_gated: Bool,
    claimed_parity: Bool,
    metric_inputs: List(MetricInput),
  )
}

pub type ReceiptCheck {
  ReceiptCheck(kind: String, status: String, locator: String, errors: List(String))
}

pub type VerificationDecision {
  VerificationDecision(
    admitted: Bool,
    status: String,
    exit_code: Int,
    metrics_available: Bool,
    missing_denominators: List(String),
    candidate_change_id: String,
    candidate_commit_id: String,
    input_sha256: String,
    runtime: ReceiptCheck,
    formal: ReceiptCheck,
    existing_document: Bool,
    claimed_token_gated: Bool,
    claimed_parity: Bool,
    claims_grant_credit: Bool,
  )
}

type Receipt {
  Receipt(
    schema: String,
    kind: String,
    producer: String,
    producer_artifact: String,
    producer_artifact_sha256: String,
    candidate_change_id: String,
    candidate_commit_id: String,
    input_sha256: String,
    scopes: List(String),
    issued_at_unix_seconds: Int,
    expires_at_unix_seconds: Int,
    executed: Bool,
    outcome: String,
  )
}

@external(erlang, "evidence_truth_ffi", "read_candidate_file")
fn read_candidate_file(root: String, relative_path: String, cap: Int) -> Result(String, String)

@external(erlang, "evidence_truth_ffi", "sha256_candidate_file")
fn sha256_candidate_file(root: String, relative_path: String, cap: Int) -> Result(String, String)

@external(erlang, "evidence_truth_ffi", "unix_seconds")
pub fn unix_seconds() -> Int

fn receipt_decoder() -> decode.Decoder(Receipt) {
  use schema <- decode.field("schema", decode.string)
  use kind <- decode.field("kind", decode.string)
  use producer <- decode.field("producer", decode.string)
  use producer_artifact <- decode.field("producer_artifact", decode.string)
  use producer_artifact_sha256 <- decode.field("producer_artifact_sha256", decode.string)
  use candidate_change_id <- decode.field("candidate_change_id", decode.string)
  use candidate_commit_id <- decode.field("candidate_commit_id", decode.string)
  use input_sha256 <- decode.field("input_sha256", decode.string)
  use scopes <- decode.field("scopes", decode.list(decode.string))
  use issued_at_unix_seconds <- decode.field("issued_at_unix_seconds", decode.int)
  use expires_at_unix_seconds <- decode.field("expires_at_unix_seconds", decode.int)
  use executed <- decode.field("executed", decode.bool)
  use outcome <- decode.field("outcome", decode.string)
  decode.success(Receipt(
    schema:,
    kind:,
    producer:,
    producer_artifact:,
    producer_artifact_sha256:,
    candidate_change_id:,
    candidate_commit_id:,
    input_sha256:,
    scopes:,
    issued_at_unix_seconds:,
    expires_at_unix_seconds:,
    executed:,
    outcome:,
  ))
}

pub const required_aspects = [
  "harness", "hermes_harness", "hermes_wiki", "hermes_ops",
  "hermes_dependability", "hermes_ops_dashboard", "hermes_vcs",
  "hermes_agent_loop", "swarm", "system_engg", "hermes_nix",
  "hermes_sysml", "hermes_zellij", "hermes_vision", "hermes_toolchain",
  "hermes_fpp_authority", "hermes_dune_graph",
]

fn expected_producer(kind: String) -> #(String, String, String) {
  case kind {
    "runtime" -> #(
      "uos.candidate-snapshot",
      "tools/verification/candidate_snapshot.ml",
      "d133755696100822b355d1f1164ac1ecdd064142338efe2d2a0f41092954e507",
    )
    _ -> #(
      "uos.hermes-production-posture",
      "engines/hermes/modules/hermes_dependability/dependability_approval.ml",
      "ed12b980ee9f4124d6c06eaca6e4aaa5134a7fbfee5381b75cd51ad216eb932e",
    )
  }
}

fn error_if(condition: Bool, error: String) -> List(String) {
  case condition { True -> [] False -> [error] }
}

fn check_receipt(request: VerificationRequest, kind: String, locator: ReceiptLocator) -> ReceiptCheck {
  case locator {
    Missing -> ReceiptCheck(kind, "UNRUN", "missing", [kind <> " receipt missing"])
    InvalidLocator(value) ->
      ReceiptCheck(kind, "REJECTED", value, ["untyped receipt locator"])
    ReceiptFile(path, expected_sha256) -> {
      let bytes = read_candidate_file(request.candidate_root, path, 65_536)
      let actual_sha = sha256_candidate_file(request.candidate_root, path, 65_536)
      case bytes, actual_sha {
        Ok(text), Ok(digest) ->
          case json.parse(text, receipt_decoder()) {
            Error(_) -> ReceiptCheck(kind, "REJECTED", path, ["receipt JSON/schema invalid"])
            Ok(receipt) -> {
              let #(producer, artifact, pinned_artifact_sha) = expected_producer(kind)
              let artifact_sha =
                sha256_candidate_file(request.candidate_root, artifact, 2_097_152)
              let artifact_errors = case artifact_sha {
                Error(_) -> ["producer artifact unavailable"]
                Ok(value) ->
                  error_if(
                    value == pinned_artifact_sha
                      && value == receipt.producer_artifact_sha256,
                    "producer artifact is not the pinned authority",
                  )
              }
              let errors =
                []
                |> list.append(error_if(digest == expected_sha256, "receipt digest changed"))
                |> list.append(error_if(receipt.schema == "uos.evidence-receipt.v1", "receipt schema unsupported"))
                |> list.append(error_if(receipt.kind == kind, "receipt kind mismatch"))
                |> list.append(error_if(receipt.producer == producer, "producer authority not allowlisted"))
                |> list.append(error_if(receipt.producer_artifact == artifact, "producer artifact not allowlisted"))
                |> list.append(artifact_errors)
                |> list.append(error_if(receipt.candidate_change_id == request.candidate_change_id, "candidate change changed"))
                |> list.append(error_if(receipt.candidate_commit_id == request.candidate_commit_id, "candidate commit changed"))
                |> list.append(error_if(receipt.input_sha256 == request.input_sha256, "verification inputs changed"))
                |> list.append(error_if(receipt.scopes == required_aspects, "17-aspect scope incomplete or reordered"))
                |> list.append(error_if(receipt.issued_at_unix_seconds <= request.now_unix_seconds, "receipt is future-dated"))
                |> list.append(error_if(request.now_unix_seconds - receipt.issued_at_unix_seconds <= request.max_receipt_age_seconds, "receipt is stale"))
                |> list.append(error_if(receipt.expires_at_unix_seconds >= request.now_unix_seconds, "receipt expired"))
                |> list.append(error_if(receipt.executed, "producer did not execute"))
                |> list.append(error_if(receipt.outcome == "PASSED", "producer outcome is not PASSED"))
              case errors {
                [] -> ReceiptCheck(kind, "CHECKED", path, [])
                _ -> ReceiptCheck(kind, "REJECTED", path, errors)
              }
            }
          }
        _, _ -> ReceiptCheck(kind, "REJECTED", path, ["receipt unavailable or exceeds 65536 bytes"])
      }
    }
  }
}

fn missing_denominators(metrics: List(MetricInput)) -> List(String) {
  case metrics {
    [] -> ["metric_inputs"]
    _ -> list.filter_map(metrics, fn(metric) {
      case metric.denominator > 0 { True -> Error(Nil) False -> Ok(metric.name) }
    })
  }
}

pub fn evaluate(request: VerificationRequest) -> VerificationDecision {
  let runtime = check_receipt(request, "runtime", request.runtime_receipt)
  let formal = check_receipt(request, "formal", request.formal_receipt)
  let missing = missing_denominators(request.metric_inputs)
  let metrics_available = missing == [] && list.all(request.metric_inputs, fn(metric) {
    metric.input_sha256 == request.input_sha256
  })
  let admitted = runtime.status == "CHECKED" && formal.status == "CHECKED" && metrics_available
  let supplied_invalid = runtime.status == "REJECTED" || formal.status == "REJECTED"
  let status = case admitted, supplied_invalid {
    True, _ -> "ADMITTED"
    False, True -> "REJECTED"
    False, False -> "UNRUN"
  }
  VerificationDecision(
    admitted:,
    status:,
    exit_code: case admitted { True -> 0 False -> 1 },
    metrics_available:,
    missing_denominators: missing,
    candidate_change_id: request.candidate_change_id,
    candidate_commit_id: request.candidate_commit_id,
    input_sha256: request.input_sha256,
    runtime:,
    formal:,
    existing_document: request.existing_document,
    claimed_token_gated: request.claimed_token_gated,
    claimed_parity: request.claimed_parity,
    claims_grant_credit: False,
  )
}

pub fn unrun() -> VerificationDecision {
  evaluate(VerificationRequest(
    candidate_root: ".",
    candidate_change_id: "UNKNOWN",
    candidate_commit_id: "UNKNOWN",
    input_sha256: "UNKNOWN",
    now_unix_seconds: unix_seconds(),
    max_receipt_age_seconds: 0,
    runtime_receipt: Missing,
    formal_receipt: Missing,
    existing_document: False,
    claimed_token_gated: False,
    claimed_parity: False,
    metric_inputs: [],
  ))
}

type Fixture {
  Fixture(runtime_receipt: String, formal_receipt: String, existing_document: Bool, claimed_token_gated: Bool, claimed_parity: Bool)
}

fn fixture_decoder() -> decode.Decoder(Fixture) {
  use runtime_receipt <- decode.field("runtime_receipt", decode.string)
  use formal_receipt <- decode.field("formal_receipt", decode.string)
  use existing_document <- decode.field("existing_document", decode.bool)
  use claimed_token_gated <- decode.field("claimed_token_gated", decode.bool)
  use claimed_parity <- decode.field("claimed_parity", decode.bool)
  use _metric_inputs <- decode.field("metric_inputs", decode.list(decode.int))
  decode.success(Fixture(runtime_receipt, formal_receipt, existing_document, claimed_token_gated, claimed_parity))
}

fn locator_from_fixture(value: String) -> ReceiptLocator {
  case value { "missing" -> Missing "" -> Missing _ -> InvalidLocator(value) }
}

pub fn evaluate_fixture(text: String) -> VerificationDecision {
  case json.parse(text, fixture_decoder()) {
    Error(_) -> {
      let base = unrun()
      VerificationDecision(..base, status: "REJECTED")
    }
    Ok(fixture) ->
      evaluate(VerificationRequest(
        candidate_root: ".",
        candidate_change_id: "UNKNOWN",
        candidate_commit_id: "UNKNOWN",
        input_sha256: "UNKNOWN",
        now_unix_seconds: unix_seconds(),
        max_receipt_age_seconds: 0,
        runtime_receipt: locator_from_fixture(fixture.runtime_receipt),
        formal_receipt: locator_from_fixture(fixture.formal_receipt),
        existing_document: fixture.existing_document,
        claimed_token_gated: fixture.claimed_token_gated,
        claimed_parity: fixture.claimed_parity,
        metric_inputs: [],
      ))
  }
}

fn encode_check(check: ReceiptCheck) -> json.Json {
  json.object([
    #("kind", json.string(check.kind)),
    #("status", json.string(check.status)),
    #("locator", json.string(check.locator)),
    #("errors", json.array(check.errors, json.string)),
  ])
}

fn encode_aspect(name: String, status: String) -> json.Json {
  json.object([
    #("aspect", json.string(name)),
    #("status", json.string(status)),
    #("global_credit", json.bool(False)),
  ])
}

pub fn to_json(decision: VerificationDecision) -> String {
  json.object([
    #("schema", json.string("uos.evidence-decision.v1")),
    #("admitted", json.bool(decision.admitted)),
    #("status", json.string(decision.status)),
    #("exit_code", json.int(decision.exit_code)),
    #("metrics_available", json.bool(decision.metrics_available)),
    #("missing_denominators", json.array(decision.missing_denominators, json.string)),
    #("candidate_change_id", json.string(decision.candidate_change_id)),
    #("candidate_commit_id", json.string(decision.candidate_commit_id)),
    #("input_sha256", json.string(decision.input_sha256)),
    #("runtime_receipt", encode_check(decision.runtime)),
    #("formal_receipt", encode_check(decision.formal)),
    #("aspect_results", json.array(required_aspects, fn(name) { encode_aspect(name, decision.status) })),
    #("existing_document", json.bool(decision.existing_document)),
    #("claimed_token_gated", json.bool(decision.claimed_token_gated)),
    #("claimed_parity", json.bool(decision.claimed_parity)),
    #("claims_grant_credit", json.bool(decision.claims_grant_credit)),
  ])
  |> json.to_string
}

pub fn evaluate_fixture_file(path: String) -> VerificationDecision {
  case read_candidate_file(".", path, 65_536) {
    Ok(text) -> evaluate_fixture(text)
    Error(_) -> unrun()
  }
}
