//// =============================================================================
//// [C3I-SIL6-MSTS] UOS Agentic Ecology & 17 System Aspects (SC-AGENT-CAPABILITY-001)
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/harness/agent_ecology</module>
////     <authority>UOS-CANONICAL-AGENT-POLICY</authority>
////   </identity>
////   <fractal-topology>
////     <layer>L6_ECOSYSTEM</layer>
////     <topology>Rich Agent Profiles, 17 System Aspects and Capability Semilattices</topology>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-SYSTEM-ASPECTS-001, SC-AGENT-CAPABILITY-001, SC-JIDOKA-001, SC-MUDA-001</stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================

import gleam/int
import gleam/list
import gleam/string

pub const andon_halt_unauthorized_code: Int = -32_002
pub const andon_halt_quorum_missing_code: Int = -32_003

pub type SystemAspect {
  A01SubstrateHardwareSafety
  A02VersionControlDiscipline
  A03ZeroMudaPurity
  A04SupervisionActorHierarchy
  A05DeterministicRuntimeEngine
  A06FormalEvidenceAnalysis
  A07MathematicalAuthority
  A08FeedbackSemioticsHomeostasis
  A09QuarantinedAIInference
  A10MeshTelemetryObservability
  A11AgentEventBusProtocol
  A12DeclarativeUIComponentCatalog
  A13MultiInterfaceAccessibility
  A14UniversalTailscaleWebNavigation
  A15ComprehensiveVerificationChecklist
  A16KnowledgeManagementTriad
  A17DurableExecutionWorkflow
}

pub type FractalLayer {
  L0Constitutional
  L1Atomic
  L2ComponentState
  L3TransactionHistory
  L4SystemRuntime
  L5CognitiveReasoning
  L6SwarmEcosystem
  L7FederationEgress
  L8LivingKnowledge
  L9SREHomeostasis
}

pub type CapabilityKind {
  ReadOnly
  StateMutating
  HardwareInterlock
  QuorumMutating
  SovereignAdvisory
}

pub type Capability {
  Capability(
    id: String,
    name: String,
    kind: CapabilityKind,
    aspect: SystemAspect,
    layer: FractalLayer,
    max_budget_bytes: Int,
  )
}

pub type AgentKind {
  Singleton
  ElasticSwarm
  EphemeralHolon
}

pub type AgentProfile {
  AgentProfile(
    id: String,
    name: String,
    kind: AgentKind,
    layer: FractalLayer,
    aspects: List(SystemAspect),
    capabilities: List(Capability),
    tool_allowlist: List(String),
    requires_2oo3: Bool,
    max_token_budget: Int,
    sla_latency_ms: Int,
  )
}

/// Enumerates all 17 canonical System Aspects in UOS.
pub fn all_system_aspects() -> List(SystemAspect) {
  [
    A01SubstrateHardwareSafety,
    A02VersionControlDiscipline,
    A03ZeroMudaPurity,
    A04SupervisionActorHierarchy,
    A05DeterministicRuntimeEngine,
    A06FormalEvidenceAnalysis,
    A07MathematicalAuthority,
    A08FeedbackSemioticsHomeostasis,
    A09QuarantinedAIInference,
    A10MeshTelemetryObservability,
    A11AgentEventBusProtocol,
    A12DeclarativeUIComponentCatalog,
    A13MultiInterfaceAccessibility,
    A14UniversalTailscaleWebNavigation,
    A15ComprehensiveVerificationChecklist,
    A16KnowledgeManagementTriad,
    A17DurableExecutionWorkflow,
  ]
}

/// Convert SystemAspect to its canonical alphanumeric code.
pub fn aspect_to_code(aspect: SystemAspect) -> String {
  case aspect {
    A01SubstrateHardwareSafety -> "A01"
    A02VersionControlDiscipline -> "A02"
    A03ZeroMudaPurity -> "A03"
    A04SupervisionActorHierarchy -> "A04"
    A05DeterministicRuntimeEngine -> "A05"
    A06FormalEvidenceAnalysis -> "A06"
    A07MathematicalAuthority -> "A07"
    A08FeedbackSemioticsHomeostasis -> "A08"
    A09QuarantinedAIInference -> "A09"
    A10MeshTelemetryObservability -> "A10"
    A11AgentEventBusProtocol -> "A11"
    A12DeclarativeUIComponentCatalog -> "A12"
    A13MultiInterfaceAccessibility -> "A13"
    A14UniversalTailscaleWebNavigation -> "A14"
    A15ComprehensiveVerificationChecklist -> "A15"
    A16KnowledgeManagementTriad -> "A16"
    A17DurableExecutionWorkflow -> "A17"
  }
}

