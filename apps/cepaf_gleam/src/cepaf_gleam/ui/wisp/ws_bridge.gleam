//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ui/wisp/ws_bridge</module>
////     <fsharp-lineage>N/A — Pure Gleam Multi-Host Zenoh WebSocket Telemetry Bridge</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L2_COMPONENT</layer>
////     <layer>L5_COGNITIVE</layer>
////     <layer>L6_ECOSYSTEM</layer>
////     <cross-layer-dependencies>
////       <dep layer="L6_ECOSYSTEM">cepaf_gleam/zenoh/zmof_transport</dep>
////     </cross-layer-dependencies>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-ZMOF-001, SC-AGUI-001, SC-MUDA-001</stamp-controls>
////   </compliance>
////   <algebraic-properties>
////     <property name="framing-totality">Every multiplexed Zenoh frame maps bijectively to a typed WebSocket JSON frame</property>
////     <property name="zero-copy-broadcast">Server-side multiplexing incurs zero client-side JavaScript execution</property>
////   </algebraic-properties>
//// </c3i-module>
//// =============================================================================

import cepaf_gleam/zenoh/zmof_transport.{
  type MoZReqPayload, type OoZSpanPayload, encode_moz_request, encode_ooz_span,
}
import gleam/dynamic/decode
import gleam/json

/// Downstream WebSocket telemetry frame transmitted to connected browser clients.
pub type WsDownstreamFrame {
  WsOoZSpan(span: OoZSpanPayload)
  WsMoZReq(req: MoZReqPayload)
  WsCRDTSync(node_id: String, payload_json: String)
  WsHeartbeat(timestamp_us: Int, peer_count: Int)
}

/// Upstream WebSocket command frame received from client.
pub type WsUpstreamCommand {
  WsSubscribe(layer_filter: String)
  WsPing(client_time_us: Int)
}

/// Encode downstream frame to strict typed JSON string.
pub fn encode_downstream_frame(frame: WsDownstreamFrame) -> String {
  case frame {
    WsOoZSpan(span) ->
      json.object([
        #("type", json.string("ooz_span")),
        #("layer", json.string(span.layer)),
        #("payload", json.string(encode_ooz_span(span))),
      ])
      |> json.to_string

    WsMoZReq(req) ->
      json.object([
        #("type", json.string("moz_request")),
        #("tool", json.string(req.tool)),
        #("payload", json.string(encode_moz_request(req))),
      ])
      |> json.to_string

    WsCRDTSync(node_id, payload_json) ->
      json.object([
        #("type", json.string("crdt_sync")),
        #("node_id", json.string(node_id)),
        #("payload", json.string(payload_json)),
      ])
      |> json.to_string

    WsHeartbeat(timestamp_us, peer_count) ->
      json.object([
        #("type", json.string("heartbeat")),
        #("timestamp_us", json.int(timestamp_us)),
        #("peer_count", json.int(peer_count)),
        #("status", json.string("HEALTHY")),
      ])
      |> json.to_string
  }
}

/// Decode upstream client command frame.
pub fn decode_upstream_command(
  payload: String,
) -> Result(WsUpstreamCommand, String) {
  let type_decoder = {
    use frame_type <- decode.field("type", decode.string)
    decode.success(frame_type)
  }

  case json.parse(from: payload, using: type_decoder) {
    Ok("subscribe") -> {
      let sub_decoder = {
        use layer <- decode.field("layer", decode.string)
        decode.success(WsSubscribe(layer_filter: layer))
      }
      case json.parse(from: payload, using: sub_decoder) {
        Ok(cmd) -> Ok(cmd)
        Error(_) -> Error("Invalid subscribe frame payload")
      }
    }

    Ok("ping") -> {
      let ping_decoder = {
        use client_time <- decode.field("client_time_us", decode.int)
        decode.success(WsPing(client_time_us: client_time))
      }
      case json.parse(from: payload, using: ping_decoder) {
        Ok(cmd) -> Ok(cmd)
        Error(_) -> Error("Invalid ping frame payload")
      }
    }

    Ok(unknown) -> Error("Unknown upstream command type: " <> unknown)
    Error(_) -> Error("Invalid JSON frame")
  }
}
