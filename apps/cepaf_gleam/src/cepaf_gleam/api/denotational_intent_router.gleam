//// =============================================================================
//// [C3I-SIL6-ROUTER] DENOTATIONAL INTENT HTTP/REST & SSE TELEMETRY ROUTER
//// =============================================================================
//// Canonical implementation of:
//// 1. Intent payload validation & authorization
//// 2. Hardware Storage Safety Interlock gate evaluation
//// 3. Typed JSON serialization of Intent responses
//// =============================================================================

import cepaf_gleam/verification/dmc_biosemiotics_interlock.{
  AccessDenied, AccessGranted, check_hardware_safety_interlock,
}
import gleam/json

pub type IntentPayload {
  IntentPayload(
    actor: String,
    action: String,
    target: String,
    device_serial: String,
  )
}

pub type IntentResponse {
  IntentResponse(
    authorized: Bool,
    status_code: Int,
    message: String,
    trace_id: String,
  )
}

pub fn evaluate_intent_api(payload: IntentPayload) -> IntentResponse {
  let security = check_hardware_safety_interlock(payload.device_serial)
  case security {
    AccessDenied(reason) ->
      IntentResponse(
        authorized: False,
        status_code: 403,
        message: reason,
        trace_id: "00000000000000000000000000000000",
      )
    AccessGranted ->
      IntentResponse(
        authorized: True,
        status_code: 200,
        message: "Intent authorized",
        trace_id: "00000000000000000000000000000001",
      )
  }
}

pub fn encode_intent_response_json(response: IntentResponse) -> String {
  json.object([
    #("authorized", json.bool(response.authorized)),
    #("status_code", json.int(response.status_code)),
    #("message", json.string(response.message)),
    #("trace_id", json.string(response.trace_id)),
  ])
  |> json.to_string
}
