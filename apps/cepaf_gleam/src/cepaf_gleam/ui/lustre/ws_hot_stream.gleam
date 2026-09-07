//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ui/lustre/ws_hot_stream</module>
////     <fsharp-lineage>N/A — Pure Gleam AG-UI WebSocket Hot-Stream Lustre Component</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L2_COMPONENT</layer>
////     <layer>L5_COGNITIVE</layer>
////     <cross-layer-dependencies>
////       <dep layer="L6_ECOSYSTEM">cepaf_gleam/ui/wisp/ws_bridge</dep>
////     </cross-layer-dependencies>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-AGUI-001, SC-GLM-UI-001, SC-MUDA-001</stamp-controls>
////   </compliance>
////   <algebraic-properties>
////     <property name="render-isomorphism">Server-rendered markup produces valid DOM structure identical to live WebSocket updates</property>
////   </algebraic-properties>
//// </c3i-module>
//// =============================================================================

import cepaf_gleam/ui/wisp/ws_bridge.{
  type WsDownstreamFrame, WsCRDTSync, WsHeartbeat, WsMoZReq, WsOoZSpan,
}
import gleam/list
import gleam/string

/// Connection status of the live WebSocket telemetry stream.
pub type WsConnectionStatus {
  WsConnected(endpoint: String, peer_count: Int)
  WsReconnecting(attempt: Int)
  WsDisconnected
}

/// Render the live WebSocket telemetry stream panel.
pub fn render_stream_panel(
  status: WsConnectionStatus,
  frames: List(WsDownstreamFrame),
) -> String {
  let status_html = case status {
    WsConnected(endpoint, peers) ->
      "<span style=\"color:#50e3c2;font-size:0.85rem\">● CONNECTED &middot; "
      <> endpoint
      <> " ("
      <> string.inspect(peers)
      <> " active peers)</span>"
    WsReconnecting(attempt) ->
      "<span style=\"color:#f5a623;font-size:0.85rem\">▲ RECONNECTING (Attempt "
      <> string.inspect(attempt)
      <> ")</span>"
    WsDisconnected ->
      "<span style=\"color:#e06c75;font-size:0.85rem\">■ DISCONNECTED</span>"
  }

  "<div class=\"uos-ws-hot-stream\" style=\"background:#101622;border:1px solid #1e2a3a;border-radius:6px;padding:1rem;margin-top:1rem\">"
  <> "<div style=\"display:flex;justify-content:space-between;align-items:center;margin-bottom:0.75rem\">"
  <> "<h3 style=\"color:#00d4aa;margin:0;font-size:1.1rem\">AG-UI Live WebSocket Stream</h3>"
  <> status_html
  <> "</div>"
  <> "<div style=\"display:flex;flex-direction:column;gap:0.4rem;max-height:280px;overflow-y:auto\">"
  <> list.map(frames, render_frame_item) |> string.concat()
  <> "</div></div>"
}

fn render_frame_item(frame: WsDownstreamFrame) -> String {
  case frame {
    WsOoZSpan(span) ->
      "<div style=\"display:flex;justify-content:space-between;background:#06090e;padding:0.4rem 0.6rem;border-radius:4px;border-left:3px solid #50e3c2;font-family:monospace;font-size:0.82rem\">"
      <> "<span style=\"color:#50e3c2\">[OoZ-SPAN] "
      <> span.layer
      <> " / "
      <> span.name
      <> "</span>"
      <> "<span style=\"color:#8b9bb4\">status: "
      <> span.status
      <> "</span></div>"

    WsMoZReq(req) ->
      "<div style=\"display:flex;justify-content:space-between;background:#06090e;padding:0.4rem 0.6rem;border-radius:4px;border-left:3px solid #4a90e2;font-family:monospace;font-size:0.82rem\">"
      <> "<span style=\"color:#4a90e2\">[MoZ-RPC] "
      <> req.tool
      <> " (req_id: "
      <> req.req_id
      <> ")</span>"
      <> "<span style=\"color:#8b9bb4\">caller: "
      <> req.caller_id
      <> "</span></div>"

    WsCRDTSync(node_id, _) ->
      "<div style=\"display:flex;justify-content:space-between;background:#06090e;padding:0.4rem 0.6rem;border-radius:4px;border-left:3px solid #bd10e0;font-family:monospace;font-size:0.82rem\">"
      <> "<span style=\"color:#bd10e0\">[CRDT-SYNC] Node "
      <> node_id
      <> "</span>"
      <> "<span style=\"color:#8b9bb4\">reconciled</span></div>"

    WsHeartbeat(ts, peers) ->
      "<div style=\"display:flex;justify-content:space-between;background:#06090e;padding:0.4rem 0.6rem;border-radius:4px;border-left:3px solid #f5a623;font-family:monospace;font-size:0.82rem\">"
      <> "<span style=\"color:#f5a623\">[HEARTBEAT] ts: "
      <> string.inspect(ts)
      <> "</span>"
      <> "<span style=\"color:#8b9bb4\">peers: "
      <> string.inspect(peers)
      <> "</span></div>"
  }
}