/// Parse SystemAspect from its canonical alphanumeric code.
pub fn aspect_from_code(code: String) -> Result(SystemAspect, Nil) {
  case code {
    "A01" -> Ok(A01SubstrateHardwareSafety)
    "A02" -> Ok(A02VersionControlDiscipline)
    "A03" -> Ok(A03ZeroMudaPurity)
    "A04" -> Ok(A04SupervisionActorHierarchy)
    "A05" -> Ok(A05DeterministicRuntimeEngine)
    "A06" -> Ok(A06FormalEvidenceAnalysis)
    "A07" -> Ok(A07MathematicalAuthority)
    "A08" -> Ok(A08FeedbackSemioticsHomeostasis)
    "A09" -> Ok(A09QuarantinedAIInference)
    "A10" -> Ok(A10MeshTelemetryObservability)
    "A11" -> Ok(A11AgentEventBusProtocol)
    "A12" -> Ok(A12DeclarativeUIComponentCatalog)
    "A13" -> Ok(A13MultiInterfaceAccessibility)
    "A14" -> Ok(A14UniversalTailscaleWebNavigation)
    "A15" -> Ok(A15ComprehensiveVerificationChecklist)
    "A16" -> Ok(A16KnowledgeManagementTriad)
    "A17" -> Ok(A17DurableExecutionWorkflow)
    _ -> Error(Nil)
  }
}

/// Returns the 7 canonical Agent Profiles equipped with rich capabilities.
pub fn all_agent_profiles() -> List(AgentProfile) {
  [
    agy_sovereign_coordinator_profile(),
    sre_homeostasis_overseer_profile(),
    security_hardware_guardian_profile(),
    multimodal_edge_ingestor_profile(),
    formal_verifier_oracle_profile(),
    knowledge_sheaf_curator_profile(),
    quarantined_inference_worker_profile(),
  ]
}

/// Retrieve a specific AgentProfile by its unique identifier or alias.
pub fn get_agent_profile(agent_id: String) -> Result(AgentProfile, String) {
  let normalized = string.lowercase(string.trim(agent_id))
  let target_id = case normalized {
    "agy" | "antigravity" | "coordinator" -> "agy_sovereign_coordinator"
    "sre" | "homeostasis" | "overseer" -> "sre_homeostasis_overseer"
    "security" | "guardian" | "hardware" -> "security_hardware_guardian"
    "edge" | "multimodal" | "ingestor" | "razr" | "razr-1" | "holon-razr15-1" ->
      "multimodal_edge_ingestor"
    "formal" | "verifier" | "oracle" -> "formal_verifier_oracle"
    "knowledge" | "sheaf" | "curator" | "zk" | "wiki" -> "knowledge_sheaf_curator"
    "inference" | "quarantined" | "max" | "mojo" ->
      "quarantined_inference_worker"
    _ -> string.trim(agent_id)
  }
  let matches =
    list.filter(all_agent_profiles(), fn(profile) { profile.id == target_id })
  case matches {
    [profile, ..] -> Ok(profile)
    [] -> Error("Agent profile not found: " <> agent_id)
  }
}

/// Tests whether an agent profile grants a given capability.
pub fn can_execute_capability(profile: AgentProfile, cap_id: String) -> Bool {
  list.any(profile.capabilities, fn(cap) { cap.id == cap_id })
}

/// Tests whether a tool invocation is allowed under an agent's tool allowlist.
pub fn can_invoke_tool(profile: AgentProfile, tool_name: String) -> Bool {
  list.contains(profile.tool_allowlist, tool_name)
}

/// Evaluates an agent's intent to execute a tool under Sa-Plan lease & 2oo3 quorum constraints.
pub fn evaluate_agent_intent(
  profile: AgentProfile,
  tool_name: String,
  has_valid_lease: Bool,
  quorum_count: Int,
) -> Result(String, Int) {
  // Check 1: Tool allowlist
  case can_invoke_tool(profile, tool_name) {
    False -> Error(andon_halt_unauthorized_code)
    True -> {
      // Check 2: Active Sa-plan lease
      case has_valid_lease {
        False -> Error(andon_halt_unauthorized_code)
        True -> {
          // Check 3: 2oo3 constitutional quorum if required
          case profile.requires_2oo3 && quorum_count < 2 {
            True -> Error(andon_halt_quorum_missing_code)
            False -> Ok("PERMITTED")
          }
        }
      }
    }
  }
}

/// Checks completeness of the 17 System Aspects coverage.
pub fn validate_aspect_completeness(aspects: List(SystemAspect)) -> Bool {
  let all = all_system_aspects()
  list.all(all, fn(expected) { list.contains(aspects, expected) })
}

// -----------------------------------------------------------------------------
// Canonical Profile Constructors
// -----------------------------------------------------------------------------

