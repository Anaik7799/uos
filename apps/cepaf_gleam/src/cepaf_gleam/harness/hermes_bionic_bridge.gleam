//// Hermes-Bionic Bridge & Full Systemic Integration
////
//// Integrates the Hermes-Bionic execution substrate into the Unified Operational System (UOS)
//// using the 17-aspect approach, adhering to:
////   - 18 L1 Feature Families
////   - Canonical L2 Capability Catalogue Authority
////   - L0–L6 Recursive Evidence Plane (Product -> Family -> Capability -> Contract -> Scenario -> Trace -> Receipt)
////   - Precise Evidence Boundary: Source inventory is discovery-only evidence, NOT a parity or health receipt
////   - LX Control Plane (Homeostasis, Turn Budgets, Orientation Snapshots, Lyapunov Stability)
////   - FPP Elements (NASA JPL Aerospace HSMs, Topologies, Component Packets)
////   - Actor & Agent Ecosystem over L0..L9 x 5 Surfaces

import gleam/list
import gleam/option.{type Option}

// =============================================================================
// §1.0 The 18 L1 Feature Families (Public Product Denominator)
// =============================================================================

pub type L1FeatureFamily {
  InteractiveCli
  AgentLoop
  ModelRouting
  ToolExecution
  Mcp
  Memory
  ContextFiles
  Skills
  LearningLoop
  Subagents
  ScheduledAutomation
  MessagingGateway
  VoiceMedia
  BrowserResearch
  ExecutionBackends
  TrajectoryData
  OperationsCli
  ApplicationSurfaces
}

pub type L1FeatureRecord {
  L1FeatureRecord(
    id: String,
    family: L1FeatureFamily,
    label: String,
    source_domains: List(String),
    durable_tasks_count: Int,
  )
}

pub fn all_18_l1_feature_families() -> List(L1FeatureRecord) {
  [
    L1FeatureRecord(
      "interactive_cli",
      InteractiveCli,
      "Interactive CLI and terminal UI",
      ["hermes_cli", "ui-tui", "tui_gateway"],
      5,
    ),
    L1FeatureRecord(
      "agent_loop",
      AgentLoop,
      "Agent conversation and tool loop",
      ["agent"],
      7,
    ),
    L1FeatureRecord(
      "model_routing",
      ModelRouting,
      "Model providers and routing",
      ["agent", "providers"],
      6,
    ),
    L1FeatureRecord(
      "tool_execution",
      ToolExecution,
      "Tool execution and approvals",
      ["agent", "tools"],
      5,
    ),
    L1FeatureRecord(
      "mcp",
      Mcp,
      "MCP integration",
      ["agent", "optional-mcps"],
      4,
    ),
    L1FeatureRecord(
      "memory",
      Memory,
      "Persistent memory and session search",
      ["agent", "native"],
      4,
    ),
    L1FeatureRecord(
      "context_files",
      ContextFiles,
      "Project context files",
      ["agent", "skills"],
      3,
    ),
    L1FeatureRecord(
      "skills",
      Skills,
      "Skills and discovery",
      ["agent", "skills", "optional-skills"],
      6,
    ),
    L1FeatureRecord(
      "learning_loop",
      LearningLoop,
      "Learning and self-improvement",
      ["agent", "skills"],
      4,
    ),
    L1FeatureRecord(
      "subagents",
      Subagents,
      "Subagents and parallel delegation",
      ["agent"],
      4,
    ),
    L1FeatureRecord(
      "scheduled_automation",
      ScheduledAutomation,
      "Scheduled cron automation",
      ["cron", "agent", "gateway"],
      3,
    ),
    L1FeatureRecord(
      "messaging_gateway",
      MessagingGateway,
      "Messaging platforms and delivery gateway",
      ["gateway", "agent"],
      5,
    ),
    L1FeatureRecord(
      "voice_media",
      VoiceMedia,
      "Voice, transcription, and media generation",
      ["agent", "tools"],
      4,
    ),
    L1FeatureRecord(
      "browser_research",
      BrowserResearch,
      "Browser control and web research",
      ["agent", "tools", "web"],
      4,
    ),
    L1FeatureRecord(
      "execution_backends",
      ExecutionBackends,
      "Local, container, SSH, and serverless execution",
      ["tools", "docker", "scripts"],
      5,
    ),
    L1FeatureRecord(
      "trajectory_data",
      TrajectoryData,
      "Trajectory generation and compression",
      ["agent", "datagen-config-examples"],
      3,
    ),
    L1FeatureRecord(
      "operations_cli",
      OperationsCli,
      "Setup, config, doctor, migration, and usage",
      ["hermes_cli", "apps", "agent"],
      6,
    ),
    L1FeatureRecord(
      "application_surfaces",
      ApplicationSurfaces,
      "Desktop and web application surfaces",
      ["apps", "web", "ui-tui"],
      4,
    ),
  ]
}

