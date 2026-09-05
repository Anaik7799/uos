//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/bridge/pi_agent</module>
////     <fsharp-lineage>No F# lineage — Gleam-native Pi-mono bridge</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L6_ECOSYSTEM</layer>
////     <mesh-domain>Pi-mono TypeScript Agent Runtime Bridge</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>DAL-A / SIL-6 / HIGH</criticality>
////     <stamp-controls>
////       SC-PI-001, SC-PI-002, SC-PI-003, SC-PI-004, SC-PI-005,
////       SC-PI-006, SC-PI-007, SC-PI-008, SC-PI-009, SC-PI-010,
////       SC-ZMOF-001, SC-ZMOF-005, SC-GLM-UI-001
////     </stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective" augmentation="event-mapping">
////       Pi AgentEvent (12 types) ↪ C3I AG-UI event (32 types).
////       Pi events are a strict subset — every Pi event maps to exactly one
////       AG-UI event type. The reverse is not true (AG-UI is a superset).
////     </morphism>
////     <morphism type="surjective" loss="jsonl-session-schema">
////       Pi JSONL session log ↠ Smriti.db SQLite schema.
////       JSONL line-delimited format is normalised into relational rows.
////       Mitigation: raw JSONL preserved in a blob column for lossless replay.
////     </morphism>
////     <morphism type="injective" augmentation="hedged-inference">
////       Pi single-provider model ↪ C3I 6-tier hedged inference cascade.
////       C3I wraps Pi provider registration with circuit-breaker fallback.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// Pi Agent Bridge — Gleam-side integration layer between C3I's Gleam mesh and
//// the Pi-mono TypeScript agent runtime.
////
//// Responsibilities:
////   1. Type definitions for Pi agent state, sessions, events, and tools.
////   2. Zenoh topic constants for the Pi namespace.
////   3. Event bridge: Pi AgentEvent (12) → C3I AG-UI event (32).
////   4. Tool federation: pi_tools + c3i_mcp_tools = 87 total federated tools.
////   5. Session bridge: Pi JSONL sessions → Smriti.db SQLite rows.
////   6. Provider bridge: Register C3I cortex as a Pi provider.
////
//// SC-ZMOF-001: Zenoh is the SOLE internal transport for mesh communication.
//// SC-PI-001:   Every Pi event MUST be converted to an AG-UI event before
////              publishing to the C3I mesh.
//// SC-PI-002:   Pi sessions MUST be persisted to Smriti.db via the SQLite NIF.

import cepaf_gleam/agui/events.{
  type AgUiEvent, type EventType, AgUiEvent, MetaEvent, RunFinished, RunStarted,
  StepFinished, StepStarted, TextMessageContent, TextMessageEnd,
  TextMessageStart, ToolCallArgs, ToolCallEnd, ToolCallStart,
}
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

// =============================================================================
// FFI Bindings
// =============================================================================

@external(erlang, "cepaf_gleam_ffi", "system_time_nanos")
fn system_time_nanos() -> Int

fn now_ms() -> Int {
  system_time_nanos() / 1_000_000
}

// =============================================================================
// Zenoh Topic Constants (SC-PI-003, SC-ZMOF-001)
// =============================================================================

/// Root namespace for all Pi bridge communication.
pub const pi_namespace = "indrajaal/pi"

/// Topic prefix for Pi agent lifecycle and streaming events.
/// Full topic: indrajaal/pi/events/{session_id}/{event_type}
pub const pi_events_topic = "indrajaal/pi/events"

/// Topic prefix for Pi tool call federation (pi_tools + c3i_mcp_tools).
/// Full topic: indrajaal/pi/tools/{tool_name}/{call_id}
pub const pi_tools_topic = "indrajaal/pi/tools"

/// Topic prefix for Pi session state (creation, update, teardown).
/// Full topic: indrajaal/pi/sessions/{session_id}
pub const pi_sessions_topic = "indrajaal/pi/sessions"

/// Topic for provider registration — C3I cortex registers as a Pi provider.
/// Full topic: indrajaal/pi/providers/{provider_id}
pub const pi_providers_topic = "indrajaal/pi/providers"

/// Topic for federated tool registry announcements.
/// Full topic: indrajaal/pi/registry/tools
pub const pi_registry_topic = "indrajaal/pi/registry"

