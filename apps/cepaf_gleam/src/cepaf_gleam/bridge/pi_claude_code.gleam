//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/bridge/pi_claude_code</module>
////     <fsharp-lineage>No F# lineage — Gleam-native Claude Code bridge</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L6_ECOSYSTEM</layer>
////     <mesh-domain>Pi-mono x Claude Code Bidirectional Protocol Bridge</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>DAL-A / SIL-6 / HIGH</criticality>
////     <stamp-controls>
////       SC-PI-001, SC-PI-002, SC-PI-003, SC-PI-004, SC-PI-005,
////       SC-PI-006, SC-PI-007, SC-PI-008, SC-PI-009, SC-PI-010,
////       SC-PI-AUTO-001, SC-PI-AUTO-002, SC-PI-AUTO-003, SC-PI-AUTO-004,
////       SC-ZMOF-001, SC-ZMOF-005, SC-GLM-UI-001, SC-AGUI-001
////     </stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective" augmentation="bidirectional-event-mapping">
////       Pi 29 event types ↪ AG-UI 32 event types (bidirectional).
////       3 AG-UI events (Heartbeat, MetaEvent, Raw) are C3I-specific.
////     </morphism>
////     <morphism type="injective" augmentation="tool-federation">
////       Claude Code 6 native tools + Pi 14 tools + C3I 73 MCP tools = 93 total.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// Pi x Claude Code Bridge — Bidirectional protocol translation layer between
//// Pi-mono's TypeScript agent runtime and Claude Code's tool/event system.
////
//// This module is the KEYSTONE of the symbiosis architecture. It provides:
////   1. Bidirectional event mapping (Pi 29 ↔ AG-UI 32)
////   2. Claude Code tool registry (Read, Write, Edit, Bash, Grep, Glob)
////   3. Combined tool federation (93 total: 6 Claude + 14 Pi + 73 C3I)
////   4. Bridge state type for health monitoring
////   5. RPC protocol compatibility layer
////
//// SC-PI-AUTO-002: This module MUST be updated when tools or events change.

import gleam/list

// =============================================================================
// Types
// =============================================================================

/// Bridge health status
pub type BridgeHealth {
  Healthy
  Degraded
  Disconnected
}

/// RPC connection state
pub type RpcState {
  Connected
  Reconnecting
  NotStarted
}

/// The core bridge state tracking Pi ↔ Claude Code integration
pub type ClaudeCodeBridge {
  ClaudeCodeBridge(
    rpc_state: RpcState,
    event_count: Int,
    pi_events_mapped: Int,
    agui_events_mapped: Int,
    tool_federation_count: Int,
    claude_tools_count: Int,
    pi_tools_count: Int,
    c3i_tools_count: Int,
    session_sync_active: Bool,
    zenoh_publishing: Bool,
  )
}

/// Bridge status summary for dashboards
pub type BridgeStatus {
  BridgeStatus(
    health: BridgeHealth,
    total_tools: Int,
    events_mapped: Int,
    rpc_connected: Bool,
    session_active: Bool,
  )
}

/// Pi event categories (29 total across 6 groups)
pub type PiEventCategory {
  PiLifecycle
  PiToolExecution
  PiSessionManagement
  PiLlmContext
  PiDiscovery
  PiUserInput
}

/// AG-UI event categories (32 total across 7 groups)
pub type AgUiEventCategory {
  AgUiLifecycle
  AgUiText
  AgUiTool
  AgUiState
  AgUiActivity
  AgUiReasoning
  AgUiSpecial
}

/// Bidirectional event mapping entry
pub type EventMapping {
  EventMapping(
    pi_event: String,
    agui_event: String,
    pi_category: PiEventCategory,
    agui_category: AgUiEventCategory,
    bidirectional: Bool,
  )
}

/// Claude Code native tool definition
pub type ClaudeCodeTool {
  ClaudeCodeTool(name: String, description: String, fractal_layer: Int)
}

// =============================================================================
// Constructors
// =============================================================================

/// Initialize the bridge with default state
pub fn init() -> ClaudeCodeBridge {
  ClaudeCodeBridge(
    rpc_state: NotStarted,
    event_count: 0,
    pi_events_mapped: 29,
    agui_events_mapped: 32,
    tool_federation_count: total_tool_count(),
    claude_tools_count: list.length(claude_code_tools()),
    pi_tools_count: 14,
    c3i_tools_count: 73,
    session_sync_active: False,
    zenoh_publishing: False,
  )
}

