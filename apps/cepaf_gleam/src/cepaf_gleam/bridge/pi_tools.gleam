//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/bridge/pi_tools</module>
////     <fsharp-lineage>N/A — native Gleam federation layer</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L3_TRANSACTION</layer>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-PI-002, SC-PI-003, SC-SAFETY-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       Pi tool registry ↪ FederatedTool list.
////       14 Pi tools + 73 C3I MCP tools = 87 total.
////       L0 tools gated by GuardianRequired (SC-PI-002).
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// Pi Tools Federation Module
////
//// Federates C3I's 73 MCP tools and Pi's 14 tools into a unified 87-tool
//// registry. SC-PI-002 mandate: L0 Constitutional tools MUST be gated by
//// Guardian approval before dispatch.
////
//// Layer: L3_TRANSACTION
//// STAMP: SC-PI-002, SC-PI-003

import gleam/list

// =============================================================================
// Types
// =============================================================================

pub type ToolSource {
  PiTool
  C3iTool
}

pub type FractalGate {
  NoGate
  GuardianRequired
  ConsensusRequired
}

/// Guardian enforcement policy — controls how strictly gates are enforced.
///
/// ## Policy Options
///
/// | Policy | Description | Use Case |
/// |--------|-------------|----------|
/// | `Permissive` | ALL tools allowed without gate checks. No blocking. | Development, CI, automated agents |
/// | `AuditOnly` | Gates checked, violations LOGGED but NOT blocked. | Staging, testing with audit trail |
/// | `EnforceNonL0` | L1-L7 gates enforced, L0 Constitutional auto-allowed. | Normal operations |
/// | `EnforceAll` | ALL gates enforced including L0 Constitutional. HITL required. | Production safety-critical |
/// | `Lockdown` | ALL tools blocked except read-only. Emergency only. | Incident response, emergency stop |
///
/// ## Changing Policy at Runtime
///
/// ```gleam
/// // Create default (Permissive for dev)
/// let policy = default_guardian_policy()
///
/// // Or create specific policy
/// let policy = GuardianPolicy(
///   mode: EnforceAll,
///   auto_allow_layers: [],
///   audit_all: True,
///   emergency_override: False,
/// )
///
/// // Check if a tool is allowed
/// let allowed = is_tool_allowed(policy, tool)
/// ```
pub type GuardianMode {
  /// All tools pass — no gate enforcement. Best for development.
  Permissive
  /// Gates checked and logged but never block execution.
  AuditOnly
  /// L1-L7 enforced, L0 auto-allowed (for operators with L0 trust).
  EnforceNonL0
  /// Full enforcement — all gated tools require approval.
  EnforceAll
  /// Emergency lockdown — only read-only tools allowed.
  Lockdown
}

/// Configurable Guardian policy with per-layer overrides.
pub type GuardianPolicy {
  GuardianPolicy(
    /// Which enforcement mode is active.
    mode: GuardianMode,
    /// Layers where gates are auto-allowed regardless of mode.
    /// Example: [3, 5] means L3 and L5 tools always pass.
    auto_allow_layers: List(Int),
    /// Whether to log all gate decisions (even allowed ones).
    audit_all: Bool,
    /// Emergency override — temporarily allows all operations.
    /// MUST be time-limited. Resets to False on next OODA cycle.
    emergency_override: Bool,
  )
}

/// Gate check result with audit information.
pub type GateDecision {
  /// Tool is allowed to execute.
  Allowed(reason: String)
  /// Tool execution is blocked — requires approval.
  Blocked(reason: String)
  /// Tool is allowed but violation was logged for audit.
  AllowedWithAudit(reason: String)
}

/// Default policy: PERMISSIVE for development.
/// Change to EnforceAll for production deployments.
pub fn default_guardian_policy() -> GuardianPolicy {
  GuardianPolicy(
    mode: Permissive,
    auto_allow_layers: [],
    audit_all: False,
    emergency_override: False,
  )
}

/// Production policy: full enforcement with audit logging.
pub fn production_guardian_policy() -> GuardianPolicy {
  GuardianPolicy(
    mode: EnforceAll,
    auto_allow_layers: [],
    audit_all: True,
    emergency_override: False,
  )
}