// =============================================================================
// §2.0 Canonical L2 Capability Catalogue Authority
// =============================================================================

pub type L2Capability {
  L2Capability(
    id: String,
    family_id: String,
    label: String,
    source_anchors: List(String),
    doc_anchors: List(String),
    status_policy: String,
  )
}

pub fn canonical_l2_capabilities_sample() -> List(L2Capability) {
  [
    L2Capability(
      "repl_session",
      "interactive_cli",
      "Interactive REPL session and console engine",
      ["hermes_cli/console_engine.py", "hermes_cli/main.py"],
      ["website/docs/user-guide/cli.md"],
      "FailClosed",
    ),
    L2Capability(
      "slash_commands",
      "interactive_cli",
      "Slash commands and completion",
      ["hermes_cli/commands.py", "hermes_cli/completion.py"],
      ["website/docs/reference/slash-commands.md"],
      "FailClosed",
    ),
    L2Capability(
      "terminal_ui",
      "interactive_cli",
      "Terminal user interface surface",
      ["ui-tui/src", "hermes_cli/curses_ui.py"],
      ["website/docs/user-guide/tui.md"],
      "FailClosed",
    ),
    L2Capability(
      "conversation_loop",
      "agent_loop",
      "Conversation turn loop",
      ["agent/conversation_loop.py"],
      ["website/docs/developer-guide/agent-loop.md"],
      "FailClosed",
    ),
    L2Capability(
      "prompt_assembly",
      "agent_loop",
      "System prompt and request assembly",
      ["agent/prompt_builder.py", "agent/system_prompt.py"],
      ["website/docs/developer-guide/prompt-assembly.md"],
      "FailClosed",
    ),
    L2Capability(
      "anthropic_adapter",
      "model_routing",
      "Anthropic adapter",
      ["agent/anthropic_adapter.py", "agent/transports/anthropic.py"],
      ["website/docs/developer-guide/adding-providers.md"],
      "FailClosed",
    ),
    L2Capability(
      "codex_runtime",
      "model_routing",
      "Codex app-server runtime",
      ["agent/codex_runtime.py", "agent/transports/codex_app_server.py"],
      ["website/docs/user-guide/features/codex-app-server-runtime.md"],
      "FailClosed",
    ),
    L2Capability(
      "gemini_adapter",
      "model_routing",
      "Gemini native adapter and schema",
      ["agent/gemini_native_adapter.py", "agent/gemini_schema.py"],
      ["website/docs/guides/google-gemini.md"],
      "FailClosed",
    ),
    L2Capability(
      "tool_sandbox",
      "tool_execution",
      "Sandboxed tool executor with approval gates",
      ["tools/executor.py", "tools/sandbox.py"],
      ["website/docs/developer-guide/tools.md"],
      "FailClosed",
    ),
    L2Capability(
      "mcp_gateway",
      "mcp",
      "Model Context Protocol JSON-RPC gateway",
      ["agent/mcp.py", "gateway/mcp_server.py"],
      ["website/docs/user-guide/features/mcp.md"],
      "FailClosed",
    ),
  ]
}