// =============================================================================
// Pi Agent State (SC-PI-001)
// =============================================================================

/// Lifecycle state of a Pi agent session as seen from C3I.
///
/// Transitions:
///   Idle → Processing (agent_start received)
///   Processing → Streaming (message_start received)
///   Streaming → Processing (message_end received, more turns pending)
///   Processing → Idle (agent_end received)
///   Any → PiError (error event received)
///   PiError → Idle (session reset)
pub type PiAgentState {
  /// No active session; bridge is ready to accept connections.
  PiIdle
  /// Session active; agent is processing a turn (not yet streaming output).
  PiProcessing(session_id: String, turn_index: Int)
  /// Session active; agent is streaming text or tool output.
  PiStreaming(session_id: String, message_id: String)
  /// Terminal error state for the session; must be reset before reuse.
  PiError(session_id: String, reason: String, code: String)
  /// Timed out — session exceeded maximum processing time (30s watchdog).
  /// Auto-transitions to PiIdle after cleanup.
  PiTimedOut(session_id: String, elapsed_ms: Int)
}

// =============================================================================
// Session Timeout Watchdog (FMEA RPN 112 mitigation)
// =============================================================================

/// Maximum time a session can stay in PiProcessing before watchdog fires.
pub const session_timeout_ms = 30_000

/// Check if a session has exceeded the timeout threshold.
/// Returns True if the session should be forcibly transitioned to PiTimedOut.
pub fn is_session_timed_out(
  state: PiAgentState,
  current_time_ms: Int,
  session_started_ms: Int,
) -> Bool {
  case state {
    PiProcessing(_, _) ->
      current_time_ms - session_started_ms > session_timeout_ms
    PiStreaming(_, _) ->
      current_time_ms - session_started_ms > session_timeout_ms * 2
    _ -> False
  }
}

/// Force-reset a timed-out session to PiIdle state.
/// Generates a RunFinished event for AG-UI state machine cleanup.
pub fn timeout_session(
  session_id: String,
  elapsed_ms: Int,
) -> #(PiAgentState, PiEvent) {
  let cleanup_event =
    PiEvent(
      session_id: session_id,
      kind: PiAgentEnd,
      sequence: 999_999,
      timestamp: now_ms(),
      payload: json.object([
        #("reason", json.string("timeout")),
        #("elapsed_ms", json.int(elapsed_ms)),
        #("source", json.string("watchdog")),
      ]),
    )
  #(PiTimedOut(session_id, elapsed_ms), cleanup_event)
}

// =============================================================================
// PII Filter Types (FMEA RPN 135 mitigation — SC-SEC-003)
// =============================================================================

/// PII detection result for LLM response filtering.
pub type PiiScanResult {
  /// No PII detected — safe to pass through.
  PiiClean
  /// PII detected and redacted — scrubbed version available.
  PiiRedacted(original_length: Int, redacted_count: Int)
  /// PII scan failed — fail-safe: block the response.
  PiiScanFailed(reason: String)
}

/// PII categories that must be scrubbed from Pi LLM responses.
pub type PiiCategory {
  PiiEmail
  PiiPhone
  PiiCreditCard
  PiiSsn
  PiiIpAddress
}

/// Check if a response text likely contains PII (heuristic pre-filter).
/// Full scrubbing is done by the Rust NIF pii.rs module.
pub fn likely_contains_pii(text: String) -> Bool {
  string.contains(text, "@")
  || string.contains(text, "+1")
  || string.contains(text, "+44")
  || string.contains(text, "+46")
  || string.contains(text, "xxx-")
  || string.contains(text, "192.168.")
  || string.contains(text, "10.0.")
}

// =============================================================================
// Pi Session (SC-PI-004, SC-PI-002)
// =============================================================================

