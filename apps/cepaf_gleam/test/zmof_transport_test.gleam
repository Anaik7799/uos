//// =============================================================================
//// [C3I-SIL6-MSTS] TEST CONTRACT: ZMOF Transport & Backplane Verification
//// =============================================================================

import cepaf_gleam/zenoh/zmof_transport.{
  ConstitutionalStream, CrdtMeshSync, MoZRequest, MoZResponse,
  MoZReqPayload, MoZResPayload, OoZSpan, OoZSpanPayload,
  classify_topic, crdt_sync_topic, decode_moz_request, decode_moz_response,
  decode_ooz_span, encode_moz_request, encode_moz_response, encode_ooz_span,
  moz_req_topic, moz_res_topic, ooz_topic,
}
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn ooz_topic_generation_and_classification_test() {
  let topic = ooz_topic("l4_system", "podman_controller_01")
  topic
  |> should.equal("indrajaal/otel/span/l4_system/podman_controller_01")

  let classified = classify_topic(topic)
  classified
  |> should.equal(Ok(OoZSpan(layer: "l4_system", entity_id: "podman_controller_01")))
}

pub fn moz_req_topic_generation_and_classification_test() {
  let topic = moz_req_topic("plan_list", "req-12345")
  topic
  |> should.equal("indrajaal/mcp/req/plan_list/req-12345")

  let classified = classify_topic(topic)
  classified
  |> should.equal(Ok(MoZRequest(tool: "plan_list", req_id: "req-12345")))
}

pub fn moz_res_topic_generation_and_classification_test() {
  let topic = moz_res_topic("req-12345")
  topic
  |> should.equal("indrajaal/mcp/res/req-12345")

  let classified = classify_topic(topic)
  classified
  |> should.equal(Ok(MoZResponse(req_id: "req-12345")))
}

pub fn crdt_sync_topic_generation_and_classification_test() {
  let topic = crdt_sync_topic("node-alpha-42")
  topic
  |> should.equal("indrajaal/crdt/sync/node-alpha-42")

  let classified = classify_topic(topic)
  classified
  |> should.equal(Ok(CrdtMeshSync(node_id: "node-alpha-42")))
}

pub fn constitutional_stream_classification_test() {
  let topic = "indrajaal/l0/const/2oo3/vote"
  let classified = classify_topic(topic)
  classified
  |> should.equal(Ok(ConstitutionalStream(topic: topic)))
}

pub fn invalid_topic_classification_test() {
  classify_topic("invalid/topic/path")
  |> should.equal(Error(Nil))
}

pub fn ooz_span_roundtrip_test() {
  let span =
    OoZSpanPayload(
      trace_id: "4bf92f3577b34da6a3ce929d0e0e4736",
      span_id: "00f067aa0ba902b7",
      name: "prajna.lyapunov_eval",
      layer: "l0_constitutional",
      start_time_us: 1725720000000000,
      end_time_us: 1725720000002500,
      status: "OK",
    )

  let encoded = encode_ooz_span(span)
  let decoded = decode_ooz_span(encoded)
  decoded
  |> should.equal(Ok(span))
}

pub fn moz_request_roundtrip_test() {
  let req =
    MoZReqPayload(
      req_id: "moz-req-8899",
      tool: "plan_status",
      arguments_json: "{\"plan_id\":\"ev-94\"}",
      caller_id: "worker-node-1",
      timestamp_us: 1725720001000000,
    )

  let encoded = encode_moz_request(req)
  let decoded = decode_moz_request(encoded)
  decoded
  |> should.equal(Ok(req))
}

pub fn moz_response_roundtrip_test() {
  let res =
    MoZResPayload(
      req_id: "moz-req-8899",
      success: True,
      result_json: "{\"status\":\"active\"}",
      error_msg: "",
      timestamp_us: 1725720001005000,
    )

  let encoded = encode_moz_response(res)
  let decoded = decode_moz_response(encoded)
  decoded
  |> should.equal(Ok(res))
}
