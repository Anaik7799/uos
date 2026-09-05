//// [C3I-SIL6-MSTS] MODULE CONTRACT
//// <c3i-module>
////   <identity><module>cepaf_gleam/ui/zenoh_otel</module></identity>
////   <fractal-topology><layer>L6_ECOSYSTEM</layer></fractal-topology>
////   <compliance>
////     <stamp-controls>SC-GLM-CORE-001, SC-GLM-CORE-002, SC-GLM-CORE-003, SC-ZENOH-001</stamp-controls>
////   </compliance>
//// </c3i-module>
////

/// Zenoh OTel Integration Module.
/// Publishes OpenTelemetry spans over Zenoh pub/sub for all UI state changes.
/// Topic schema: indrajaal/otel/ops/{page}/{element}
/// Span types: Observe, Orient, Decide, Act (OODA loop phases)
///
/// STAMP: SC-GLM-CORE-001, SC-GLM-CORE-002, SC-GLM-CORE-003, SC-ZENOH-001
import cepaf_gleam/ui/domain.{
  type Page, Agents, Auth, Bicameral, Biomorphic, Bridge, Cockpit, ComponentDemo,
  Config, Dashboard, Database, Evolution, Federation, Git, HealthGrid, Holon,
  HomeostasisPage, Immune, Integrity, Kms, Knowledge, Mcp, Metabolic, Planning,
  PlanningDashboard, Podman, Prajna, Singularity, Smriti, Substrate, Telemetry,
  Verification, Zenoh, page_to_path,
}
import cepaf_gleam/zenoh/client
import gleam/int
import gleam/json

// ---------------------------------------------------------------------------
// OODA Span Types
// ---------------------------------------------------------------------------

/// OODA loop phase for OTel span classification.
pub type OodaPhase {
  Observe
  Orient
  Decide
  Act
}

/// OTel span carrying OODA phase metadata and UI state delta.
pub type OtelSpan {
  OtelSpan(
    trace_id: String,
    span_id: String,
    name: String,
    ooda_phase: OodaPhase,
    page: Page,
    element: String,
    timestamp: Int,
    duration_us: Int,
    attributes: json.Json,
  )
}

/// Topic prefix for OTel spans.
const otel_prefix = "indrajaal/otel/ops/"

// ---------------------------------------------------------------------------
// OodaPhase serialization
// ---------------------------------------------------------------------------

/// Convert OodaPhase to string.
pub fn ooda_phase_to_string(phase: OodaPhase) -> String {
  case phase {
    Observe -> "Observe"
    Orient -> "Orient"
    Decide -> "Decide"
    Act -> "Act"
  }
}

/// Convert a Page to its string representation for OTel spans.
pub fn page_to_string(page: Page) -> String {
  case page {
    Dashboard -> "dashboard"
    Planning -> "planning"
    Immune -> "immune"
    Knowledge -> "knowledge"
    Zenoh -> "zenoh"
    Cockpit -> "cockpit"
    Verification -> "verification"
    Substrate -> "substrate"
    Metabolic -> "metabolic"
    Podman -> "podman"
    Mcp -> "mcp"
    Kms -> "kms"
    Telemetry -> "telemetry"
    Federation -> "federation"
    HealthGrid -> "health_grid"
    Prajna -> "prajna"
    Agents -> "agents"
    Holon -> "holon"
    Config -> "config"
    Git -> "git"
    Database -> "database"
    Bridge -> "bridge"
    Smriti -> "smriti"
    PlanningDashboard -> "planning_dashboard"
    Integrity -> "integrity"
    Evolution -> "evolution"
    Biomorphic -> "biomorphic"
    HomeostasisPage -> "homeostasis"
    Bicameral -> "bicameral"
    Singularity -> "singularity"
    ComponentDemo -> "component_demo"
    Auth -> "auth"
  }
}

// ---------------------------------------------------------------------------
// FFI bindings
// ---------------------------------------------------------------------------

@external(erlang, "cepaf_gleam_ffi", "generate_id")
fn generate_id() -> String

@external(erlang, "cepaf_gleam_ffi", "system_time_nanos")
fn system_time_nanos() -> String

fn now_ms() -> Int {
  case int.parse(system_time_nanos()) {
    Ok(nanos) -> nanos / 1_000_000
    Error(_) -> 0
  }
}

fn generate_trace_id() -> String {
  generate_id()
}

fn generate_span_id() -> String {
  generate_id()
}

// ---------------------------------------------------------------------------
// Span builders
// ---------------------------------------------------------------------------