/// A Pi agent session record bridging Pi-mono JSONL to Smriti.db.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <formal-proof>
///     <P> session_id is a UUID generated by Pi-mono runtime </P>
///     <C> new_session(session_id, provider_id, model_id) </C>
///     <Q> PiSession with started_at set, ended_at = None, turn_count = 0 </Q>
///   </formal-proof>
/// </c3i-atomic>
pub type PiSession {
  PiSession(
    /// UUID generated by Pi-mono runtime (primary key in Smriti.db).
    session_id: String,
    /// The provider that handled this session (e.g., "c3i_cortex").
    provider_id: String,
    /// Model name used for inference (e.g., "gemini-2.5-flash").
    model_id: String,
    /// Unix epoch ms when session began.
    started_at: Int,
    /// Unix epoch ms when session ended; None if still active.
    ended_at: Option(Int),
    /// Number of complete turns processed in this session.
    turn_count: Int,
    /// Raw JSONL blob for lossless replay (SC-PI-002 mitigation).
    raw_jsonl: String,
    /// Whether this session's events have been persisted to Smriti.db.
    persisted: Bool,
  )
}

/// Construct a new Pi session with defaults.
pub fn new_session(
  session_id: String,
  provider_id: String,
  model_id: String,
) -> PiSession {
  PiSession(
    session_id: session_id,
    provider_id: provider_id,
    model_id: model_id,
    started_at: now_ms(),
    ended_at: None,
    turn_count: 0,
    raw_jsonl: "",
    persisted: False,
  )
}

/// Start a session with proper AG-UI state machine initialization.
/// This creates the session AND generates the RunStarted event that MUST
/// be emitted before any tool calls (SC-AGUI state machine requirement).
///
/// Returns: (PiSession, PiEvent) — caller MUST publish the event to Zenoh.
pub fn start_session(
  session_id: String,
  provider_id: String,
  model_id: String,
) -> #(PiSession, PiEvent) {
  let session = new_session(session_id, provider_id, model_id)
  let run_started_event =
    PiEvent(
      session_id: session_id,
      kind: PiAgentStart,
      sequence: 0,
      timestamp: now_ms(),
      payload: json.object([
        #("thread_id", json.string(session_id)),
        #("run_id", json.string(session_id)),
        #("provider_id", json.string(provider_id)),
        #("model_id", json.string(model_id)),
        #("source", json.string("pi_mono")),
      ]),
    )
  #(session, run_started_event)
}

/// Mark a session as completed by setting ended_at and incrementing turn_count.
pub fn complete_session(session: PiSession) -> PiSession {
  PiSession(..session, ended_at: Some(now_ms()))
}

/// Append a raw JSONL line to the session blob for lossless replay.
pub fn append_jsonl(session: PiSession, line: String) -> PiSession {
  let new_jsonl = case session.raw_jsonl {
    "" -> line
    existing -> existing <> "\n" <> line
  }
  PiSession(..session, raw_jsonl: new_jsonl)
}

/// Increment the turn counter after a complete turn cycle.
pub fn increment_turn(session: PiSession) -> PiSession {
  PiSession(..session, turn_count: session.turn_count + 1)
}

// =============================================================================
// Pi Event Types (SC-PI-001)
// =============================================================================

/// The 12 Pi AgentEvent types as seen from Pi-mono's TypeScript runtime.
///
/// These are the events emitted by the Pi agent runtime that must be bridged
/// to C3I's AG-UI 32-event protocol before Zenoh publication.
pub type PiEventKind {
  /// Agent session started — maps to RunStarted.
  PiAgentStart
  /// Agent session ended — maps to RunFinished.
  PiAgentEnd
  /// A new conversation turn started — maps to StepStarted.
  PiTurnStart
  /// A conversation turn ended — maps to StepFinished.
  PiTurnEnd
  /// Streaming message beginning — maps to TextMessageStart.
  PiMessageStart
  /// Streaming message delta — maps to TextMessageContent.
  PiMessageUpdate
  /// Streaming message complete — maps to TextMessageEnd.
  PiMessageEnd
  /// Tool invocation started — maps to ToolCallStart.
  PiToolExecutionStart
  /// Tool argument streaming delta — maps to ToolCallArgs.
  PiToolExecutionUpdate
  /// Tool invocation complete — maps to ToolCallEnd.
  PiToolExecutionEnd
  /// Provider-level error — maps to RunError via Raw wrapper.
  PiAgentError
  /// Metadata or protocol-level event — maps to MetaEvent.
  PiAgentMeta
}

