//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/zenoh/zmof_transport</module>
////     <fsharp-lineage>N/A — Pure Gleam Zenoh-MCP-OTel Fractal Backplane (ZMOF)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////     <layer>L6_ECOSYSTEM</layer>
////     <cross-layer-dependencies>
////       <dep layer="L6_ECOSYSTEM">cepaf_gleam/zenoh/domain</dep>
////     </cross-layer-dependencies>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-ZMOF-001, SC-ZMOF-002, SC-ZMOF-003, SC-ZMOF-005, SC-MUDA-001</stamp-controls>
////   </compliance>
////   <algebraic-properties>
////     <property name="unification">Zenoh pub/sub is the single canonical substrate for telemetry (OoZ) and tool calls (MoZ)</property>
////     <property name="deterministic-routing">Structured topic namespaces guarantee deterministic O(1) hash routing</property>
////   </algebraic-properties>
//// </c3i-module>
//// =============================================================================

import gleam/dynamic/decode
import gleam/json
import gleam/string

/// Traffic classifications in the ZMOF backplane.
pub type ZMOFTrafficClass {
  OoZSpan(layer: String, entity_id: String)
  MoZRequest(tool: String, req_id: String)
  MoZResponse(req_id: String)
  CrdtMeshSync(node_id: String)
  ConstitutionalStream(topic: String)
}

/// Typed OTel-over-Zenoh (OoZ) span payload.
pub type OoZSpanPayload {
  OoZSpanPayload(
    trace_id: String,
    span_id: String,
    name: String,
    layer: String,
    start_time_us: Int,
    end_time_us: Int,
    status: String,
  )
}

/// Typed MCP-over-Zenoh (MoZ) request payload.
pub type MoZReqPayload {
  MoZReqPayload(
    req_id: String,
    tool: String,
    arguments_json: String,
    caller_id: String,
    timestamp_us: Int,
  )
}

/// Typed MCP-over-Zenoh (MoZ) response payload.
pub type MoZResPayload {
  MoZResPayload(
    req_id: String,
    success: Bool,
    result_json: String,
    error_msg: String,
    timestamp_us: Int,
  )
}

// ---------------------------------------------------------------------------
// Canonical Topic Generators
// ---------------------------------------------------------------------------

pub fn ooz_topic(layer: String, entity_id: String) -> String {
  "indrajaal/otel/span/" <> layer <> "/" <> entity_id
}

pub fn moz_req_topic(tool: String, req_id: String) -> String {
  "indrajaal/mcp/req/" <> tool <> "/" <> req_id
}

pub fn moz_res_topic(req_id: String) -> String {
  "indrajaal/mcp/res/" <> req_id
}

pub fn crdt_sync_topic(node_id: String) -> String {
  "indrajaal/crdt/sync/" <> node_id
}

// ---------------------------------------------------------------------------
// Topic Classification & Parsing
// ---------------------------------------------------------------------------

pub fn classify_topic(topic: String) -> Result(ZMOFTrafficClass, Nil) {
  let parts = string.split(topic, on: "/")
  case parts {
    ["indrajaal", "otel", "span", layer, entity_id] ->
      Ok(OoZSpan(layer: layer, entity_id: entity_id))
    ["indrajaal", "mcp", "req", tool, req_id] ->
      Ok(MoZRequest(tool: tool, req_id: req_id))
    ["indrajaal", "mcp", "res", req_id] ->
      Ok(MoZResponse(req_id: req_id))
    ["indrajaal", "crdt", "sync", node_id] ->
      Ok(CrdtMeshSync(node_id: node_id))
    ["indrajaal", "l0", "const", ..] ->
      Ok(ConstitutionalStream(topic: topic))
    _ -> Error(Nil)
  }
}

// ---------------------------------------------------------------------------
// Encoders
// ---------------------------------------------------------------------------

pub fn encode_ooz_span(span: OoZSpanPayload) -> String {
  json.object([
    #("trace_id", json.string(span.trace_id)),
    #("span_id", json.string(span.span_id)),
    #("name", json.string(span.name)),
    #("layer", json.string(span.layer)),
    #("start_time_us", json.int(span.start_time_us)),
    #("end_time_us", json.int(span.end_time_us)),
    #("status", json.string(span.status)),
  ])
  |> json.to_string
}

pub fn encode_moz_request(req: MoZReqPayload) -> String {
  json.object([
    #("req_id", json.string(req.req_id)),
    #("tool", json.string(req.tool)),
    #("arguments_json", json.string(req.arguments_json)),
    #("caller_id", json.string(req.caller_id)),
    #("timestamp_us", json.int(req.timestamp_us)),
  ])
  |> json.to_string
}

pub fn encode_moz_response(res: MoZResPayload) -> String {
  json.object([
    #("req_id", json.string(res.req_id)),
    #("success", json.bool(res.success)),
    #("result_json", json.string(res.result_json)),
    #("error_msg", json.string(res.error_msg)),
    #("timestamp_us", json.int(res.timestamp_us)),
  ])
  |> json.to_string
}

// ---------------------------------------------------------------------------
// Decoders
// ---------------------------------------------------------------------------

pub fn decode_ooz_span(payload: String) -> Result(OoZSpanPayload, String) {
  let decoder = {
    use trace_id <- decode.field("trace_id", decode.string)
    use span_id <- decode.field("span_id", decode.string)
    use name <- decode.field("name", decode.string)
    use layer <- decode.field("layer", decode.string)
    use start_time_us <- decode.field("start_time_us", decode.int)
    use end_time_us <- decode.field("end_time_us", decode.int)
    use status <- decode.field("status", decode.string)
    decode.success(OoZSpanPayload(
      trace_id: trace_id,
      span_id: span_id,
      name: name,
      layer: layer,
      start_time_us: start_time_us,
      end_time_us: end_time_us,
      status: status,
    ))
  }
  case json.parse(from: payload, using: decoder) {
    Ok(val) -> Ok(val)
    Error(_) -> Error("Failed to decode OoZSpanPayload JSON")
  }
}

pub fn decode_moz_request(payload: String) -> Result(MoZReqPayload, String) {
  let decoder = {
    use req_id <- decode.field("req_id", decode.string)
    use tool <- decode.field("tool", decode.string)
    use arguments_json <- decode.field("arguments_json", decode.string)
    use caller_id <- decode.field("caller_id", decode.string)
    use timestamp_us <- decode.field("timestamp_us", decode.int)
    decode.success(MoZReqPayload(
      req_id: req_id,
      tool: tool,
      arguments_json: arguments_json,
      caller_id: caller_id,
      timestamp_us: timestamp_us,
    ))
  }
  case json.parse(from: payload, using: decoder) {
    Ok(val) -> Ok(val)
    Error(_) -> Error("Failed to decode MoZReqPayload JSON")
  }
}

pub fn decode_moz_response(payload: String) -> Result(MoZResPayload, String) {
  let decoder = {
    use req_id <- decode.field("req_id", decode.string)
    use success <- decode.field("success", decode.bool)
    use result_json <- decode.field("result_json", decode.string)
    use error_msg <- decode.field("error_msg", decode.string)
    use timestamp_us <- decode.field("timestamp_us", decode.int)
    decode.success(MoZResPayload(
      req_id: req_id,
      success: success,
      result_json: result_json,
      error_msg: error_msg,
      timestamp_us: timestamp_us,
    ))
  }
  case json.parse(from: payload, using: decoder) {
    Ok(val) -> Ok(val)
    Error(_) -> Error("Failed to decode MoZResPayload JSON")
  }
}