/// Build an OTel span JSON payload.
fn span_to_json(span: OtelSpan) -> json.Json {
  json.object([
    #("trace_id", json.string(span.trace_id)),
    #("span_id", json.string(span.span_id)),
    #("name", json.string(span.name)),
    #("ooda_phase", json.string(ooda_phase_to_string(span.ooda_phase))),
    #("page", json.string(page_to_string(span.page))),
    #("element", json.string(span.element)),
    #("timestamp", json.int(span.timestamp)),
    #("duration_us", json.int(span.duration_us)),
    #("attributes", span.attributes),
  ])
}

/// Build the Zenoh topic for a given page and element.
fn otel_topic(page: Page, element: String) -> String {
  otel_prefix <> page_to_string(page) <> "/" <> element
}

/// Create a new OTel span for a UI state change.
pub fn new_span(
  page: Page,
  element: String,
  ooda_phase: OodaPhase,
  attributes: json.Json,
) -> OtelSpan {
  OtelSpan(
    trace_id: generate_trace_id(),
    span_id: generate_span_id(),
    name: page_to_path(page) <> "/" <> element,
    ooda_phase: ooda_phase,
    page: page,
    element: element,
    timestamp: now_ms(),
    duration_us: 0,
    attributes: attributes,
  )
}

/// Publish an OTel span to Zenoh.
pub fn publish_span(
  session: client.Session,
  span: OtelSpan,
) -> Result(Nil, String) {
  let topic = otel_topic(span.page, span.element)
  let payload = json.to_string(span_to_json(span))
  client.put(session, topic, payload)
}

/// Session-less publish — uses NIF ambient Zenoh session.
/// Fire-and-forget; returns Ok(Nil) on accept, Error(msg) on NIF failure.
/// Added by ULTRA-PASS5 to close FINDING-A (RPN=900).
pub fn publish(span: OtelSpan) -> Result(Nil, String) {
  let topic = otel_topic(span.page, span.element)
  let payload = json.to_string(span_to_json(span))
  case client.put_nif(topic, payload) {
    Ok(_) -> Ok(Nil)
    Error(msg) -> Error(msg)
  }
}

/// Convenience: build + publish in one call.
pub fn emit_span(
  page: Page,
  element: String,
  phase: OodaPhase,
  attributes: json.Json,
) -> Result(Nil, String) {
  publish(new_span(page, element, phase, attributes))
}

// ---------------------------------------------------------------------------
// Page-specific span publishers
// ---------------------------------------------------------------------------

/// Publish OTel span for Dashboard state change.
pub fn dashboard_span(
  session: client.Session,
  element: String,
  phase: OodaPhase,
  attrs: json.Json,
) -> Result(Nil, String) {
  let span = new_span(Dashboard, element, phase, attrs)
  publish_span(session, span)
}

/// Publish OTel span for Planning state change.
pub fn planning_span(
  session: client.Session,
  element: String,
  phase: OodaPhase,
  attrs: json.Json,
) -> Result(Nil, String) {
  let span = new_span(Planning, element, phase, attrs)
  publish_span(session, span)
}

/// Publish OTel span for Immune state change.
pub fn immune_span(
  session: client.Session,
  element: String,
  phase: OodaPhase,
  attrs: json.Json,
) -> Result(Nil, String) {
  let span = new_span(Immune, element, phase, attrs)
  publish_span(session, span)
}

/// Publish OTel span for Knowledge state change.
pub fn knowledge_span(
  session: client.Session,
  element: String,
  phase: OodaPhase,
  attrs: json.Json,
) -> Result(Nil, String) {
  let span = new_span(Knowledge, element, phase, attrs)
  publish_span(session, span)
}

/// Publish OTel span for Zenoh Mesh state change.
pub fn zenoh_mesh_span(
  session: client.Session,
  element: String,
  phase: OodaPhase,
  attrs: json.Json,
) -> Result(Nil, String) {
  let span = new_span(Zenoh, element, phase, attrs)
  publish_span(session, span)
}

/// Publish OTel span for Cockpit state change.
pub fn cockpit_span(
  session: client.Session,
  element: String,
  phase: OodaPhase,
  attrs: json.Json,
) -> Result(Nil, String) {
  let span = new_span(Cockpit, element, phase, attrs)
  publish_span(session, span)
}

/// Publish OTel span for Verification state change.
pub fn verification_span(
  session: client.Session,
  element: String,
  phase: OodaPhase,
  attrs: json.Json,
) -> Result(Nil, String) {
  let span = new_span(Verification, element, phase, attrs)
  publish_span(session, span)
}