pub fn agy_sovereign_coordinator_profile() -> AgentProfile {
  AgentProfile(
    id: "agy_sovereign_coordinator",
    name: "AGY Sovereign Coordinator",
    kind: Singleton,
    layer: L6SwarmEcosystem,
    aspects: [
      A04SupervisionActorHierarchy,
      A11AgentEventBusProtocol,
      A13MultiInterfaceAccessibility,
      A17DurableExecutionWorkflow,
    ],
    capabilities: [
      Capability(
        id: "swarm_orchestration",
        name: "Swarm Orchestration",
        kind: SovereignAdvisory,
        aspect: A04SupervisionActorHierarchy,
        layer: L6SwarmEcosystem,
        max_budget_bytes: 8192,
      ),
      Capability(
        id: "tri_sovereign_consensus",
        name: "Tri-Sovereign Consensus",
        kind: SovereignAdvisory,
        aspect: A04SupervisionActorHierarchy,
        layer: L6SwarmEcosystem,
        max_budget_bytes: 8192,
      ),
      Capability(
        id: "agui_stream_publishing",
        name: "AG-UI Stream Publishing",
        kind: ReadOnly,
        aspect: A11AgentEventBusProtocol,
        layer: L5CognitiveReasoning,
        max_budget_bytes: 4096,
      ),
      Capability(
        id: "sa_plan_dispatch",
        name: "Sa-Plan Dispatch",
        kind: StateMutating,
        aspect: A17DurableExecutionWorkflow,
        layer: L3TransactionHistory,
        max_budget_bytes: 8192,
      ),
    ],
    tool_allowlist: [
      "plan_status",
      "plan_get",
      "plan_add",
      "plan_update",
      "agui_emit",
      "system_health",
      "system_dashboard",
    ],
    requires_2oo3: False,
    max_token_budget: 8192,
    sla_latency_ms: 5,
  )
}

pub fn sre_homeostasis_overseer_profile() -> AgentProfile {
  AgentProfile(
    id: "sre_homeostasis_overseer",
    name: "SRE Homeostasis Overseer",
    kind: Singleton,
    layer: L9SREHomeostasis,
    aspects: [
      A01SubstrateHardwareSafety,
      A08FeedbackSemioticsHomeostasis,
      A15ComprehensiveVerificationChecklist,
    ],
    capabilities: [
      Capability(
        id: "lyapunov_trend_detection",
        name: "Lyapunov Trend Detection",
        kind: ReadOnly,
        aspect: A08FeedbackSemioticsHomeostasis,
        layer: L9SREHomeostasis,
        max_budget_bytes: 4096,
      ),
      Capability(
        id: "prajna_circuit_breaker_control",
        name: "Prajna Circuit Breaker Control",
        kind: QuorumMutating,
        aspect: A08FeedbackSemioticsHomeostasis,
        layer: L9SREHomeostasis,
        max_budget_bytes: 2048,
      ),
      Capability(
        id: "dark_cockpit_failsafe",
        name: "Dark Cockpit Fail-Safe",
        kind: QuorumMutating,
        aspect: A08FeedbackSemioticsHomeostasis,
        layer: L9SREHomeostasis,
        max_budget_bytes: 2048,
      ),
    ],
    tool_allowlist: [
      "prajna_health",
      "system_immune",
      "dark_cockpit_mode",
      "integrity_check",
      "evolution_metrics",
    ],
    requires_2oo3: True,
    max_token_budget: 4096,
    sla_latency_ms: 10,
  )
}

pub fn security_hardware_guardian_profile() -> AgentProfile {
  AgentProfile(
    id: "security_hardware_guardian",
    name: "Security & Hardware Enclave Guardian",
    kind: Singleton,
    layer: L0Constitutional,
    aspects: [
      A01SubstrateHardwareSafety,
      A03ZeroMudaPurity,
      A08FeedbackSemioticsHomeostasis,
    ],
    capabilities: [
      Capability(
        id: "drive_serial_enclave_lock",
        name: "Drive Serial Enclave Lock",
        kind: HardwareInterlock,
        aspect: A01SubstrateHardwareSafety,
        layer: L0Constitutional,
        max_budget_bytes: 1024,
      ),
      Capability(
        id: "egress_credential_redaction",
        name: "Egress Credential Redaction",
        kind: ReadOnly,
        aspect: A03ZeroMudaPurity,
        layer: L0Constitutional,
        max_budget_bytes: 4096,
      ),
      Capability(
        id: "constitutional_2oo3_verification",
        name: "Constitutional 2oo3 Verification",
        kind: ReadOnly,
        aspect: A08FeedbackSemioticsHomeostasis,
        layer: L0Constitutional,
        max_budget_bytes: 2048,
      ),
    ],
    tool_allowlist: [
      "storage_status",
      "hardware_lock_verify",
      "token_rotate",
      "quorum_verify",
      "redactor_scrub",
    ],
    requires_2oo3: True,
    max_token_budget: 2048,
    sla_latency_ms: 2,
  )
}