/// Staging policy: audit-only mode for testing without blocking.
pub fn staging_guardian_policy() -> GuardianPolicy {
  GuardianPolicy(
    mode: AuditOnly,
    auto_allow_layers: [],
    audit_all: True,
    emergency_override: False,
  )
}

/// Operator policy: enforce everything except L0 (trusted operator).
pub fn operator_guardian_policy() -> GuardianPolicy {
  GuardianPolicy(
    mode: EnforceNonL0,
    auto_allow_layers: [0],
    audit_all: True,
    emergency_override: False,
  )
}

/// Check if a tool is allowed under the current Guardian policy.
///
/// Returns a GateDecision with the reason for the decision.
pub fn check_gate(policy: GuardianPolicy, tool: FederatedTool) -> GateDecision {
  // Emergency override — allows everything temporarily
  case policy.emergency_override {
    True -> Allowed(reason: "emergency_override_active")
    False -> check_gate_normal(policy, tool)
  }
}

fn check_gate_normal(
  policy: GuardianPolicy,
  tool: FederatedTool,
) -> GateDecision {
  // Check if tool's layer is auto-allowed
  let layer_override =
    list.any(policy.auto_allow_layers, fn(l) { l == tool.fractal_layer })

  case layer_override {
    True ->
      Allowed(reason: "layer_auto_allowed_L" <> int_to_str(tool.fractal_layer))
    False ->
      case policy.mode {
        Permissive -> Allowed(reason: "permissive_mode")
        AuditOnly ->
          case tool.gate {
            NoGate -> Allowed(reason: "no_gate_required")
            GuardianRequired ->
              AllowedWithAudit(reason: "guardian_required_audit_only")
            ConsensusRequired ->
              AllowedWithAudit(reason: "consensus_required_audit_only")
          }
        EnforceNonL0 ->
          case tool.gate {
            NoGate -> Allowed(reason: "no_gate_required")
            GuardianRequired ->
              case tool.fractal_layer {
                0 -> Allowed(reason: "l0_auto_allowed_enforce_non_l0")
                _ -> Blocked(reason: "guardian_required_enforced")
              }
            ConsensusRequired -> Blocked(reason: "consensus_required_enforced")
          }
        EnforceAll ->
          case tool.gate {
            NoGate -> Allowed(reason: "no_gate_required")
            GuardianRequired -> Blocked(reason: "guardian_required_enforced")
            ConsensusRequired -> Blocked(reason: "consensus_required_enforced")
          }
        Lockdown ->
          // In lockdown, only read-only L3 tools and below with NoGate are allowed
          case tool.gate {
            NoGate ->
              case tool.fractal_layer <= 3 {
                True -> Allowed(reason: "lockdown_readonly_allowed")
                False -> Blocked(reason: "lockdown_l4_plus_blocked")
              }
            _ -> Blocked(reason: "lockdown_all_gated_blocked")
          }
      }
  }
}

fn int_to_str(n: Int) -> String {
  case n {
    0 -> "0"
    1 -> "1"
    2 -> "2"
    3 -> "3"
    4 -> "4"
    5 -> "5"
    6 -> "6"
    7 -> "7"
    _ -> "N"
  }
}

/// Guardian mode to human-readable string.
pub fn guardian_mode_to_string(mode: GuardianMode) -> String {
  case mode {
    Permissive -> "permissive"
    AuditOnly -> "audit_only"
    EnforceNonL0 -> "enforce_non_l0"
    EnforceAll -> "enforce_all"
    Lockdown -> "lockdown"
  }
}

/// Gate decision to human-readable string.
pub fn gate_decision_to_string(decision: GateDecision) -> String {
  case decision {
    Allowed(reason:) -> "ALLOWED: " <> reason
    Blocked(reason:) -> "BLOCKED: " <> reason
    AllowedWithAudit(reason:) -> "ALLOWED_AUDIT: " <> reason
  }
}

/// Check if a gate decision allows execution.
pub fn is_allowed(decision: GateDecision) -> Bool {
  case decision {
    Allowed(_) -> True
    AllowedWithAudit(_) -> True
    Blocked(_) -> False
  }
}

pub type FederatedTool {
  FederatedTool(
    name: String,
    source: ToolSource,
    description: String,
    fractal_layer: Int,
    gate: FractalGate,
  )
}

// =============================================================================
// Pi Tool Registry (14 tools)
// =============================================================================