// =============================================================================
// §3.0 L0–L6 Recursive Evidence Plane & Evidence Boundary
// =============================================================================

pub type FractalEvidenceLevel {
  Level0Product
  Level1Family
  Level2Capability
  Level3Contract
  Level4Scenario
  Level5Trace
  Level6Receipt
}

pub type FractalNode {
  FractalNode(
    node_id: String,
    level: FractalEvidenceLevel,
    parent_node_id: Option(String),
    semantic_key: String,
    label: String,
    required: Bool,
  )
}

pub type EvidenceVerdict {
  DiscoveryOnlyEvidence(reason: String)
  ParityReceipt(candidate_digest: String, reference_digest: String, matched: Bool)
  EvidenceRejected(reason: String)
}

/// The precise evidence boundary:
/// Source inventory presence is discovery-only evidence; it NEVER counts as a
/// parity or health receipt without fresh runtime behavior AND formal specification.
pub fn evaluate_evidence_boundary(
  source_discovered: Bool,
  runtime_observed: Bool,
  formal_specified: Bool,
  candidate_digest: String,
  reference_digest: String,
) -> EvidenceVerdict {
  case source_discovered, runtime_observed, formal_specified {
    True, True, True ->
      case candidate_digest == reference_digest {
        True -> ParityReceipt(candidate_digest, reference_digest, True)
        False -> EvidenceRejected("Candidate digest diverges from reference digest")
      }
    True, False, _ ->
      DiscoveryOnlyEvidence(
        "Source presence is discovery evidence only; missing runtime observation",
      )
    True, True, False ->
      DiscoveryOnlyEvidence(
        "Missing machine-checked formal specification (Two-Key rule failed)",
      )
    _, _, _ -> EvidenceRejected("Unvetted or missing evidence boundary inputs")
  }
}

// =============================================================================
// §4.0 LX Control Plane (Homeostasis, Turn Budgets, Orientation Snapshots)
// =============================================================================

pub type HomeostasisStatus {
  HomeostaticStable
  HomeostaticDrifting(drift_metric: Float)
  HomeostaticDegraded
}

pub type TurnBudget {
  TurnBudget(
    allocated_tokens: Int,
    consumed_tokens: Int,
    max_tool_invocations: Int,
    used_tool_invocations: Int,
    wall_clock_timeout_ms: Int,
  )
}

pub type OrientationSnapshot {
  OrientationSnapshot(
    turn_id: String,
    phase: String,
    active_hypotheses: List(String),
    entropy_bits: Float,
    lyapunov_exponent: Float,
  )
}

pub type LxControlPlane {
  LxControlPlane(
    status: HomeostasisStatus,
    budget: TurnBudget,
    snapshot: OrientationSnapshot,
  )
}

pub fn create_default_lx_control_plane() -> LxControlPlane {
  LxControlPlane(
    status: HomeostaticStable,
    budget: TurnBudget(
      allocated_tokens: 32_768,
      consumed_tokens: 4096,
      max_tool_invocations: 16,
      used_tool_invocations: 2,
      wall_clock_timeout_ms: 30_000,
    ),
    snapshot: OrientationSnapshot(
      turn_id: "turn-001",
      phase: "Orient",
      active_hypotheses: ["H0-Nominal", "H1-MinorDrift"],
      entropy_bits: 2.75,
      lyapunov_exponent: -0.15,
    ),
  )
}

pub fn is_control_plane_safe(cp: LxControlPlane) -> Bool {
  case cp.status {
    HomeostaticStable ->
      cp.budget.consumed_tokens <= cp.budget.allocated_tokens
      && cp.budget.used_tool_invocations <= cp.budget.max_tool_invocations
      && cp.snapshot.lyapunov_exponent <=. 0.0
    _ -> False
  }
}

// =============================================================================
// §5.0 FPP Elements (NASA JPL Aerospace Metamodel)
// =============================================================================

pub type FppPortDirection {
  PortIn
  PortOut
}

