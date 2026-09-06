//// =============================================================================
//// [C3I-SIL6-MSTS] OCaml bridge — typed Gleam surface
//// -----------------------------------------------------------------------------
//// Wraps the `c3i_ocaml_nif` Erlang shim over the OCaml RETE-UL / Gospel
//// substrate. The NIF returns JSON strings; this module gives them types.
////
//// Fail-closed by construction: any response that is not an explicit pass is a
//// rejection. A malformed, empty, or unrecognised payload rejects — it never
//// falls through to `GatePassed`.
//// =============================================================================

import gleam/string

/// Outcome of a RETE-UL safety-gate evaluation.
///
/// Both variants carry the raw JSON as the final field so callers can inspect
/// diagnostics without this module having to model the whole payload.
pub type GateResult {
  /// Gate passed. First field is the verdict token, second the raw JSON.
  GatePassed(String, String)
  /// Gate rejected. First field is the extracted reason, second the raw JSON.
  GateRejected(String, String)
}

@external(erlang, "c3i_ocaml_nif", "version")
fn nif_version() -> String

@external(erlang, "c3i_ocaml_nif", "rete_eval")
fn nif_rete_eval(facts: String) -> String

@external(erlang, "c3i_ocaml_nif", "gospel_verify")
fn nif_gospel_verify(spec: String, payload: String) -> String

@external(erlang, "c3i_ocaml_nif", "zenoh_dispatch")
fn nif_zenoh_dispatch(topic: String, payload: String) -> String

@external(erlang, "c3i_ocaml_nif", "parity_check")
fn nif_parity_check(scenario: String) -> String

/// Version string of the linked OCaml substrate.
pub fn version() -> String {
  nif_version()
}

/// Evaluate comma-separated `key=value` facts against the closed RETE-UL schema.
///
/// Rejects fail-closed on: missing mandatory keys, unknown keys, invalid boolean
/// values, duplicate keys, buffer overflow, and embedded NUL.
pub fn evaluate_gate(facts: String) -> GateResult {
  let raw = nif_rete_eval(facts)
  case string.contains(raw, "\"verdict\":\"pass\"") {
    True -> GatePassed("pass", raw)
    False -> GateRejected(extract_reason(raw), raw)
  }
}

/// Verify a payload against a named Gospel contract.
/// `Ok(raw)` when the substrate reports `"valid":true`, `Error(raw)` otherwise.
pub fn verify_contract(
  spec: String,
  payload: String,
) -> Result(String, String) {
  let raw = nif_gospel_verify(spec, payload)
  case string.contains(raw, "\"valid\":true") {
    True -> Ok(raw)
    False -> Error(raw)
  }
}

/// Dispatch a payload over Zenoh through the OCaml substrate.
/// Returns the raw receipt JSON, which carries a `receipt_digest` on success.
pub fn zenoh_dispatch(topic: String, payload: String) -> String {
  nif_zenoh_dispatch(topic, payload)
}

/// Run a named differential-parity scenario against the frozen reference.
///
/// The substrate answers with `frozen_reference_intact`, not a `valid` field —
/// parity is defined as the evidence store still matching the frozen reference.
/// `Ok(raw)` when intact, `Error(raw)` when it has diverged.
pub fn verify_parity(scenario: String) -> Result(String, String) {
  let raw = nif_parity_check(scenario)
  case string.contains(raw, "\"frozen_reference_intact\":true") {
    True -> Ok(raw)
    False -> Error(raw)
  }
}

/// Pull the `"reason"` field out of a rejection payload.
///
/// Deliberately string-based rather than a JSON parse: this runs on the
/// fail-closed path, where the payload may itself be malformed, and it must
/// still yield something an operator can read.
fn extract_reason(raw: String) -> String {
  case string.split_once(raw, "\"reason\":\"") {
    Ok(#(_, rest)) ->
      case string.split_once(rest, "\"") {
        Ok(#(reason, _)) -> reason
        Error(_) -> raw
      }
    Error(_) -> raw
  }
}