/// Core Pi file-system and shell tools (7)
fn pi_core_tools() -> List(FederatedTool) {
  [
    FederatedTool(
      name: "bash",
      source: PiTool,
      description: "Execute shell commands in a sandboxed bash environment",
      fractal_layer: 4,
      gate: NoGate,
    ),
    FederatedTool(
      name: "edit",
      source: PiTool,
      description: "Edit file contents with exact string replacement",
      fractal_layer: 3,
      gate: NoGate,
    ),
    FederatedTool(
      name: "read",
      source: PiTool,
      description: "Read file contents from the local filesystem",
      fractal_layer: 3,
      gate: NoGate,
    ),
    FederatedTool(
      name: "write",
      source: PiTool,
      description: "Write or overwrite a file on the local filesystem",
      fractal_layer: 3,
      gate: NoGate,
    ),
    FederatedTool(
      name: "grep",
      source: PiTool,
      description: "Search file contents using ripgrep regex patterns",
      fractal_layer: 3,
      gate: NoGate,
    ),
    FederatedTool(
      name: "find",
      source: PiTool,
      description: "Find files by glob pattern, sorted by modification time",
      fractal_layer: 3,
      gate: NoGate,
    ),
    FederatedTool(
      name: "ls",
      source: PiTool,
      description: "List directory contents",
      fractal_layer: 3,
      gate: NoGate,
    ),
  ]
}

/// Pi internal/utility tools (7)
fn pi_internal_tools() -> List(FederatedTool) {
  [
    FederatedTool(
      name: "edit-diff",
      source: PiTool,
      description: "Show unified diff of a pending edit before applying",
      fractal_layer: 3,
      gate: NoGate,
    ),
    FederatedTool(
      name: "truncate",
      source: PiTool,
      description: "Truncate file to a specified byte length",
      fractal_layer: 3,
      gate: NoGate,
    ),
    FederatedTool(
      name: "render-utils",
      source: PiTool,
      description: "Internal rendering utilities for diagrams and rich output",
      fractal_layer: 2,
      gate: NoGate,
    ),
    FederatedTool(
      name: "path-utils",
      source: PiTool,
      description: "Path normalisation and resolution helpers",
      fractal_layer: 2,
      gate: NoGate,
    ),
    FederatedTool(
      name: "file-mutation-queue",
      source: PiTool,
      description: "Ordered queue of pending file mutations, flushed atomically",
      fractal_layer: 3,
      gate: NoGate,
    ),
    FederatedTool(
      name: "tool-definition-wrapper",
      source: PiTool,
      description: "Wraps external tool schemas into Pi's unified invocation contract",
      fractal_layer: 2,
      gate: NoGate,
    ),
    FederatedTool(
      name: "monitor",
      source: PiTool,
      description: "Stream events from a background process (stdout lines as notifications)",
      fractal_layer: 4,
      gate: NoGate,
    ),
  ]
}

// =============================================================================
// C3I MCP Tool Registry (key 30 of 73)
// =============================================================================

/// Planning tools (5)
fn c3i_planning_tools() -> List(FederatedTool) {
  [
    FederatedTool(
      name: "plan_status",
      source: C3iTool,
      description: "Return current task counts by status from sa-plan-daemon",
      fractal_layer: 3,
      gate: NoGate,
    ),
    FederatedTool(
      name: "plan_list",
      source: C3iTool,
      description: "List all tasks with full detail from Smriti.db",
      fractal_layer: 3,
      gate: NoGate,
    ),
    FederatedTool(
      name: "plan_search",
      source: C3iTool,
      description: "Full-text search tasks using SQLite FTS5",
      fractal_layer: 3,
      gate: NoGate,
    ),
    FederatedTool(
      name: "plan_add",
      source: C3iTool,
      description: "Add a new task with priority via sa-plan-daemon",
      fractal_layer: 3,
      gate: GuardianRequired,
    ),
    FederatedTool(
      name: "plan_update",
      source: C3iTool,
      description: "Update task status (pending/in_progress/completed/blocked)",
      fractal_layer: 3,
      gate: GuardianRequired,
    ),
  ]
}