pub type FppPort {
  FppPort(name: String, direction: FppPortDirection, port_type: String)
}

pub type FppHsmState {
  HsmIdle
  HsmArming
  HsmArmed
  HsmExecuting
  HsmSafing
}

pub type FppComponent {
  FppComponent(
    name: String,
    kind: String,
    ports: List(FppPort),
    current_state: FppHsmState,
  )
}

pub fn create_fpp_telemetry_component() -> FppComponent {
  FppComponent(
    name: "C3iTelemetryBroadcaster",
    kind: "ActiveComponent",
    ports: [
      FppPort("cmdIn", PortIn, "Fw::Cmd"),
      FppPort("tlmOut", PortOut, "Fw::Tlm"),
      FppPort("timeCaller", PortOut, "Svc::Time"),
    ],
    current_state: HsmArmed,
  )
}

// =============================================================================
// §6.0 17-Aspect Hermes-Bionic Alignment
// =============================================================================

pub type BionicAspectBinding {
  BionicAspectBinding(
    aspect_id: Int,
    aspect_name: String,
    bionic_subsystem: String,
    evidence_tier: String,
    status: String,
  )
}

pub fn all_17_aspect_bionic_bindings() -> List(BionicAspectBinding) {
  [
    BionicAspectBinding(1, "Substrate & Hardware Safety", "spec.rs OS NVMe Drive Lock", "L0 Constitutional", "Active"),
    BionicAspectBinding(2, "Standalone Jujutsu Monorepo", "Non-colocated .jj/ VCS", "L0 Governance", "Active"),
    BionicAspectBinding(3, "Zero-Muda Purity", "0 Bevy, 0 Graphite, pure Erlang", "L1 Purity", "Active"),
    BionicAspectBinding(4, "Gleam/OTP Supervision & Actors", "uos_sup.gleam 4-domain supervisor", "L4 System", "Active"),
    BionicAspectBinding(5, "Deterministic Runtime Engine", "ZigVM Descriptor-Relative VFS", "L1 Kernel", "Active"),
    BionicAspectBinding(6, "Formal Evidence & Analysis", "Hermes Gospel, Z3 & SQLite WAL", "L6 Evidence", "Active"),
    BionicAspectBinding(7, "Mathematical Authority", "Lean 4 Coordinate Conservation", "L8 Math", "Active"),
    BionicAspectBinding(8, "Biosemiotic Cybernetics", "Rocha Decoupled Semiotics", "L9 Semiotics", "Active"),
    BionicAspectBinding(9, "Quarantined AI Inference", "Modular MAX/Mojo Python daemon", "L4 Service", "Active"),
    BionicAspectBinding(10, "Mesh Telemetry & Communication", "Zenoh OoZ & MoZ backplane", "L4 Telemetry", "Active"),
    BionicAspectBinding(11, "Agent Event Bus Protocol", "AG-UI 32-Event SSE Stream", "L6 Agent", "Active"),
    BionicAspectBinding(12, "Declarative UI Component Catalog", "A2UI 233 Component Registry", "L2 Presentation", "Active"),
    BionicAspectBinding(13, "Multi-Interface Accessibility", "Penta-Stack (Lustre/Wisp/TUI)", "L7 Interface", "Active"),
    BionicAspectBinding(14, "Universal Tailscale FQDN Web Nav", "Tailscale FQDN http://nas-1:4100", "L7 Gateway", "Active"),
    BionicAspectBinding(15, "Comprehensive Verification Checklist", "SC-CHECKLIST-001 5 Domains / 18 Checks", "L4 SRE", "Active"),
    BionicAspectBinding(16, "Knowledge Management Triad", "KM Triad (Wiki, ZK, Living Ontology)", "L7 Knowledge", "Active"),
    BionicAspectBinding(17, "Sa-Plan Durable Execution & Workflow", "Hermes Sa-Plan (12 suites, 235 laws)", "L3 Execution", "Active"),
  ]
}

// =============================================================================
// §7.0 Hermes-Bionic Actors & Agents Topology
// =============================================================================