pub fn multimodal_edge_ingestor_profile() -> AgentProfile {
  AgentProfile(
    id: "multimodal_edge_ingestor",
    name: "Multimodal Edge Ingestor",
    kind: ElasticSwarm,
    layer: L7FederationEgress,
    aspects: [A10MeshTelemetryObservability, A13MultiInterfaceAccessibility],
    capabilities: [
      Capability(
        id: "acoustic_vibration_spectrum_codec",
        name: "Acoustic Vibration Spectrum Codec",
        kind: ReadOnly,
        aspect: A10MeshTelemetryObservability,
        layer: L7FederationEgress,
        max_budget_bytes: 16_384,
      ),
      Capability(
        id: "vision_rack_caddy_cv",
        name: "Vision Rack Caddy CV",
        kind: ReadOnly,
        aspect: A10MeshTelemetryObservability,
        layer: L7FederationEgress,
        max_budget_bytes: 16_384,
      ),
      Capability(
        id: "voice_biometric_quorum_codec",
        name: "Voice Biometric Quorum Codec",
        kind: ReadOnly,
        aspect: A13MultiInterfaceAccessibility,
        layer: L7FederationEgress,
        max_budget_bytes: 8192,
      ),
    ],
    tool_allowlist: [
      "encode_acoustic",
      "analyze_caddy_vision",
      "verify_voice_quorum",
      "telegram_simulate_event",
    ],
    requires_2oo3: False,
    max_token_budget: 16_384,
    sla_latency_ms: 15,
  )
}

pub fn formal_verifier_oracle_profile() -> AgentProfile {
  AgentProfile(
    id: "formal_verifier_oracle",
    name: "Formal Verifier Oracle",
    kind: Singleton,
    layer: L8LivingKnowledge,
    aspects: [
      A06FormalEvidenceAnalysis,
      A07MathematicalAuthority,
      A15ComprehensiveVerificationChecklist,
    ],
    capabilities: [
      Capability(
        id: "lean4_theorem_validation",
        name: "Lean 4 Theorem Validation",
        kind: ReadOnly,
        aspect: A07MathematicalAuthority,
        layer: L0Constitutional,
        max_budget_bytes: 4096,
      ),
      Capability(
        id: "quint_parity_simulation",
        name: "Quint Parity Simulation",
        kind: ReadOnly,
        aspect: A07MathematicalAuthority,
        layer: L0Constitutional,
        max_budget_bytes: 4096,
      ),
      Capability(
        id: "gospel_contract_checking",
        name: "Gospel Contract Checking",
        kind: ReadOnly,
        aspect: A06FormalEvidenceAnalysis,
        layer: L8LivingKnowledge,
        max_budget_bytes: 4096,
      ),
    ],
    tool_allowlist: [
      "verification_run",
      "lean_check",
      "quint_verify",
      "z3_solve",
      "gospel_assert",
    ],
    requires_2oo3: False,
    max_token_budget: 4096,
    sla_latency_ms: 50,
  )
}

pub fn knowledge_sheaf_curator_profile() -> AgentProfile {
  AgentProfile(
    id: "knowledge_sheaf_curator",
    name: "Knowledge Sheaf Curator",
    kind: Singleton,
    layer: L8LivingKnowledge,
    aspects: [A16KnowledgeManagementTriad],
    capabilities: [
      Capability(
        id: "hermes_wiki_transclusion",
        name: "Hermes Wiki Transclusion",
        kind: ReadOnly,
        aspect: A16KnowledgeManagementTriad,
        layer: L8LivingKnowledge,
        max_budget_bytes: 8192,
      ),
      Capability(
        id: "zk_adr_cataloging",
        name: "ZK ADR Cataloging",
        kind: StateMutating,
        aspect: A16KnowledgeManagementTriad,
        layer: L8LivingKnowledge,
        max_budget_bytes: 8192,
      ),
      Capability(
        id: "living_ontology_sheaf_sync",
        name: "Living Ontology Sheaf Sync",
        kind: StateMutating,
        aspect: A16KnowledgeManagementTriad,
        layer: L8LivingKnowledge,
        max_budget_bytes: 8192,
      ),
    ],
    tool_allowlist: [
      "knowledge_search",
      "zk_read_note",
      "zk_author_note",
      "wiki_render_node",
      "ontology_sync",
    ],
    requires_2oo3: False,
    max_token_budget: 8192,
    sla_latency_ms: 20,
  )
}

pub fn quarantined_inference_worker_profile() -> AgentProfile {
  AgentProfile(
    id: "quarantined_inference_worker",
    name: "Quarantined AI Inference Worker",
    kind: ElasticSwarm,
    layer: L5CognitiveReasoning,
    aspects: [A09QuarantinedAIInference],
    capabilities: [
      Capability(
        id: "modular_max_mojo_rpc",
        name: "Modular MAX Mojo RPC",
        kind: SovereignAdvisory,
        aspect: A09QuarantinedAIInference,
        layer: L5CognitiveReasoning,
        max_budget_bytes: 16_384,
      ),
      Capability(
        id: "openrouter_gemma4_client",
        name: "OpenRouter Gemma 4 Client",
        kind: SovereignAdvisory,
        aspect: A09QuarantinedAIInference,
        layer: L5CognitiveReasoning,
        max_budget_bytes: 16_384,
      ),
      Capability(
        id: "daily_budget_gate_enforcement",
        name: "Daily Budget Gate Enforcement",
        kind: ReadOnly,
        aspect: A09QuarantinedAIInference,
        layer: L5CognitiveReasoning,
        max_budget_bytes: 2048,
      ),
    ],
    tool_allowlist: [
      "infer_gemma4",
      "budget_check_reservation",
      "emit_decision_envelope",
    ],
    requires_2oo3: False,
    max_token_budget: 16_384,
    sla_latency_ms: 5,
  )
}