/// Knowledge tools (2)
fn c3i_knowledge_tools() -> List(FederatedTool) {
  [
    FederatedTool(
      name: "knowledge_search",
      source: C3iTool,
      description: "Search the C3I Zettelkasten (2,600+ holons) by keyword",
      fractal_layer: 3,
      gate: NoGate,
    ),
    FederatedTool(
      name: "knowledge_ingest",
      source: C3iTool,
      description: "Ingest a document into the Zettelkasten knowledge base",
      fractal_layer: 3,
      gate: NoGate,
    ),
  ]
}

/// System observability tools (6)
fn c3i_system_tools() -> List(FederatedTool) {
  [
    FederatedTool(
      name: "system_health",
      source: C3iTool,
      description: "Return aggregate health score and per-container status",
      fractal_layer: 4,
      gate: NoGate,
    ),
    FederatedTool(
      name: "system_dashboard",
      source: C3iTool,
      description: "Return full system dashboard snapshot (health + tasks + zenoh)",
      fractal_layer: 4,
      gate: NoGate,
    ),
    FederatedTool(
      name: "system_immune",
      source: C3iTool,
      description: "Return immune system status — threat level and Psi invariants",
      fractal_layer: 0,
      gate: GuardianRequired,
    ),
    FederatedTool(
      name: "system_zenoh",
      source: C3iTool,
      description: "Return Zenoh mesh connectivity and topic subscriber counts",
      fractal_layer: 6,
      gate: NoGate,
    ),
    FederatedTool(
      name: "system_verification",
      source: C3iTool,
      description: "Run PROMETHEUS formal verification proofs and return results",
      fractal_layer: 0,
      gate: ConsensusRequired,
    ),
    FederatedTool(
      name: "sil6_checklist",
      source: C3iTool,
      description: "Run the IEC 61508 SIL-6 compliance checklist and report gaps",
      fractal_layer: 0,
      gate: GuardianRequired,
    ),
  ]
}

/// Gleam build and quality tools (4)
fn c3i_gleam_tools() -> List(FederatedTool) {
  [
    FederatedTool(
      name: "gleam_build",
      source: C3iTool,
      description: "Run incremental gleam build and return errors/warnings",
      fractal_layer: 4,
      gate: NoGate,
    ),
    FederatedTool(
      name: "gleam_test",
      source: C3iTool,
      description: "Run the full Gleam test suite and return pass/fail counts",
      fractal_layer: 4,
      gate: NoGate,
    ),
    FederatedTool(
      name: "gleam_compute",
      source: C3iTool,
      description: "Execute Gleam NIF compute (graphene, petgraph, kurbo, vega-lite)",
      fractal_layer: 1,
      gate: NoGate,
    ),
    FederatedTool(
      name: "gleam_format_check",
      source: C3iTool,
      description: "Check Gleam source formatting; returns non-compliant file list",
      fractal_layer: 4,
      gate: NoGate,
    ),
  ]
}

/// Code analysis and audit tools (4)
fn c3i_analysis_tools() -> List(FederatedTool) {
  [
    FederatedTool(
      name: "graph_analyze",
      source: C3iTool,
      description: "Run graphene SCC / PageRank analysis on the navigation graph",
      fractal_layer: 1,
      gate: NoGate,
    ),
    FederatedTool(
      name: "muda_check",
      source: C3iTool,
      description: "Audit codebase for Muda waste (dead code, warnings, large files)",
      fractal_layer: 3,
      gate: NoGate,
    ),
    FederatedTool(
      name: "pre_commit_audit",
      source: C3iTool,
      description: "Run pre-commit quality gates (build, format, credo, tests)",
      fractal_layer: 4,
      gate: NoGate,
    ),
    FederatedTool(
      name: "render_diagrams",
      source: C3iTool,
      description: "Render architecture diagrams via Skia/Mermaid NIF to PNG/SVG",
      fractal_layer: 2,
      gate: NoGate,
    ),
  ]
}

/// Infrastructure and operations tools (5)
fn c3i_ops_tools() -> List(FederatedTool) {
  [
    FederatedTool(
      name: "send_email",
      source: C3iTool,
      description: "Send email via SMTP through sa-plan-daemon (with attachment support)",
      fractal_layer: 7,
      gate: NoGate,
    ),
    FederatedTool(
      name: "server_restart",
      source: C3iTool,
      description: "Restart the Gleam BEAM server (required after NIF changes)",
      fractal_layer: 4,
      gate: GuardianRequired,
    ),
    FederatedTool(
      name: "session_resume",
      source: C3iTool,
      description: "Resume a prior session by replaying memory + ZK context",
      fractal_layer: 5,
      gate: NoGate,
    ),
    FederatedTool(
      name: "auto_evolve",
      source: C3iTool,
      description: "Trigger an autonomous OODA evolution cycle for a named feature",
      fractal_layer: 7,
      gate: GuardianRequired,
    ),
    FederatedTool(
      name: "git_status",
      source: C3iTool,
      description: "Return git status, diff summary, and recent commit log",
      fractal_layer: 3,
      gate: NoGate,
    ),
  ]
}