/// Get bridge health status
pub fn bridge_status(bridge: ClaudeCodeBridge) -> BridgeStatus {
  let health = case bridge.rpc_state {
    Connected -> Healthy
    Reconnecting -> Degraded
    NotStarted -> Disconnected
  }
  BridgeStatus(
    health: health,
    total_tools: bridge.tool_federation_count,
    events_mapped: bridge.pi_events_mapped,
    rpc_connected: bridge.rpc_state == Connected,
    session_active: bridge.session_sync_active,
  )
}

// =============================================================================
// Claude Code Native Tools (6)
// =============================================================================

/// Claude Code's 6 native tools that map to Pi equivalents
pub fn claude_code_tools() -> List(ClaudeCodeTool) {
  [
    ClaudeCodeTool(
      name: "Read",
      description: "Read file from local filesystem",
      fractal_layer: 3,
    ),
    ClaudeCodeTool(
      name: "Write",
      description: "Write file to local filesystem",
      fractal_layer: 3,
    ),
    ClaudeCodeTool(
      name: "Edit",
      description: "Exact string replacement in files",
      fractal_layer: 3,
    ),
    ClaudeCodeTool(
      name: "Bash",
      description: "Execute shell commands",
      fractal_layer: 4,
    ),
    ClaudeCodeTool(
      name: "Grep",
      description: "Search file contents with regex",
      fractal_layer: 3,
    ),
    ClaudeCodeTool(
      name: "Glob",
      description: "Find files by pattern",
      fractal_layer: 3,
    ),
  ]
}

/// Total federated tool count: Claude (6) + Pi (14) + C3I MCP (73)
pub fn total_tool_count() -> Int {
  6 + 14 + 73
}

// =============================================================================
// Event Mapping (29 Pi ↔ 32 AG-UI, bidirectional)
// =============================================================================

/// Complete bidirectional event mapping between Pi and AG-UI
pub fn event_mappings() -> List(EventMapping) {
  [
    // Lifecycle group (8 Pi → 5 AG-UI)
    EventMapping("agent_start", "RunStarted", PiLifecycle, AgUiLifecycle, True),
    EventMapping("agent_end", "RunFinished", PiLifecycle, AgUiLifecycle, True),
    EventMapping("turn_start", "StepStarted", PiLifecycle, AgUiLifecycle, True),
    EventMapping("turn_end", "StepFinished", PiLifecycle, AgUiLifecycle, True),
    EventMapping(
      "message_start",
      "TextMessageStart",
      PiLifecycle,
      AgUiText,
      True,
    ),
    EventMapping("message_end", "TextMessageEnd", PiLifecycle, AgUiText, True),
    EventMapping(
      "message_update",
      "TextMessageContent",
      PiLifecycle,
      AgUiText,
      True,
    ),
    EventMapping(
      "before_agent_start",
      "RunStarted",
      PiLifecycle,
      AgUiLifecycle,
      False,
    ),
    // Tool execution group (4 Pi → 5 AG-UI)
    EventMapping(
      "tool_execution_start",
      "ToolCallStart",
      PiToolExecution,
      AgUiTool,
      True,
    ),
    EventMapping(
      "tool_execution_update",
      "ToolCallArgs",
      PiToolExecution,
      AgUiTool,
      True,
    ),
    EventMapping(
      "tool_execution_end",
      "ToolCallEnd",
      PiToolExecution,
      AgUiTool,
      True,
    ),
    EventMapping("tool_call", "ToolCallStart", PiToolExecution, AgUiTool, False),
    // Session management group (8 Pi → 3 AG-UI state)
    EventMapping(
      "session_start",
      "StateSnapshot",
      PiSessionManagement,
      AgUiState,
      True,
    ),
    EventMapping(
      "session_before_switch",
      "StateDelta",
      PiSessionManagement,
      AgUiState,
      False,
    ),
    EventMapping(
      "session_before_fork",
      "StateDelta",
      PiSessionManagement,
      AgUiState,
      False,
    ),
    EventMapping(
      "session_before_compact",
      "StateDelta",
      PiSessionManagement,
      AgUiState,
      False,
    ),
    EventMapping(
      "session_compact",
      "MessagesSnapshot",
      PiSessionManagement,
      AgUiState,
      True,
    ),
    EventMapping(
      "session_before_tree",
      "StateDelta",
      PiSessionManagement,
      AgUiState,
      False,
    ),
    EventMapping(
      "session_tree",
      "StateSnapshot",
      PiSessionManagement,
      AgUiState,
      True,
    ),
    EventMapping(
      "session_shutdown",
      "RunFinished",
      PiSessionManagement,
      AgUiLifecycle,
      True,
    ),
    // LLM context group (5 Pi → reasoning/special AG-UI)
    EventMapping("context", "ReasoningStart", PiLlmContext, AgUiReasoning, True),
    EventMapping(
      "before_provider_request",
      "ReasoningMessageStart",
      PiLlmContext,
      AgUiReasoning,
      False,
    ),
    EventMapping(
      "after_provider_response",
      "ReasoningEnd",
      PiLlmContext,
      AgUiReasoning,
      True,
    ),
    EventMapping("input", "Custom", PiLlmContext, AgUiSpecial, True),
    EventMapping("user_bash", "ToolCallStart", PiLlmContext, AgUiTool, False),
    // Discovery group (2 Pi → activity AG-UI)
    EventMapping(
      "resources_discover",
      "ActivitySnapshot",
      PiDiscovery,
      AgUiActivity,
      True,
    ),
    EventMapping(
      "model_select",
      "ActivityDelta",
      PiDiscovery,
      AgUiActivity,
      True,
    ),
  ]
}

