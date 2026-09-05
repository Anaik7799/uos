import cepaf_gleam/api/denotational_intent_router.{
  IntentPayload, IntentResponse, encode_intent_response_json,
  evaluate_intent_api,
}
import gleam/string
import gleeunit/should

pub fn authorize_valid_intent_test() {
  let payload =
    IntentPayload(
      actor: "claude_agent",
      action: "read_state",
      target: "doc_view",
      device_serial: "SAFE_NVME_01",
    )
  let response = evaluate_intent_api(payload)
  should.equal(response.authorized, True)
  should.equal(response.status_code, 200)
  should.equal(response.message, "Intent authorized")
  should.equal(response.trace_id, "00000000000000000000000000000001")
}

pub fn reject_locked_nvme_intent_test() {
  let payload =
    IntentPayload(
      actor: "unvetted_actor",
      action: "wipe_disk",
      target: "os_root",
      device_serial: "25503L801736",
    )
  let response = evaluate_intent_api(payload)
  should.equal(response.authorized, False)
  should.equal(response.status_code, 403)
  should.equal(response.message, "OS NVMe 25503L801736 is locked")
  should.equal(response.trace_id, "00000000000000000000000000000000")
}

pub fn encode_response_json_test() {
  let resp =
    IntentResponse(
      authorized: True,
      status_code: 200,
      message: "Intent authorized",
      trace_id: "00000000000000000000000000000001",
    )
  let json = encode_intent_response_json(resp)
  should.equal(string.contains(json, "\"authorized\":true"), True)
  should.equal(string.contains(json, "\"status_code\":200"), True)
  should.equal(string.contains(json, "\"message\":\"Intent authorized\""), True)
  should.equal(
    string.contains(json, "\"trace_id\":\"00000000000000000000000000000001\""),
    True,
  )
}