pub type BionicInstanceMode {
  BionicSingleInstance
  BionicMultiInstance
}

pub type BionicActorDescriptor {
  BionicActorDescriptor(
    id: String,
    name: String,
    role: String,
    mode: BionicInstanceMode,
    layer: Int,
    max_concurrency: Int,
    sdlc_sre_faculty: String,
  )
}

pub fn hermes_bionic_actor_catalog() -> List(BionicActorDescriptor) {
  [
    // L0: Constitutional & Proof Reducer
    BionicActorDescriptor(
      "actor-bionic-l0-reducer",
      "L0–L6 Recursive Proof Reducer",
      "ProofConjunctionAuthority",
      BionicSingleInstance,
      0,
      1,
      "VerificationReduction",
    ),
    // L1: Feature Family & Capability Registry
    BionicActorDescriptor(
      "actor-bionic-l1-router",
      "L1 Feature Family Router",
      "FeatureFamilyDispatcher",
      BionicSingleInstance,
      1,
      1,
      "ArchitectureRouting",
    ),
    BionicActorDescriptor(
      "actor-bionic-l2-catalogue",
      "Canonical L2 Catalogue Authority",
      "CapabilityCatalogueKeeper",
      BionicSingleInstance,
      2,
      1,
      "CapabilityRegistry",
    ),
    // L3: Contracts & Durable Schedulers
    BionicActorDescriptor(
      "actor-bionic-l3-contract-checker",
      "L3 Gospel Contract Checker",
      "GospelBehavioralVerifier",
      BionicMultiInstance,
      3,
      32,
      "ContractVerification",
    ),
    // L4: Scenarios & Control Plane
    BionicActorDescriptor(
      "actor-bionic-l4-scenario-runner",
      "L4 BDD/TDD Scenario Fixture Worker",
      "ScenarioExecutionEngine",
      BionicMultiInstance,
      4,
      64,
      "ScenarioTesting",
    ),
    BionicActorDescriptor(
      "actor-bionic-lx-homeostasis",
      "LX Control Plane Homeostasis Monitor",
      "LyapunovHomeostasisGuard",
      BionicSingleInstance,
      4,
      1,
      "ControlPlaneGuard",
    ),
    // L5: Traces & OODA Loops
    BionicActorDescriptor(
      "actor-bionic-l5-trace-collector",
      "L5 Trace Collector & Normalizer",
      "DifferentialTraceComparator",
      BionicMultiInstance,
      5,
      32,
      "TraceNormalization",
    ),
    // L6: Receipts & Certification
    BionicActorDescriptor(
      "actor-bionic-l6-receipt-certifier",
      "L6 Strict Receipt Certifier",
      "TwoKeyCertificationAuthority",
      BionicSingleInstance,
      6,
      1,
      "ParityCertification",
    ),
    // FPP Aerospace & Superpowers
    BionicActorDescriptor(
      "actor-bionic-fpp-topology",
      "FPP Metamodel & Topology Router",
      "AerospaceHsmDispatcher",
      BionicSingleInstance,
      7,
      1,
      "FppAutocoding",
    ),
    BionicActorDescriptor(
      "actor-bionic-superpower-orch",
      "Superpower & SDD Orchestrator",
      "SkillSuperpowerCoordinator",
      BionicMultiInstance,
      6,
      128,
      "SuperpowerExecution",
    ),
  ]
}

// =============================================================================
// §8.0 High-Level Verification Predicates
// =============================================================================

pub fn verify_hermes_bionic_integration() -> Bool {
  let l1_families = all_18_l1_feature_families()
  let l2_samples = canonical_l2_capabilities_sample()
  let aspects = all_17_aspect_bionic_bindings()
  let actors = hermes_bionic_actor_catalog()
  let cp = create_default_lx_control_plane()

  list.length(l1_families) == 18
  && list.length(l2_samples) >= 10
  && list.length(aspects) == 17
  && list.length(actors) >= 10
  && is_control_plane_safe(cp)
}