/// Publish OTel span for Substrate state change.
pub fn substrate_span(
  session: client.Session,
  element: String,
  phase: OodaPhase,
  attrs: json.Json,
) -> Result(Nil, String) {
  let span = new_span(Substrate, element, phase, attrs)
  publish_span(session, span)
}

/// Publish OTel span for Metabolic state change.
pub fn metabolic_span(
  session: client.Session,
  element: String,
  phase: OodaPhase,
  attrs: json.Json,
) -> Result(Nil, String) {
  let span = new_span(Metabolic, element, phase, attrs)
  publish_span(session, span)
}

/// Publish OTel span for Podman state change.
pub fn podman_span(
  session: client.Session,
  element: String,
  phase: OodaPhase,
  attrs: json.Json,
) -> Result(Nil, String) {
  let span = new_span(Podman, element, phase, attrs)
  publish_span(session, span)
}

/// Publish OTel span for MCP state change.
pub fn mcp_span(
  session: client.Session,
  element: String,
  phase: OodaPhase,
  attrs: json.Json,
) -> Result(Nil, String) {
  let span = new_span(Mcp, element, phase, attrs)
  publish_span(session, span)
}

/// Publish OTel span for KMS state change.
pub fn kms_span(
  session: client.Session,
  element: String,
  phase: OodaPhase,
  attrs: json.Json,
) -> Result(Nil, String) {
  let span = new_span(Kms, element, phase, attrs)
  publish_span(session, span)
}

/// Publish OTel span for Telemetry state change.
pub fn telemetry_span(
  session: client.Session,
  element: String,
  phase: OodaPhase,
  attrs: json.Json,
) -> Result(Nil, String) {
  let span = new_span(Telemetry, element, phase, attrs)
  publish_span(session, span)
}

/// Publish OTel span for Federation state change.
pub fn federation_span(
  session: client.Session,
  element: String,
  phase: OodaPhase,
  attrs: json.Json,
) -> Result(Nil, String) {
  let span = new_span(Federation, element, phase, attrs)
  publish_span(session, span)
}

/// Publish OTel span for HealthGrid state change.
pub fn health_grid_span(
  session: client.Session,
  element: String,
  phase: OodaPhase,
  attrs: json.Json,
) -> Result(Nil, String) {
  let span = new_span(HealthGrid, element, phase, attrs)
  publish_span(session, span)
}

// ---------------------------------------------------------------------------
// Generic page dispatcher
// ---------------------------------------------------------------------------

/// Publish an OTel span for any page via dispatcher.
pub fn publish_for_page(
  session: client.Session,
  page: Page,
  element: String,
  phase: OodaPhase,
  attrs: json.Json,
) -> Result(Nil, String) {
  let span = new_span(page, element, phase, attrs)
  publish_span(session, span)
}

// ---------------------------------------------------------------------------
// Attribute helpers
// ---------------------------------------------------------------------------

/// Build attribute JSON for a state transition.
pub fn state_change_attrs(
  from_state: String,
  to_state: String,
  trigger: String,
) -> json.Json {
  json.object([
    #("from_state", json.string(from_state)),
    #("to_state", json.string(to_state)),
    #("trigger", json.string(trigger)),
    #("span_kind", json.string("state_change")),
  ])
}

/// Build attribute JSON for a user action.
pub fn user_action_attrs(action: String, target: String) -> json.Json {
  json.object([
    #("action", json.string(action)),
    #("target", json.string(target)),
    #("span_kind", json.string("user_action")),
  ])
}

/// Build attribute JSON for a Zenoh message event.
pub fn zenoh_message_attrs(
  topic: String,
  message_count: Int,
  latency_us: Int,
) -> json.Json {
  json.object([
    #("zenoh_topic", json.string(topic)),
    #("message_count", json.int(message_count)),
    #("latency_us", json.int(latency_us)),
    #("span_kind", json.string("zenoh_message")),
  ])
}

/// Build attribute JSON for an error event.
pub fn error_attrs(error_type: String, message: String) -> json.Json {
  json.object([
    #("error_type", json.string(error_type)),
    #("error_message", json.string(message)),
    #("span_kind", json.string("error")),
  ])
}

// ---------------------------------------------------------------------------
// Control & System Operation Spans (SC-GLM-ZEN-001)
// ---------------------------------------------------------------------------

/// Build attribute JSON for a control operation (container start/stop/restart).
pub fn control_attrs(
  action: String,
  target: String,
  result: String,
) -> json.Json {
  json.object([
    #("action", json.string(action)),
    #("target", json.string(target)),
    #("result", json.string(result)),
    #("span_kind", json.string("control")),
  ])
}