/// Formats a complete markdown overview of all 17 System Aspects.
pub fn format_aspects_summary() -> String {
  "🛡️ *Canonical 17 System Aspects (UOS \\mathbb{A}_{17})*\n\n"
  <> "• `A01` **Substrate & Hardware Safety**: Host NVMe enclave locked (`[REDACTED_SYSTEM_OS_SERIAL]`) 🟢\n"
  <> "• `A02` **VCS Discipline**: Standalone Jujutsu monorepo (`.jj/`), zero Git mutations 🟢\n"
  <> "• `A03` **Zero-Muda Purity**: 0 Bevy, 0 Graphite, 0 foreign NIFs (Pure BEAM & Hermes) 🟢\n"
  <> "• `A04` **Supervision & Actor Hierarchy**: Pure Gleam/OTP 29 4-domain supervisor (`uos_sup.gleam`) 🟢\n"
  <> "• `A05` **Deterministic Runtime Engine**: Pure ZigVM VFS & arena kernel (19.85M ops/s) 🟢\n"
  <> "• `A06` **Formal Evidence & Analysis**: Hermes OCaml/Dune, Gospel contracts, Z3 bounded workers 🟢\n"
  <> "• `A07` **Mathematical Authority**: Lean 4 (13D coordinate conservation) & Quint parity 🟢\n"
  <> "• `A08` **Feedback & Homeostasis**: Prajna circuit breakers & Lyapunov decay trend detection 🟢\n"
  <> "• `A09` **Quarantined AI Inference**: MAX/Mojo isolated daemon & daily budget ledger ($10/day) 🟢\n"
  <> "• `A10` **Mesh Telemetry & Observability**: Zenoh pub/sub mesh & universal C3I OTel spans 🟢\n"
  <> "• `A11` **Agent Event Bus Protocol**: AG-UI isomorphic 32-event bidirectional stream 🟢\n"
  <> "• `A12` **Declarative UI Component Catalog**: A2UI declarative schema (233 trusted components) 🟢\n"
  <> "• `A13` **Multi-Interface Accessibility**: Triple-Interface Penta-Stack (Lustre + Wisp + TUI) 🟢\n"
  <> "• `A14` **Universal Tailscale Web Navigation**: Full clickable Tailscale FQDN links on all views 🟢\n"
  <> "• `A15` **Comprehensive Verification Checklist**: 5 domains, 18/18 checks 100% green (`G-CHECKLIST`) 🟢\n"
  <> "• `A16` **Knowledge Management Triad**: Hermes Wiki + ZigVM ZK (109 ADRs) + C3I Ontology 🟢\n"
  <> "• `A17` **Durable Execution & Workflow**: Sa-Plan sole execution authority (`SC-JIDOKA-001`) 🟢\n\n"
  <> "Send `/aspects <A01..A17>` for detailed invariants, governing files, and formal verification gates."
}