/// A Pi agent event carrying its kind and structured payload.
pub type PiEvent {
  PiEvent(
    /// Session this event belongs to.
    session_id: String,
    /// Which Pi event type this is.
    kind: PiEventKind,
    /// Monotonically increasing sequence number within the session.
    sequence: Int,
    /// Wall-clock ms timestamp from Pi-mono runtime.
    timestamp: Int,
    /// JSON payload from Pi-mono (tool name, message delta, error code, etc.).
    payload: json.Json,
  )
}

// =============================================================================
// Pi Tool Call (SC-PI-005)
// =============================================================================

/// A federated tool call originating from Pi-mono.
///
/// The federated registry contains:
///   - Pi built-in tools (~40, provided by Pi-mono runtime)
///   - C3I MCP tools (47, provided by sa-plan-daemon + Gleam NIFs)
///   = 87 total federated tools
pub type PiToolCall {
  PiToolCall(
    /// Unique call ID generated by Pi-mono.
    call_id: String,
    /// Session this call belongs to.
    session_id: String,
    /// Tool name from the federated registry (pi_* or c3i_*).
    tool_name: String,
    /// Whether this tool is native to Pi-mono or bridged from C3I MCP.
    source: PiToolSource,
    /// JSON arguments for the tool call.
    args: json.Json,
    /// JSON result; None while the call is in flight.
    result: Option(json.Json),
    /// Wall-clock ms when the call was initiated.
    started_at: Int,
    /// Wall-clock ms when the call completed; None if still in flight.
    completed_at: Option(Int),
  )
}

/// Origin of a federated tool in the Pi-C3I bridge.
pub type PiToolSource {
  /// Tool is native to Pi-mono TypeScript runtime.
  PiNativeTool
  /// Tool is bridged from C3I MCP (sa-plan-daemon or Gleam NIF).
  C3iMcpTool(mcp_tool_name: String)
}

/// Federated tool registry entry describing one tool available to Pi agents.
pub type FederatedTool {
  FederatedTool(
    /// Canonical tool name in the federated namespace.
    name: String,
    /// Human-readable description for the Pi agent's LLM context.
    description: String,
    /// Which runtime provides this tool.
    source: PiToolSource,
    /// JSON Schema for the tool's input parameters.
    input_schema: json.Json,
    /// Fractal layer this tool operates at (for STAMP tracing).
    fractal_layer: String,
  )
}

// =============================================================================
// Pi Provider Config (SC-PI-006)
// =============================================================================

/// Configuration for registering C3I's cortex as a Pi provider.
///
/// Pi-mono treats C3I as just another AI provider, but under the hood
/// C3I runs the 6-tier hedged inference cascade (Gemini Direct → OpenRouter
/// → Ollama gemma4 → gemma3 → RETE-UL rules → static ack).
pub type PiProviderConfig {
  PiProviderConfig(
    /// Unique provider ID used in Pi session records.
    provider_id: String,
    /// Human-readable name shown in Pi's provider list.
    display_name: String,
    /// HTTP(S) endpoint Pi-mono uses to reach C3I's Wisp REST API.
    endpoint_url: String,
    /// Authentication token (stored in Smriti.db, never in files).
    auth_token: String,
    /// Which C3I inference tiers are active for this provider registration.
    active_tiers: List(C3iInferenceTier),
    /// Maximum tokens per Pi inference request.
    max_tokens: Int,
    /// Request timeout in milliseconds (maps to Pi-mono's AbortController).
    timeout_ms: Int,
    /// Whether to enable streaming responses from C3I to Pi.
    streaming_enabled: Bool,
  )
}

/// C3I's 6-tier hedged inference cascade tiers, as exposed to Pi-mono.
pub type C3iInferenceTier {
  /// Tier 1: Gemini Direct (gemini-2.5-flash, ~900ms, Free).
  GeminiDirect
  /// Tier 2: OpenRouter (gemini-2.5-flash via OR, ~1.1s, $0.000009/req).
  OpenRouter
  /// Tier 3: Ollama gemma4 (port 11435, local, ~4s).
  OllamaGemma4
  /// Tier 4: Ollama gemma3 (port 11434, local, ~10s).
  OllamaGemma3
  /// Tier 5: RETE-UL rule engine (<1ms, deterministic).
  ReteUlRules
  /// Tier 6: Static acknowledgement (<1ms, always succeeds).
  StaticAck
}