/// Publish a control span for system operations.
pub fn control_span(
  session: client.Session,
  action: String,
  target: String,
  phase: OodaPhase,
) -> Result(Nil, String) {
  let attrs = control_attrs(action, target, "initiated")
  let span = new_span(Podman, "control_" <> action, phase, attrs)
  publish_span(session, span)
}

// ---------------------------------------------------------------------------
// Test Runner Observer Spans (SC-GLM-ZEN-002)
// ---------------------------------------------------------------------------

/// Build attribute JSON for test runner observation.
pub fn test_runner_attrs(
  test_name: String,
  test_status: String,
  duration_ms: Int,
) -> json.Json {
  json.object([
    #("test_name", json.string(test_name)),
    #("test_status", json.string(test_status)),
    #("duration_ms", json.int(duration_ms)),
    #("span_kind", json.string("test_runner")),
  ])
}

/// Publish a test runner observation span.
pub fn test_runner_span(
  session: client.Session,
  test_name: String,
  phase: OodaPhase,
  attrs: json.Json,
) -> Result(Nil, String) {
  let span = new_span(Verification, "test_" <> test_name, phase, attrs)
  publish_span(session, span)
}

// ---------------------------------------------------------------------------
// Agent Observation Spans (for Gemini/Claude via MCP+Zenoh)
// ---------------------------------------------------------------------------

/// Build attribute JSON for AI agent observation.
pub fn agent_attrs(
  agent_id: String,
  action: String,
  context: String,
) -> json.Json {
  json.object([
    #("agent_id", json.string(agent_id)),
    #("action", json.string(action)),
    #("context", json.string(context)),
    #("span_kind", json.string("agent")),
  ])
}

/// Publish an agent observation span.
pub fn agent_span(
  session: client.Session,
  agent_id: String,
  action: String,
  phase: OodaPhase,
  attrs: json.Json,
) -> Result(Nil, String) {
  let span = new_span(Mcp, "agent_" <> agent_id <> "_" <> action, phase, attrs)
  publish_span(session, span)
}

// ---------------------------------------------------------------------------
// Session-free publishing (for Lustre pages that don't hold a Session)
// Uses the global NIF Zenoh session (SC-GLM-ZEN-001)
// ---------------------------------------------------------------------------

/// Publish an OTel span using the global NIF Zenoh session.
/// This is the PRIMARY entry point for Lustre pages — no Session needed.
pub fn emit(page: Page, element: String, phase: OodaPhase) -> Nil {
  let span = new_span(page, element, phase, json.object([]))
  let topic = otel_topic(span.page, span.element)
  let payload = json.to_string(span_to_json(span))
  let _ = client.put_nif(topic, payload)
  Nil
}

/// Emit with custom attributes.
pub fn emit_with(
  page: Page,
  element: String,
  phase: OodaPhase,
  attrs: json.Json,
) -> Nil {
  let span = new_span(page, element, phase, attrs)
  let topic = otel_topic(span.page, span.element)
  let payload = json.to_string(span_to_json(span))
  let _ = client.put_nif(topic, payload)
  Nil
}

/// All 31 page topic prefixes (for observer subscription).
pub fn all_page_topics() -> List(String) {
  [
    otel_prefix <> "dashboard",
    otel_prefix <> "planning",
    otel_prefix <> "immune",
    otel_prefix <> "knowledge",
    otel_prefix <> "zenoh",
    otel_prefix <> "cockpit",
    otel_prefix <> "verification",
    otel_prefix <> "substrate",
    otel_prefix <> "metabolic",
    otel_prefix <> "podman",
    otel_prefix <> "mcp",
    otel_prefix <> "kms",
    otel_prefix <> "telemetry",
    otel_prefix <> "federation",
    otel_prefix <> "health_grid",
    otel_prefix <> "prajna",
    otel_prefix <> "agents",
    otel_prefix <> "holon",
    otel_prefix <> "config",
    otel_prefix <> "git",
    otel_prefix <> "database",
    otel_prefix <> "bridge",
    otel_prefix <> "smriti",
    otel_prefix <> "planning_dashboard",
    otel_prefix <> "integrity",
    otel_prefix <> "evolution",
    otel_prefix <> "biomorphic",
    otel_prefix <> "homeostasis",
    otel_prefix <> "bicameral",
    otel_prefix <> "singularity",
    otel_prefix <> "component_demo",
  ]
}