/// Formats detailed specifications for a single System Aspect by code or number.
pub fn format_aspect_detail(input: String) -> String {
  let normalized = string.uppercase(string.trim(input))
  let code = case normalized {
    "1" | "01" | "A1" | "A01" -> "A01"
    "2" | "02" | "A2" | "A02" -> "A02"
    "3" | "03" | "A3" | "A03" -> "A03"
    "4" | "04" | "A4" | "A04" -> "A04"
    "5" | "05" | "A5" | "A05" -> "A05"
    "6" | "06" | "A6" | "A06" -> "A06"
    "7" | "07" | "A7" | "A07" -> "A07"
    "8" | "08" | "A8" | "A08" -> "A08"
    "9" | "09" | "A9" | "A09" -> "A09"
    "10" | "A10" -> "A10"
    "11" | "A11" -> "A11"
    "12" | "A12" -> "A12"
    "13" | "A13" -> "A13"
    "14" | "A14" -> "A14"
    "15" | "A15" -> "A15"
    "16" | "A16" -> "A16"
    "17" | "A17" -> "A17"
    _ -> normalized
  }

  case code {
    "A01" ->
      "🛡️ *Aspect A01: Substrate & Hardware Safety Enclave*\n\n"
      <> "• *Domain:* Rust Native Kernel & K8s Controller (`ops/kubernetes/nas-k8s-lab/src/spec.rs`)\n"
      <> "• *Fractal Layer:* L0 Constitutional / L1 Atomic\n"
      <> "• *Primary Invariant:* `HARD_DENIED_SYSTEM_OS_SERIAL = \"[REDACTED_SYSTEM_OS_SERIAL]\"`\n"
      <> "• *Safety Control:* Storage interlock strictly bars NVMe Bay 0 from OSD allocation or wiping.\n"
      <> "• *Verification Gate:* 7/7 drive safety tests green (`CHK-07-DRIVE`)."

    "A02" ->
      "🌳 *Aspect A02: Version Control Discipline (Standalone JJ)*\n\n"
      <> "• *Domain:* Jujutsu Standalone (`.jj/`)\n"
      <> "• *Fractal Layer:* L0 Constitutional / L3 Transaction\n"
      <> "• *Primary Invariant:* Standalone non-colocated `.jj/` only; 0 native Git mutation commands.\n"
      <> "• *Safety Control:* Mutation through Jujutsu change IDs and sibling workspaces only.\n"
      <> "• *Verification Gate:* `CHK-18-JJ` pass."

    "A03" ->
      "🌱 *Aspect A03: Zero-Muda Purity & Language Boundaries*\n\n"
      <> "• *Domain:* BEAM OTP 29 & Hermes OCaml\n"
      <> "• *Fractal Layer:* L0 Constitutional\n"
      <> "• *Primary Invariant:* 0 Bevy, 0 Graphite, 0 foreign NIF shared libraries.\n"
      <> "• *Safety Control:* Pure Erlang 2D vector math (`graphene_nif.erl`), Python quarantined to MAX.\n"
      <> "• *Verification Gate:* `CHK-05-MUDA`, `CHK-06-GRAPH` pass."

    "A04" ->
      "🌲 *Aspect A04: Supervision & Actor Hierarchy*\n\n"
      <> "• *Domain:* Pure Gleam / OTP 29 (`uos_sup.gleam`)\n"
      <> "• *Fractal Layer:* L4 System / L9 SRE Homeostasis\n"
      <> "• *Primary Invariant:* Root 4-domain supervisor (Apps, Engines, Services, Intelligence) with isolated restart budgets.\n"
      <> "• *Safety Control:* Let-it-crash fault isolation, dead-man freshness monitors, zero zombie processes.\n"
      <> "• *Verification Gate:* `CHK-12-GLEAM` pass."

    "A05" ->
      "⚙️ *Aspect A05: Deterministic Runtime Engine (ZigVM)*\n\n"
      <> "• *Domain:* Pure Zig Deterministic Kernel (`engines/zigvm`)\n"
      <> "• *Fractal Layer:* L1 Atomic / L4 System\n"
      <> "• *Primary Invariant:* Descriptor-relative, race-free, symlink-aware VFS; linear arena allocation.\n"
      <> "• *Safety Control:* Zero GC jitter, 19.85M deterministic ops/s, lockless ring buffers.\n"
      <> "• *Verification Gate:* `CHK-14-ZIGVM` pass."

    "A06" ->
      "🔬 *Aspect A06: Formal Evidence & Bounded Analysis (Hermes)*\n\n"
      <> "• *Domain:* OCaml / Dune / Gospel / Z3 (`engines/hermes`)\n"
      <> "• *Fractal Layer:* L0 Constitutional / L3 Transaction\n"
      <> "• *Primary Invariant:* Authoritative SQLite WAL append-only ledgers; Cryptokit SHA-256 MCP interceptor.\n"
      <> "• *Safety Control:* Embedded NUL byte trap (-2), SQL injection trap (-3), bounded Z3 solver workers.\n"
      <> "• *Verification Gate:* `CHK-13-HERMES` pass."

    "A07" ->
      "📐 *Aspect A07: Mathematical Authority & Formal Invariants*\n\n"
      <> "• *Domain:* Lean 4 & Quint Formal Proofs (`formal/lean/`, `formal/quint/`)\n"
      <> "• *Fractal Layer:* L0 Constitutional\n"
      <> "• *Primary Invariant:* $\\Delta \\vec{\\mathcal{T}}_{13} \\equiv \\mathbf{0}$ (13D coordinate conservation); Two-Lattice STM.\n"
      <> "• *Safety Control:* Formal proofs fail closed on missing tools, timeout, `sorry`, or undeclared axioms.\n"
      <> "• *Verification Gate:* Lean 4 theorems verified without sorry."

    "A08" ->
      "⚖️ *Aspect A08: Feedback Semiotics & Dynamic Homeostasis*\n\n"
      <> "• *Domain:* Pure Gleam Prajna Controllers (`prajna/`, `ha/`)\n"
      <> "• *Fractal Layer:* L2 Component / L9 SRE Homeostasis\n"
      <> "• *Primary Invariant:* Lyapunov windowed trend detection (\\dot{V} \\le 0); Prajna circuit breakers.\n"
      <> "• *Safety Control:* Dead-man's-switch freshness monitors, 2oo3 constitutional consensus voting.\n"
      <> "• *Verification Gate:* Prajna circuit breaker test suite pass."

    "A09" ->
      "⚡ *Aspect A09: Quarantined AI Inference & Budget Ledger*\n\n"
      <> "• *Domain:* Modular MAX / Mojo (`services/inference/max`) & OpenRouter\n"
      <> "• *Fractal Layer:* L5 Cognitive Reasoning\n"
      <> "• *Primary Invariant:* Python strictly quarantined to `max_worker.py`; $10/day aggregate liability ledger.\n"
      <> "• *Safety Control:* Length-delimited JSON-RPC over stdio pipes; daily budget admission gate enforced.\n"
      <> "• *Verification Gate:* `CHK-15-MAX` pass."

    "A10" ->
      "📡 *Aspect A10: Mesh Telemetry & Observability*\n\n"
      <> "• *Domain:* Zenoh Pub/Sub & OpenTelemetry (`ui/zenoh_otel.gleam`)\n"
      <> "• *Fractal Layer:* L4 System / L6 Swarm Ecosystem\n"
      <> "• *Primary Invariant:* Universal C3I JSON logging with 128-bit W3C OTel trace_id & UTC microsecond timestamps.\n"
      <> "• *Safety Control:* Zenoh-over-mesh distributed tracing (`indrajaal/otel/spans/**`).\n"
      <> "• *Verification Gate:* `CHK-16-OTEL` pass."

    "A11" ->
      "🔄 *Aspect A11: Agent Event Bus Protocol (AG-UI)*\n\n"
      <> "• *Domain:* Gleam AG-UI Substrate (`agui/events.gleam`)\n"
      <> "• *Fractal Layer:* L5 Cognitive Reasoning / L6 Swarm\n"
      <> "• *Primary Invariant:* 32 isomorphic event types connecting agents to Lustre/Wisp/TUI surfaces.\n"
      <> "• *Safety Control:* Real-time streaming WebSocket/SSE/Zenoh event transport without client JS.\n"
      <> "• *Verification Gate:* AG-UI 32-event verification pass."

    "A12" ->
      "🎨 *Aspect A12: Declarative UI Component Catalog (A2UI)*\n\n"
      <> "• *Domain:* Gleam A2UI Schema (`a2ui/catalog.gleam`)\n"
      <> "• *Fractal Layer:* L2 Component State\n"
      <> "• *Primary Invariant:* 233 declarative component specs across 22 domains (0 executable agent JS).\n"
      <> "• *Safety Control:* Agent specs validated against allowlist before tripartite rendering.\n"
      <> "• *Verification Gate:* A2UI validator pass."

    "A13" ->
      "🖥️ *Aspect A13: Multi-Interface Accessibility (Penta-Stack)*\n\n"
      <> "• *Domain:* Pure Gleam Triple Interface (`ui/domain.gleam`)\n"
      <> "• *Fractal Layer:* L2 Component State / L4 System\n"
      <> "• *Primary Invariant:* Every capability simultaneously available on Lustre WebUI, Wisp API, and ANSI TUI.\n"
      <> "• *Safety Control:* Single domain model; zero client JavaScript dependencies.\n"
      <> "• *Verification Gate:* 381 UI regression tests green (`CHK-11-REGR`)."

    "A14" ->
      "🌐 *Aspect A14: Universal Tailscale Web Navigation*\n\n"
      <> "• *Domain:* Tailnet Mesh Networking (`contracts/rules/tailscale-web-fqdn-mandate.md`)\n"
      <> "• *Fractal Layer:* L7 Federation / L4 System\n"
      <> "• *Primary Invariant:* All dashboards, docs, wiki, and files carry clickable Tailscale FQDN links.\n"
      <> "• *Safety Control:* Base FQDN `http://nas-1.tail55d152.ts.net:4100`.\n"
      <> "• *Verification Gate:* `CHK-02-TAIL` pass."

    "A15" ->
      "📋 *Aspect A15: Comprehensive Verification Checklist*\n\n"
      <> "• *Domain:* Governance & Quality Engineering (`contracts/rules/comprehensive-checklist-contract.md`)\n"
      <> "• *Fractal Layer:* L0 Constitutional\n"
      <> "• *Primary Invariant:* 5 domains, 18 checkpoints rendered on every screen and document.\n"
      <> "• *Safety Control:* Mathematical gates H >= 2.5b, CCM >= 90%, D_EA <= 10%, ITQS >= 0.85.\n"
      <> "• *Verification Gate:* `CHK-01` through `CHK-18` 100% green (`G-CHECKLIST`)."

    "A16" ->
      "📚 *Aspect A16: Living Knowledge Management Triad*\n\n"
      <> "• *Domain:* Hermes Wiki + ZigVM ZK + C3I Ontology (`#km-triad`)\n"
      <> "• *Fractal Layer:* L8 Living Knowledge\n"
      <> "• *Primary Invariant:* Bidirectionally linked living knowledge graph with mandatory `YYYYMMDD-HHSS-` timestamp prefix.\n"
      <> "• *Safety Control:* Transclusion grammar (`[[wiki:...]]`, `[[zk:...]]`), 109 ratified ADRs.\n"
      <> "• *Verification Gate:* `CHK-04-KM` pass."

    "A17" ->
      "⚡ *Aspect A17: Durable Execution & Workflow (Sa-Plan)*\n\n"
      <> "• *Domain:* Sa-Plan Authority (`var/sa-plan/uos.sqlite3`)\n"
      <> "• *Fractal Layer:* L0 Constitutional / L3 Transaction\n"
      <> "• *Primary Invariant:* `sa-plan` is sole execution authority for tasks, Oban jobs, and Temporal workflows.\n"
      <> "• *Safety Control:* Non-sa-plan mutations trigger fail-closed Andon stop line (error -32002).\n"
      <> "• *Verification Gate:* `SC-SA-PLAN-001`, `SC-JIDOKA-001` pass."

    _ ->
      "⚠️ Unknown System Aspect code: `"
      <> input
      <> "`. Use `/aspects` to list all 17 canonical aspects."
  }
}