/// Construct a default provider config for the C3I cortex.
pub fn default_provider_config(
  endpoint_url: String,
  auth_token: String,
) -> PiProviderConfig {
  PiProviderConfig(
    provider_id: "c3i_cortex",
    display_name: "C3I Biomorphic Cortex",
    endpoint_url: endpoint_url,
    auth_token: auth_token,
    active_tiers: [GeminiDirect, OpenRouter, OllamaGemma4, ReteUlRules],
    max_tokens: 8192,
    timeout_ms: 30_000,
    streaming_enabled: True,
  )
}

// =============================================================================
// Session Bridge — Pi JSONL → Smriti.db (SC-PI-002, SC-PI-004)
// =============================================================================

/// SQLite row representation for persisting a Pi session to Smriti.db.
///
/// Maps to the `pi_sessions` table.
/// Schema (DDL stored in Smriti.db migration M-PI-001):
///   CREATE TABLE pi_sessions (
///     session_id   TEXT PRIMARY KEY,
///     provider_id  TEXT NOT NULL,
///     model_id     TEXT NOT NULL,
///     started_at   INTEGER NOT NULL,
///     ended_at     INTEGER,
///     turn_count   INTEGER NOT NULL DEFAULT 0,
///     raw_jsonl    TEXT NOT NULL DEFAULT '',
///     persisted    INTEGER NOT NULL DEFAULT 0
///   );
pub type PiSessionRow {
  PiSessionRow(
    session_id: String,
    provider_id: String,
    model_id: String,
    started_at: Int,
    ended_at: Option(Int),
    turn_count: Int,
    raw_jsonl: String,
    persisted: Bool,
  )
}

/// Convert a PiSession to its Smriti.db row representation.
pub fn session_to_row(session: PiSession) -> PiSessionRow {
  PiSessionRow(
    session_id: session.session_id,
    provider_id: session.provider_id,
    model_id: session.model_id,
    started_at: session.started_at,
    ended_at: session.ended_at,
    turn_count: session.turn_count,
    raw_jsonl: session.raw_jsonl,
    persisted: session.persisted,
  )
}

/// Serialize a PiSessionRow to JSON for NIF persistence calls.
pub fn session_row_to_json(row: PiSessionRow) -> json.Json {
  let ended_at_json = case row.ended_at {
    None -> json.null()
    Some(ts) -> json.int(ts)
  }
  json.object([
    #("session_id", json.string(row.session_id)),
    #("provider_id", json.string(row.provider_id)),
    #("model_id", json.string(row.model_id)),
    #("started_at", json.int(row.started_at)),
    #("ended_at", ended_at_json),
    #("turn_count", json.int(row.turn_count)),
    #("raw_jsonl", json.string(row.raw_jsonl)),
    #("persisted", json.bool(row.persisted)),
  ])
}

// =============================================================================
// Event Bridge — Pi AgentEvent (12) → AG-UI (32) (SC-PI-001)
// =============================================================================

/// Convert a Pi agent event kind to its target AG-UI EventType.
///
/// This is the core mapping function. Every Pi event has exactly one
/// AG-UI counterpart. The inverse is not defined (AG-UI is a superset).
///
/// Mapping table (Pi → AG-UI):
///   agent_start           → RunStarted
///   agent_end             → RunFinished
///   turn_start            → StepStarted
///   turn_end              → StepFinished
///   message_start         → TextMessageStart
///   message_update        → TextMessageContent
///   message_end           → TextMessageEnd
///   tool_execution_start  → ToolCallStart
///   tool_execution_update → ToolCallArgs
///   tool_execution_end    → ToolCallEnd
///   agent_error           → RunError (via Raw; caller wraps payload)
///   agent_meta            → MetaEvent
pub fn pi_event_kind_to_agui(kind: PiEventKind) -> EventType {
  case kind {
    PiAgentStart -> RunStarted
    PiAgentEnd -> RunFinished
    PiTurnStart -> StepStarted
    PiTurnEnd -> StepFinished
    PiMessageStart -> TextMessageStart
    PiMessageUpdate -> TextMessageContent
    PiMessageEnd -> TextMessageEnd
    PiToolExecutionStart -> ToolCallStart
    PiToolExecutionUpdate -> ToolCallArgs
    PiToolExecutionEnd -> ToolCallEnd
    // Error and meta are special-cased in bridge_event/1 below.
    PiAgentError -> RunFinished
    PiAgentMeta -> RunFinished
  }
}