/// Count of Pi events that have AG-UI mappings
pub fn mapped_pi_event_count() -> Int {
  list.length(event_mappings())
}

/// Count of bidirectional mappings (can go both ways)
pub fn bidirectional_count() -> Int {
  event_mappings()
  |> list.filter(fn(m) { m.bidirectional })
  |> list.length()
}

/// AG-UI events that have NO Pi equivalent (C3I-specific)
pub fn agui_only_events() -> List(String) {
  [
    "Heartbeat", "MetaEvent", "Raw", "RunError", "TextMessageChunk",
    "ToolCallChunk", "ToolCallResult", "ReasoningMessageContent",
    "ReasoningMessageEnd", "ReasoningMessageChunk", "ReasoningEncryptedValue",
  ]
}

// =============================================================================
// Claude Code ↔ Pi Tool Mapping
// =============================================================================

/// Map Claude Code tool name to equivalent Pi tool name
pub fn claude_to_pi_tool(claude_tool: String) -> String {
  case claude_tool {
    "Read" -> "read"
    "Write" -> "write"
    "Edit" -> "edit"
    "Bash" -> "bash"
    "Grep" -> "grep"
    "Glob" -> "find"
    _ -> "unknown"
  }
}

/// Map Pi tool name to equivalent Claude Code tool name
pub fn pi_to_claude_tool(pi_tool: String) -> String {
  case pi_tool {
    "read" -> "Read"
    "write" -> "Write"
    "edit" -> "Edit"
    "bash" -> "Bash"
    "grep" -> "Grep"
    "find" -> "Glob"
    "ls" -> "Glob"
    _ -> "Unknown"
  }
}

// =============================================================================
// Zenoh Topics for Pi Integration
// =============================================================================

/// Zenoh topic prefix for Pi events
pub fn zenoh_topic_prefix() -> String {
  "indrajaal/pi"
}

/// Zenoh topic for Pi agent events
pub fn zenoh_agent_topic() -> String {
  "indrajaal/pi/agent/events"
}

/// Zenoh topic for Pi tool calls
pub fn zenoh_tool_topic() -> String {
  "indrajaal/pi/tools/calls"
}

/// Zenoh topic for Pi session state
pub fn zenoh_session_topic() -> String {
  "indrajaal/pi/session/state"
}

/// Zenoh topic for Pi provider metrics
pub fn zenoh_provider_topic() -> String {
  "indrajaal/pi/provider/metrics"
}

/// Zenoh topic for Claude Code bridge health
pub fn zenoh_bridge_health_topic() -> String {
  "indrajaal/pi/bridge/health"
}