/// Formats a complete markdown overview of the Rich Agent Ecology.
pub fn format_ecology_summary() -> String {
  "🐝 *UOS Rich Multi-Agent Ecology (7 Canonical Holon Profiles)*\n\n"
  <> "1. 👑 `agy_sovereign_coordinator` [L0 Constitutional / L5 Cognitive]\n"
  <> "   • *Role:* Sovereign Cognitive Architect & Swarm Coordinator\n"
  <> "   • *Aspects:* A04, A08, A11, A16, A17 | *Capabilities:* 3 | *2oo3 Required:* False\n\n"
  <> "2. 🛡️ `sre_homeostasis_overseer` [L9 SRE Homeostasis / L4 System]\n"
  <> "   • *Role:* Autonomous SRE & Self-Healing Homeostasis Overseer\n"
  <> "   • *Aspects:* A04, A08, A10 | *Capabilities:* 3 | *2oo3 Required:* False\n\n"
  <> "3. 🔒 `security_hardware_guardian` [L0 Constitutional / L1 Atomic]\n"
  <> "   • *Role:* Hardware Safety Enclave & Zero-Trust Interceptor\n"
  <> "   • *Aspects:* A01, A03, A06 | *Capabilities:* 2 | *2oo3 Required:* False\n\n"
  <> "4. 👁️ `multimodal_edge_ingestor` [L5 Cognitive / L7 Federation]\n"
  <> "   • *Role:* Multimodal Edge Ingestor & Biomorphic Audio/Vision Pipeline\n"
  <> "   • *Aspects:* A09, A10 | *Capabilities:* 2 | *2oo3 Required:* False\n\n"
  <> "5. 📐 `formal_verifier_oracle` [L3 Transaction / L6 Ecosystem]\n"
  <> "   • *Role:* Mathematical Authority & Formal Contract Oracle\n"
  <> "   • *Aspects:* A06, A07 | *Capabilities:* 2 | *2oo3 Required:* False\n\n"
  <> "6. 📚 `knowledge_sheaf_curator` [L8 Living Knowledge / L6 Ecosystem]\n"
  <> "   • *Role:* Holographic Knowledge Sheaf & ZK Curator\n"
  <> "   • *Aspects:* A16, A17 | *Capabilities:* 2 | *2oo3 Required:* False\n\n"
  <> "7. ⚡ `quarantined_inference_worker` [L5 Cognitive Reasoning]\n"
  <> "   • *Role:* Quarantined AI Inference Worker\n"
  <> "   • *Aspects:* A09 | *Capabilities:* 3 | *2oo3 Required:* False\n\n"
  <> "Send `/ecology <agent_id>` to view detailed capability lattices and tool allowlists."
}