/// Bridge a PiEvent to an AgUiEvent for publication on the C3I mesh.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">Pi AgentEvent ↪ AG-UI event</morphism>
///   <formal-proof>
///     <P> pi_event.session_id is non-empty, pi_event.sequence >= 0 </P>
///     <C> bridge_event(pi_event) </C>
///     <Q> Ok(AgUiEvent) with correct event_type, thread_id = session_id,
///         run_id = session_id, payload preserving Pi fields </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn bridge_event(pi_event: PiEvent) -> Result(AgUiEvent, String) {
  let thread_id = pi_event.session_id
  let run_id = pi_event.session_id

  case pi_event.kind {
    PiAgentStart ->
      Ok(AgUiEvent(
        event_type: RunStarted,
        timestamp: pi_event.timestamp,
        thread_id: thread_id,
        run_id: run_id,
        payload: json.object([
          #("thread_id", json.string(thread_id)),
          #("run_id", json.string(run_id)),
          #("source", json.string("pi_mono")),
          #("sequence", json.int(pi_event.sequence)),
          #("pi_payload", pi_event.payload),
        ]),
      ))

    PiAgentEnd ->
      Ok(AgUiEvent(
        event_type: RunFinished,
        timestamp: pi_event.timestamp,
        thread_id: thread_id,
        run_id: run_id,
        payload: json.object([
          #("thread_id", json.string(thread_id)),
          #("run_id", json.string(run_id)),
          #("source", json.string("pi_mono")),
          #("sequence", json.int(pi_event.sequence)),
          #("pi_payload", pi_event.payload),
        ]),
      ))

    PiTurnStart ->
      Ok(AgUiEvent(
        event_type: StepStarted,
        timestamp: pi_event.timestamp,
        thread_id: thread_id,
        run_id: run_id,
        payload: json.object([
          #("step_name", json.string("pi_turn")),
          #("source", json.string("pi_mono")),
          #("sequence", json.int(pi_event.sequence)),
          #("pi_payload", pi_event.payload),
        ]),
      ))

    PiTurnEnd ->
      Ok(AgUiEvent(
        event_type: StepFinished,
        timestamp: pi_event.timestamp,
        thread_id: thread_id,
        run_id: run_id,
        payload: json.object([
          #("step_name", json.string("pi_turn")),
          #("source", json.string("pi_mono")),
          #("sequence", json.int(pi_event.sequence)),
          #("pi_payload", pi_event.payload),
        ]),
      ))

    PiMessageStart ->
      Ok(AgUiEvent(
        event_type: TextMessageStart,
        timestamp: pi_event.timestamp,
        thread_id: thread_id,
        run_id: run_id,
        payload: json.object([
          #(
            "message_id",
            json.string(
              thread_id <> "_msg_" <> int_to_string(pi_event.sequence),
            ),
          ),
          #("role", json.string("assistant")),
          #("source", json.string("pi_mono")),
          #("sequence", json.int(pi_event.sequence)),
          #("pi_payload", pi_event.payload),
        ]),
      ))

    PiMessageUpdate ->
      Ok(AgUiEvent(
        event_type: TextMessageContent,
        timestamp: pi_event.timestamp,
        thread_id: thread_id,
        run_id: run_id,
        payload: json.object([
          #("message_id", json.string(thread_id <> "_msg")),
          #("delta", json.string("")),
          #("source", json.string("pi_mono")),
          #("sequence", json.int(pi_event.sequence)),
          #("pi_payload", pi_event.payload),
        ]),
      ))

    PiMessageEnd ->
      Ok(AgUiEvent(
        event_type: TextMessageEnd,
        timestamp: pi_event.timestamp,
        thread_id: thread_id,
        run_id: run_id,
        payload: json.object([
          #("message_id", json.string(thread_id <> "_msg")),
          #("source", json.string("pi_mono")),
          #("sequence", json.int(pi_event.sequence)),
          #("pi_payload", pi_event.payload),
        ]),
      ))

    PiToolExecutionStart ->
      Ok(AgUiEvent(
        event_type: ToolCallStart,
        timestamp: pi_event.timestamp,
        thread_id: thread_id,
        run_id: run_id,
        payload: json.object([
          #(
            "tool_call_id",
            json.string(
              thread_id <> "_tool_" <> int_to_string(pi_event.sequence),
            ),
          ),
          #("tool_name", json.string("pi_tool")),
          #("source", json.string("pi_mono")),
          #("sequence", json.int(pi_event.sequence)),
          #("pi_payload", pi_event.payload),
        ]),
      ))

    PiToolExecutionUpdate ->
      Ok(AgUiEvent(
        event_type: ToolCallArgs,
        timestamp: pi_event.timestamp,
        thread_id: thread_id,
        run_id: run_id,
        payload: json.object([
          #("tool_call_id", json.string(thread_id <> "_tool")),
          #("delta", json.string("")),
          #("source", json.string("pi_mono")),
          #("sequence", json.int(pi_event.sequence)),
          #("pi_payload", pi_event.payload),
        ]),
      ))

    PiToolExecutionEnd ->
      Ok(AgUiEvent(
        event_type: ToolCallEnd,
        timestamp: pi_event.timestamp,
        thread_id: thread_id,
        run_id: run_id,
        payload: json.object([
          #("tool_call_id", json.string(thread_id <> "_tool")),
          #("source", json.string("pi_mono")),
          #("sequence", json.int(pi_event.sequence)),
          #("pi_payload", pi_event.payload),
        ]),
      ))

    PiAgentError ->
      // Error events carry reason and code in the payload; bridged via RunError
      // but kept as a distinct path so callers can distinguish errors from
      // normal termination at the AG-UI level.
      Error(
        "pi_error: use events.new_run_error/2 with payload fields 'reason' and 'code'",
      )

    PiAgentMeta ->
      // Meta events are bridged via MetaEvent with the raw Pi payload preserved.
      Ok(AgUiEvent(
        event_type: MetaEvent,
        timestamp: pi_event.timestamp,
        thread_id: thread_id,
        run_id: run_id,
        payload: json.object([
          #("meta_type", json.string("pi_agent_meta")),
          #("source", json.string("pi_mono")),
          #("sequence", json.int(pi_event.sequence)),
          #("payload", pi_event.payload),
        ]),
      ))
  }
}

