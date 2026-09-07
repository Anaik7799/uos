//// =============================================================================
//// [C3I-SIL6-MSTS] TEST CONTRACT: AG-UI WebSocket Hot Stream Component Verification
//// =============================================================================

import cepaf_gleam/ui/lustre/ws_hot_stream.{
  WsConnected, WsDisconnected, WsReconnecting, render_stream_panel,
}
import cepaf_gleam/ui/wisp/ws_bridge.{
  WsCRDTSync, WsHeartbeat, WsMoZReq, WsOoZSpan,
}
import cepaf_gleam/zenoh/zmof_transport.{MoZReqPayload, OoZSpanPayload}
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn render_stream_connected_test() {
  let status = WsConnected("ws://nas-1.tail55d152.ts.net:4100/ag-ui/ws", 2)
  let span =
    OoZSpanPayload(
      trace_id: "t1",
      span_id: "s1",
      name: "lyapunov.tick",
      layer: "l0_constitutional",
      start_time_us: 1000,
      end_time_us: 2000,
      status: "OK",
    )
  let req =
    MoZReqPayload(
      req_id: "r1",
      tool: "plan_get",
      arguments_json: "{}",
      caller_id: "worker-1",
      timestamp_us: 1000,
    )
  let sync = WsCRDTSync("vm-1", "{}")
  let hb = WsHeartbeat(1000, 2)

  let html =
    render_stream_panel(status, [WsOoZSpan(span), WsMoZReq(req), sync, hb])

  string.contains(html, "AG-UI Live WebSocket Stream") |> should.be_true()
  string.contains(html, "CONNECTED") |> should.be_true()
  string.contains(html, "[OoZ-SPAN] l0_constitutional / lyapunov.tick")
  |> should.be_true()
  string.contains(html, "[MoZ-RPC] plan_get") |> should.be_true()
  string.contains(html, "[CRDT-SYNC] Node vm-1") |> should.be_true()
  string.contains(html, "[HEARTBEAT]") |> should.be_true()
}

pub fn render_stream_reconnecting_test() {
  let status = WsReconnecting(3)
  let html = render_stream_panel(status, [])
  string.contains(html, "RECONNECTING (Attempt 3)") |> should.be_true()
}

pub fn render_stream_disconnected_test() {
  let status = WsDisconnected
  let html = render_stream_panel(status, [])
  string.contains(html, "DISCONNECTED") |> should.be_true()
}