/// Formats detailed specifications for a single agent profile.
pub fn format_profile_detail(agent_id: String) -> String {
  case get_agent_profile(string.trim(agent_id)) {
    Ok(profile) -> {
      let cap_lines =
        list.map(profile.capabilities, fn(cap) {
          "• `" <> cap.id <> "` (" <> cap.name <> "): max budget " <> int.to_string(cap.max_budget_bytes) <> "B"
        })
        |> string.join("\n")

      let tools_str = string.join(profile.tool_allowlist, ", ")
      let quorum_str = case profile.requires_2oo3 {
        True -> "Yes (2oo3 Constitutional Quorum Required)"
        False -> "No (Single-Agent Safe Dispatch)"
      }

      "🤖 *Agent Profile: " <> profile.name <> "*\n\n"
      <> "• *ID:* `" <> profile.id <> "`\n"
      <> "• *Kind:* " <> case profile.kind {
        Singleton -> "Singleton"
        ElasticSwarm -> "ElasticSwarm"
        EphemeralHolon -> "EphemeralHolon"
      } <> "\n"
      <> "• *2oo3 Quorum:* " <> quorum_str <> "\n"
      <> "• *Max Token Budget:* " <> int.to_string(profile.max_token_budget) <> " tokens\n"
      <> "• *SLA Latency:* " <> int.to_string(profile.sla_latency_ms) <> " ms\n"
      <> "• *Tool Allowlist:* `" <> tools_str <> "`\n\n"
      <> "### ⚡ Capabilities\n"
      <> cap_lines
    }
    Error(_) ->
      "⚠️ Unknown agent profile ID: `"
      <> agent_id
      <> "`. Use `/ecology` to list all 7 canonical profiles."
  }
}