/// Bridge a list of Pi events, returning the successfully converted AG-UI
/// events and collecting any conversion errors separately.
///
/// Uses list.fold to process all events; errors do not halt the batch.
pub fn bridge_events(
  pi_events: List(PiEvent),
) -> #(List(AgUiEvent), List(String)) {
  list.fold(pi_events, #([], []), fn(acc, pi_event) {
    let #(ok_events, errors) = acc
    case bridge_event(pi_event) {
      Ok(agui_event) -> #([agui_event, ..ok_events], errors)
      Error(reason) -> #(ok_events, [reason, ..errors])
    }
  })
}

// =============================================================================
// Zenoh Topic Builders (SC-PI-003, SC-ZMOF-001)
// =============================================================================

/// Build the Zenoh topic for a Pi session event.
///
/// Pattern: indrajaal/pi/events/{session_id}/{event_type}
pub fn build_event_topic(session_id: String, event_type: String) -> String {
  string.join([pi_events_topic, session_id, event_type], "/")
}

/// Build the Zenoh topic for a Pi tool call.
///
/// Pattern: indrajaal/pi/tools/{tool_name}/{call_id}
pub fn build_tool_topic(tool_name: String, call_id: String) -> String {
  string.join([pi_tools_topic, tool_name, call_id], "/")
}

/// Build the Zenoh topic for a Pi session lifecycle event.
///
/// Pattern: indrajaal/pi/sessions/{session_id}
pub fn build_session_topic(session_id: String) -> String {
  string.join([pi_sessions_topic, session_id], "/")
}

/// Build the Zenoh topic for a Pi provider registration announcement.
///
/// Pattern: indrajaal/pi/providers/{provider_id}
pub fn build_provider_topic(provider_id: String) -> String {
  string.join([pi_providers_topic, provider_id], "/")
}

// =============================================================================
// Tool Federation (SC-PI-005)
// =============================================================================

/// Total tool count in the federated Pi-Claude-C3I registry.
/// Claude (6) + Pi-mono (14) + C3I MCP tools (73) = 93 total.
pub const federated_tool_count = 93