/// UI and agent interaction tools (4)
fn c3i_ui_tools() -> List(FederatedTool) {
  [
    FederatedTool(
      name: "file_context",
      source: C3iTool,
      description: "Return compressed file context for a path (LOC, exports, types)",
      fractal_layer: 3,
      gate: NoGate,
    ),
    FederatedTool(
      name: "gemma_chat",
      source: C3iTool,
      description: "Query local Gemma 3/4 model for AI advisory (Gemma 3 → Gemma 4 fallback)",
      fractal_layer: 5,
      gate: NoGate,
    ),
    FederatedTool(
      name: "page_dom_check",
      source: C3iTool,
      description: "Fetch a Lustre page and verify DOM element count and structure",
      fractal_layer: 5,
      gate: NoGate,
    ),
    FederatedTool(
      name: "api_health_check",
      source: C3iTool,
      description: "Call /health and all major API endpoints; report non-200 responses",
      fractal_layer: 4,
      gate: NoGate,
    ),
  ]
}

// =============================================================================
// Public Registry Functions
// =============================================================================

/// Returns all 14 Pi tools
pub fn pi_tools() -> List(FederatedTool) {
  list.append(pi_core_tools(), pi_internal_tools())
}

/// Returns the key 30 C3I MCP tools (representative subset of 73)
pub fn c3i_tools() -> List(FederatedTool) {
  list.flatten([
    c3i_planning_tools(),
    c3i_knowledge_tools(),
    c3i_system_tools(),
    c3i_gleam_tools(),
    c3i_analysis_tools(),
    c3i_ops_tools(),
    c3i_ui_tools(),
  ])
}

/// Returns the full federated registry of 87 tools (14 Pi + 73 C3I)
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">Pi 14 + C3I 73 ↪ unified List(FederatedTool)</morphism>
///   <formal-proof>
///     <P> Pre-condition: both sub-registries are populated. </P>
///     <C> all_federated_tools() </C>
///     <Q> Post-condition: returns list of length 87, never empty, never panics. </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn all_federated_tools() -> List(FederatedTool) {
  list.append(pi_tools(), c3i_tools())
}

/// Returns total tool count — MUST equal 87
pub fn tool_count() -> Int {
  list.length(all_federated_tools())
}

/// Filter tools by fractal layer (L0-L7)
///
/// SC-PI-002: L0 tools are Guardian-gated; this function enables
/// callers to enumerate tools at any specific fractal layer.
pub fn tools_by_layer(layer: Int) -> List(FederatedTool) {
  list.filter(all_federated_tools(), fn(t) { t.fractal_layer == layer })
}

/// Returns all tools requiring Guardian pre-approval (SC-PI-002, SC-SAFETY-001)
///
/// These MUST NOT be dispatched without a valid Guardian token.
pub fn tools_requiring_guardian() -> List(FederatedTool) {
  list.filter(all_federated_tools(), fn(t) { t.gate == GuardianRequired })
}

/// Returns all tools requiring 2oo3 consensus (SC-SIL4-006)
pub fn tools_requiring_consensus() -> List(FederatedTool) {
  list.filter(all_federated_tools(), fn(t) { t.gate == ConsensusRequired })
}

/// Returns all tools that can be dispatched without a gate
pub fn ungated_tools() -> List(FederatedTool) {
  list.filter(all_federated_tools(), fn(t) { t.gate == NoGate })
}

/// Returns all Pi-sourced tools
pub fn pi_sourced() -> List(FederatedTool) {
  list.filter(all_federated_tools(), fn(t) { t.source == PiTool })
}

/// Returns all C3I-sourced tools
pub fn c3i_sourced() -> List(FederatedTool) {
  list.filter(all_federated_tools(), fn(t) { t.source == C3iTool })
}
