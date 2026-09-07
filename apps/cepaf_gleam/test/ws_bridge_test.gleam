//// =============================================================================
//// [C3I-SIL6-MSTS] TEST CONTRACT: WebSocket Telemetry Bridge Verification
//// =============================================================================

import cepaf_gleam/ui/wisp/ws_bridge.{
  WsCRDTSync, WsHeartbeat, WsMoZReq, WsOoZSpan, WsPing, WsSubscribe,
  decode_upstream_command, encode_downstream_frame,
}
import cepaf_gleam/zenoh/zmof_transport.{MoZReqPayload, OoZSpanPayload}
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn downstream_ooz_span_encoding_test() {
  let span =
    OoZSpanPayload(
      trace_id: "trace-abc",
      span_id: "span-123",
      name: "prajna.step",
      layer: "l5_cognitive",
      start_time_us: 1725720000000000,
      end_time_us: 1725720000001000,
      status: "OK",
    )
  let frame = WsOoZSpan(span)
  let encoded = encode_downstream_frame(frame)

  string.contains(encoded, "\"type\":\"ooz_span\"") |> should.be_true()
  string.contains(encoded, "\"layer\":\"l5_cognitive\"") |> should.be_true()
}

pub fn downstream_moz_request_encoding_test() {
  let req =
    MoZReqPayload(
      req_id: "req-99",
      tool: "plan_status",
      arguments_json: "{}",
      caller_id: "agent-1",
      timestamp_us: 1725720000000000,
    )
  let frame = WsMoZReq(req)
  let encoded = encode_downstream_frame(frame)

  string.contains(encoded, "\"type\":\"moz_request\"") |> should.be_true()
  string.contains(encoded, "\"tool\":\"plan_status\"") |> should.be_true()
}

pub fn downstream_heartbeat_encoding_test() {
  let frame = WsHeartbeat(timestamp_us: 1725720000000000, peer_count: 3)
  let encoded = encode_downstream_frame(frame)

  string.contains(encoded, "\"type\":\"heartbeat\"") |> should.be_true()
  string.contains(encoded, "\"peer_count\":3") |> should.be_true()
}

pub fn downstream_crdt_sync_encoding_test() {
  let frame = WsCRDTSync(node_id: "vm-1", payload_json: "{\"health\":1.0}")
  let encoded = encode_downstream_frame(frame)

  string.contains(encoded, "\"type\":\"crdt_sync\"") |> should.be_true()
  string.contains(encoded, "\"node_id\":\"vm-1\"") |> should.be_true()
}

pub fn upstream_subscribe_command_decoding_test() {
  let json_str = "{\"type\":\"subscribe\",\"layer\":\"l6_ecosystem\"}"
  let decoded = decode_upstream_command(json_str)

  decoded |> should.equal(Ok(WsSubscribe(layer_filter: "l6_ecosystem")))
}

pub fn upstream_ping_command_decoding_test() {
  let json_str = "{\"type\":\"ping\",\"client_time_us\":1725720000000000}"
  let decoded = decode_upstream_command(json_str)

  decoded |> should.equal(Ok(WsPing(client_time_us: 1725720000000000)))
}

pub fn upstream_invalid_command_decoding_test() {
  decode_upstream_command("{\"type\":\"unknown\"}")
  |> should.equal(Error("Unknown upstream command type: unknown"))

  decode_upstream_command("invalid json")
  |> should.equal(Error("Invalid JSON frame"))
}