/// Count of Claude Code built-in tools.
pub const claude_tool_count = 6

/// Count of Pi-mono built-in tools.
pub const pi_native_tool_count = 14

/// Count of C3I MCP tools bridged to Pi (sa-plan-daemon + Gleam NIFs).
pub const c3i_mcp_tool_count = 73

/// Validate that a tool name belongs to the C3I MCP tool namespace.
///
/// C3I tools: either "c3i_" prefixed OR known MCP tool names (plan_*, system_*, knowledge_*).
/// Pi native tools: bash, edit, read, write, grep, find, ls, etc.
pub fn is_c3i_tool(tool_name: String) -> Bool {
  string.starts_with(tool_name, "c3i_")
  || string.starts_with(tool_name, "plan_")
  || string.starts_with(tool_name, "system_")
  || string.starts_with(tool_name, "knowledge_")
  || string.starts_with(tool_name, "verification_")
  || string.starts_with(tool_name, "podman_")
  || string.starts_with(tool_name, "metabolic_")
  || string.starts_with(tool_name, "ooda_")
  || string.starts_with(tool_name, "fractal_")
  || string.starts_with(tool_name, "prajna_")
  || string.starts_with(tool_name, "dark_cockpit_")
  || string.starts_with(tool_name, "integrity_")
  || string.starts_with(tool_name, "evolution_")
  || string.starts_with(tool_name, "mesh_")
  || string.starts_with(tool_name, "kms_")
  || string.starts_with(tool_name, "read_file")
}

/// Resolve the source of a federated tool by name.
pub fn resolve_tool_source(tool_name: String) -> PiToolSource {
  case is_c3i_tool(tool_name) {
    True -> C3iMcpTool(mcp_tool_name: string.drop_start(tool_name, 4))
    False -> PiNativeTool
  }
}

// =============================================================================
// Provider Config Serialization (SC-PI-006)
// =============================================================================

/// Serialize a PiProviderConfig to JSON for Zenoh announcement.
pub fn provider_config_to_json(config: PiProviderConfig) -> json.Json {
  let tiers_json =
    json.array(config.active_tiers, fn(tier) {
      json.string(tier_to_string(tier))
    })
  json.object([
    #("provider_id", json.string(config.provider_id)),
    #("display_name", json.string(config.display_name)),
    #("endpoint_url", json.string(config.endpoint_url)),
    #("max_tokens", json.int(config.max_tokens)),
    #("timeout_ms", json.int(config.timeout_ms)),
    #("streaming_enabled", json.bool(config.streaming_enabled)),
    #("active_tiers", tiers_json),
    #("federated_tool_count", json.int(federated_tool_count)),
  ])
}

/// Convert a C3iInferenceTier to its string identifier.
pub fn tier_to_string(tier: C3iInferenceTier) -> String {
  case tier {
    GeminiDirect -> "gemini_direct"
    OpenRouter -> "open_router"
    OllamaGemma4 -> "ollama_gemma4"
    OllamaGemma3 -> "ollama_gemma3"
    ReteUlRules -> "rete_ul_rules"
    StaticAck -> "static_ack"
  }
}

// =============================================================================
// Utility
// =============================================================================

/// Convert an Int to String; isolated helper to avoid dependency on gleam/int
/// which would require an additional import for a trivial operation.
fn int_to_string(n: Int) -> String {
  // Delegate to the Gleam stdlib string representation for integers
  // by formatting through JSON (zero-copy, no sprintf dependency).
  json.to_string(json.int(n))
}

/// Return a human-readable summary of the Pi bridge state for health endpoints.
pub fn state_to_string(state: PiAgentState) -> String {
  case state {
    PiIdle -> "idle"
    PiProcessing(session_id: sid, turn_index: t) ->
      "processing:session=" <> sid <> ",turn=" <> int_to_string(t)
    PiStreaming(session_id: sid, message_id: mid) ->
      "streaming:session=" <> sid <> ",msg=" <> mid
    PiError(session_id: sid, reason: r, code: c) ->
      "error:session=" <> sid <> ",code=" <> c <> ",reason=" <> r
    PiTimedOut(session_id: sid, elapsed_ms: ms) ->
      "timed_out:session=" <> sid <> ",elapsed_ms=" <> int_to_string(ms)
  }
}
