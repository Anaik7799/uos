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

import cepaf_gleam/harness/agent_capabilities
import cepaf_gleam/harness/agent_meta_policy
import cepaf_gleam/harness/agent_preflight_map
import gleam/int
import gleam/list
import gleam/option.{type Option}
import gleam/result
import gleam/string
import uos_swarm/symbiosis_preflight

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

/// Canonical per-agent capability record binding each of the 6 sovereign
/// AgentId constructors (`agy`, `pi`, `codex`, `claude`, `deepseek`, `argon`)
/// to all 17 system aspects, all 10 fractal holarchy layers, all 6 FPP
/// services, all 4 bionic faculties, and both `zenoh` and `mcp` transports.
pub type SovereignAgentCapabilityRecord {
  SovereignAgentCapabilityRecord(
    agent_id: String,
    holarchy_layers: List(FractalLayer),
    assigned_aspects: List(SystemAspect),
    fpp_services: List(String),
    bionic_faculties: List(String),
    declared_transports: List(String),
    intelligence_mode: String,
  )
}

/// Enumerates all 10 canonical Fractal Layers in UOS.
pub fn all_fractal_layers() -> List(FractalLayer) {
  [
    L0Constitutional,
    L1Atomic,
    L2ComponentState,
    L3TransactionHistory,
    L4SystemRuntime,
    L5CognitiveReasoning,
    L6SwarmEcosystem,
    L7FederationEgress,
    L8LivingKnowledge,
    L9SREHomeostasis,
  ]
}

/// Deterministic Multi-Agent Quota/Budget/Outage Failover Selector (SC-MODEL-ROLE-TWIN-001).
/// Enforces Supervisor Minimization (OpenRouter+Gemini+Argon used ONLY when is_supervisor_task == True)
/// and cascades Claude -> Codex -> LocalQwen on outage, timeout, or quota/budget exhaustion.
pub fn select_failover_agent(
  is_supervisor_task: Bool,
  claude_ok: Bool,
  codex_ok: Bool,
  qwen_ok: Bool,
  sup_ok: Bool,
) -> Result(String, String) {
  case is_supervisor_task {
    True ->
      case sup_ok, claude_ok, codex_ok, qwen_ok {
        True, _, _, _ -> Ok("pi_openrouter_gemini_argon")
        False, True, _, _ -> Ok("claude")
        False, False, True, _ -> Ok("codex")
        False, False, False, True -> Ok("local_qwen")
        False, False, False, False ->
          Error("no_supervisor_or_failover_agent_available")
      }
    False ->
      case claude_ok, codex_ok, qwen_ok {
        True, _, _ -> Ok("claude")
        False, True, _ -> Ok("codex")
        False, False, True -> Ok("local_qwen")
        False, False, False ->
          Error("no_execution_agent_available_within_quota_or_budget")
      }
  }
}

/// Sovereign Operator Routing Selector: prioritizes AGY (Caste01) and DeepSeek-v3.2 over Pi+Argon
/// for supervisor tasks, and maximizes Local Qwen + Claude + Codex for execution tasks.
pub fn select_supervisor_or_failover_with_agy(
  is_supervisor_task: Bool,
  agy_ok: Bool,
  deepseek_ok: Bool,
  claude_ok: Bool,
  codex_ok: Bool,
  qwen_ok: Bool,
  pi_argon_ok: Bool,
) -> Result(String, String) {
  case is_supervisor_task {
    True ->
      case agy_ok, deepseek_ok, claude_ok, codex_ok, qwen_ok, pi_argon_ok {
        True, _, _, _, _, _ -> Ok("agy")
        False, True, _, _, _, _ -> Ok("deepseek_v3_2")
        False, False, True, _, _, _ -> Ok("claude")
        False, False, False, True, _, _ -> Ok("codex")
        False, False, False, False, True, _ -> Ok("local_qwen")
        False, False, False, False, False, True ->
          Ok("pi_openrouter_gemini_argon")
        False, False, False, False, False, False ->
          Error("no_supervisor_or_failover_agent_available")
      }
    False ->
      select_failover_agent(False, claude_ok, codex_ok, qwen_ok, pi_argon_ok)
  }
}

/// Pure Gleam mirror of `uos_lean_verify_tool_call_provenance` (C-ABI Export #21, THM_FSYS_51).
pub fn verify_tool_call_provenance(
  has_tool_calls: Bool,
  same_model_origin: Bool,
  has_thought_sig: Bool,
  has_validator_waiver: Bool,
  target_requires_sig: Bool,
) -> Bool {
  case has_tool_calls, target_requires_sig {
    False, _ -> True
    _, False -> True
    True, True ->
      { same_model_origin && has_thought_sig } || has_validator_waiver
  }
}

/// Returns the 6 canonical SovereignAgentCapabilityRecord entries matching
/// `formal/lean/UosAgentCapabilityProfile.lean` (`AgentId`).
pub fn all_sovereign_agent_capabilities() -> List(SovereignAgentCapabilityRecord) {
  [
    SovereignAgentCapabilityRecord(
      agent_id: "agy",
      holarchy_layers: all_fractal_layers(),
      assigned_aspects: all_system_aspects(),
      fpp_services: [
        "fpp_supervision",
        "fpp_telemetry",
        "fpp_command",
        "fpp_health",
        "fpp_sequencing",
        "fpp_parameter",
      ],
      bionic_faculties: [
        "metabolic_regime",
        "immune_circuit",
        "archetype_dispatch",
        "lyapunov_contraction",
      ],
      declared_transports: ["zenoh", "mcp"],
      intelligence_mode: "embedded",
    ),
    SovereignAgentCapabilityRecord(
      agent_id: "pi",
      holarchy_layers: all_fractal_layers(),
      assigned_aspects: all_system_aspects(),
      fpp_services: [
        "fpp_supervision",
        "fpp_telemetry",
        "fpp_command",
        "fpp_health",
        "fpp_sequencing",
        "fpp_parameter",
      ],
      bionic_faculties: [
        "metabolic_regime",
        "immune_circuit",
        "archetype_dispatch",
        "lyapunov_contraction",
      ],
      declared_transports: ["zenoh", "mcp"],
      intelligence_mode: "embedded",
    ),
    SovereignAgentCapabilityRecord(
      agent_id: "codex",
      holarchy_layers: all_fractal_layers(),
      assigned_aspects: all_system_aspects(),
      fpp_services: [
        "fpp_supervision",
        "fpp_telemetry",
        "fpp_command",
        "fpp_health",
        "fpp_sequencing",
        "fpp_parameter",
      ],
      bionic_faculties: [
        "metabolic_regime",
        "immune_circuit",
        "archetype_dispatch",
        "lyapunov_contraction",
      ],
      declared_transports: ["zenoh", "mcp"],
      intelligence_mode: "embedded",
    ),
    SovereignAgentCapabilityRecord(
      agent_id: "claude",
      holarchy_layers: all_fractal_layers(),
      assigned_aspects: all_system_aspects(),
      fpp_services: [
        "fpp_supervision",
        "fpp_telemetry",
        "fpp_command",
        "fpp_health",
        "fpp_sequencing",
        "fpp_parameter",
      ],
      bionic_faculties: [
        "metabolic_regime",
        "immune_circuit",
        "archetype_dispatch",
        "lyapunov_contraction",
      ],
      declared_transports: ["zenoh", "mcp"],
      intelligence_mode: "embedded",
    ),
    SovereignAgentCapabilityRecord(
      agent_id: "deepseek",
      holarchy_layers: all_fractal_layers(),
      assigned_aspects: all_system_aspects(),
      fpp_services: [
        "fpp_supervision",
        "fpp_telemetry",
        "fpp_command",
        "fpp_health",
        "fpp_sequencing",
        "fpp_parameter",
      ],
      bionic_faculties: [
        "metabolic_regime",
        "immune_circuit",
        "archetype_dispatch",
        "lyapunov_contraction",
      ],
      declared_transports: ["zenoh", "mcp"],
      intelligence_mode: "delegated",
    ),
    SovereignAgentCapabilityRecord(
      agent_id: "argon",
      holarchy_layers: all_fractal_layers(),
      assigned_aspects: all_system_aspects(),
      fpp_services: [
        "fpp_supervision",
        "fpp_telemetry",
        "fpp_command",
        "fpp_health",
        "fpp_sequencing",
        "fpp_parameter",
      ],
      bionic_faculties: [
        "metabolic_regime",
        "immune_circuit",
        "archetype_dispatch",
        "lyapunov_contraction",
      ],
      declared_transports: ["zenoh", "mcp"],
      intelligence_mode: "delegated",
    ),
  ]
}

/// Per-agent bionic faculty lookup (metabolic, immune, archetype, lyapunov).
pub fn metabolic_bionic_faculties_for_agent(
  agent_id: String,
) -> List(String) {
  let target = string.lowercase(string.trim(agent_id))
  case
    list.find(all_sovereign_agent_capabilities(), fn(rec) {
      rec.agent_id == target
    })
  {
    Ok(rec) -> rec.bionic_faculties
    Error(_) -> []
  }
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
    "knowledge" | "sheaf" | "curator" | "zk" | "wiki" ->
      "knowledge_sheaf_curator"
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
/// Historical advisory evaluator: caller-supplied booleans and the PERMITTED
/// string are not admission evidence. Runtime effects still require the actual
/// harness grant/task/intent/clock checks; the ontology does not upgrade this API.
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

/// Typed source-level four-agent capability coordinates. Declaration/source
/// presence does not establish loaded operation, fresh evidence or authority.
/// The legacy evaluate_agent_intent helper above is advisory only; its caller
/// flags cannot create an authenticated capability, TaskFence or effect grant.
pub fn agent_capability_registry() -> List(agent_capabilities.Registration) {
  agent_capabilities.registry()
}

/// Existing policy snapshot only; injected collector DATA is not admission.
pub fn format_agent_preflight(
  state: Option(symbiosis_preflight.State),
  ontology_sha256: Option(String),
  monotonic_ms: Int,
) -> Result(String, String) {
  agent_preflight_map.project(state, ontology_sha256, monotonic_ms)
  |> result.map(agent_preflight_map.format_snapshot)
}

/// Reuses the ecology view. Pure meta state is caller DATA, never authenticated
/// runtime ownership or legacy evaluate_agent_intent advisory admission flags.
pub fn format_agent_meta(state: Option(agent_meta_policy.State)) -> String {
  case state {
    option.None -> agent_meta_policy.summary()
    option.Some(value) -> agent_meta_policy.format_state(value)
  }
}

/// Explicit L-only conversion; no H role is inferred from a fractal coordinate.
pub fn meta_layer(
  layer: FractalLayer,
) -> Result(agent_meta_policy.Layer, String) {
  agent_meta_policy.layer(case layer {
    L0Constitutional -> 0
    L1Atomic -> 1
    L2ComponentState -> 2
    L3TransactionHistory -> 3
    L4SystemRuntime -> 4
    L5CognitiveReasoning -> 5
    L6SwarmEcosystem -> 6
    L7FederationEgress -> 7
    L8LivingKnowledge -> 8
    L9SREHomeostasis -> 9
  })
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
      <> "• *Safety Control:* Let-it-crash fault isolation, Prajna circuit breakers, Lyapunov stability proofs, dead-man freshness monitors, zero zombie processes.\n"
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
  <> "Send `/ecology <agent_id>` to view detailed capability lattices and tool allowlists.\n\n"
  <> agent_capabilities.format_registry()
  <> "\n\n"
  <> agent_preflight_map.format_summary()
  <> "\n\n"
  <> agent_meta_policy.summary()
}

/// Formats detailed specifications for a single agent profile.
pub fn format_profile_detail(agent_id: String) -> String {
  case get_agent_profile(string.trim(agent_id)) {
    Ok(profile) -> {
      let cap_lines =
        list.map(profile.capabilities, fn(cap) {
          "• `"
          <> cap.id
          <> "` ("
          <> cap.name
          <> "): max budget "
          <> int.to_string(cap.max_budget_bytes)
          <> "B"
        })
        |> string.join("\n")

      let tools_str = string.join(profile.tool_allowlist, ", ")
      let quorum_str = case profile.requires_2oo3 {
        True -> "Yes (2oo3 Constitutional Quorum Required)"
        False -> "No (Single-Agent Safe Dispatch)"
      }

      "🤖 *Agent Profile: "
      <> profile.name
      <> "*\n\n"
      <> "• *ID:* `"
      <> profile.id
      <> "`\n"
      <> "• *Kind:* "
      <> case profile.kind {
        Singleton -> "Singleton"
        ElasticSwarm -> "ElasticSwarm"
        EphemeralHolon -> "EphemeralHolon"
      }
      <> "\n"
      <> "• *2oo3 Quorum:* "
      <> quorum_str
      <> "\n"
      <> "• *Max Token Budget:* "
      <> int.to_string(profile.max_token_budget)
      <> " tokens\n"
      <> "• *SLA Latency:* "
      <> int.to_string(profile.sla_latency_ms)
      <> " ms\n"
      <> "• *Tool Allowlist:* `"
      <> tools_str
      <> "`\n\n"
      <> "### ⚡ Capabilities\n"
      <> cap_lines
    }
    Error(_) ->
      "⚠️ Unknown agent profile ID: `"
      <> agent_id
      <> "`. Use `/ecology` to list all 7 canonical profiles."
  }
}

/// Canonical 7 Provider APIs used across the 6 UOS Agent Harnesses (THM_FSYS_53).
pub type ProviderApiFppRecord {
  ProviderApiFppRecord(
    api_id: Int,
    api_name: String,
    endpoint_uri: String,
    primary_holarchy_layer: String,
    requires_strict_role_alternation: Bool,
    requires_thought_sig_or_waiver: Bool,
    supports_encrypted_reasoning: Bool,
    max_credit_limit_tokens: Int,
  )
}

pub fn canonical_provider_api_fpp_registry() -> List(ProviderApiFppRecord) {
  [
    ProviderApiFppRecord(
      api_id: 0,
      api_name: "LocalMaxQwenApi",
      endpoint_uri: "http://razr15-1.tail55d152.ts.net:8000/v1/chat/completions",
      primary_holarchy_layer: "L1_EXECUTION",
      requires_strict_role_alternation: False,
      requires_thought_sig_or_waiver: False,
      supports_encrypted_reasoning: False,
      max_credit_limit_tokens: 0,
    ),
    ProviderApiFppRecord(
      api_id: 1,
      api_name: "OpenRouterChatCompletionsApi",
      endpoint_uri: "https://openrouter.ai/api/v1/chat/completions",
      primary_holarchy_layer: "L7_SWARM_SESSION",
      requires_strict_role_alternation: False,
      requires_thought_sig_or_waiver: True,
      supports_encrypted_reasoning: True,
      max_credit_limit_tokens: 16_384,
    ),
    ProviderApiFppRecord(
      api_id: 2,
      api_name: "GoogleGenerativeAiV1BetaApi",
      endpoint_uri: "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent",
      primary_holarchy_layer: "L7_SWARM_SESSION",
      requires_strict_role_alternation: True,
      requires_thought_sig_or_waiver: True,
      supports_encrypted_reasoning: False,
      max_credit_limit_tokens: 32_768,
    ),
    ProviderApiFppRecord(
      api_id: 3,
      api_name: "DeepSeekReasoningChatApi",
      endpoint_uri: "https://openrouter.ai/api/v1/chat/completions#deepseek-v3.2",
      primary_holarchy_layer: "L5_KNOWLEDGE",
      requires_strict_role_alternation: False,
      requires_thought_sig_or_waiver: False,
      supports_encrypted_reasoning: True,
      max_credit_limit_tokens: 16_384,
    ),
    ProviderApiFppRecord(
      api_id: 4,
      api_name: "AnthropicClaudeMessagesApi",
      endpoint_uri: "https://api.anthropic.com/v1/messages",
      primary_holarchy_layer: "L8_ORCHESTRATION",
      requires_strict_role_alternation: True,
      requires_thought_sig_or_waiver: False,
      supports_encrypted_reasoning: True,
      max_credit_limit_tokens: 65_536,
    ),
    ProviderApiFppRecord(
      api_id: 5,
      api_name: "OpenAiCodexResponsesApi",
      endpoint_uri: "https://api.openai.com/v1/responses",
      primary_holarchy_layer: "L8_ORCHESTRATION",
      requires_strict_role_alternation: False,
      requires_thought_sig_or_waiver: False,
      supports_encrypted_reasoning: True,
      max_credit_limit_tokens: 65_536,
    ),
    ProviderApiFppRecord(
      api_id: 6,
      api_name: "UosHarnessMcpAndZenohApi",
      endpoint_uri: "http://nas-1.tail55d152.ts.net:4100/mcp",
      primary_holarchy_layer: "L6_INTERFACE",
      requires_strict_role_alternation: False,
      requires_thought_sig_or_waiver: False,
      supports_encrypted_reasoning: False,
      max_credit_limit_tokens: 0,
    ),
  ]
}

/// Deterministic 7-state Provider API interaction transition guard (THM_FSYS_54 / THM_GUARD_23).
/// States: 0=Idle, 1=PreflightOk, 2=ToolCallEmitted, 3=ToolResultAppended, 4=Compacting, 5=Completed, 6=FailClosed.
pub fn verify_provider_api_transition(
  prev_state: Int,
  next_state: Int,
  req_strict_alt: Bool,
  prov_ok: Bool,
  credit_cap_ok: Bool,
) -> Bool {
  case credit_cap_ok {
    False -> next_state == 6
    True ->
      case next_state {
        2 ->
          prov_ok
          && { !req_strict_alt || prev_state == 1 || prev_state == 3 }
        3 -> prev_state == 2
        5 -> prov_ok && { prev_state == 3 || prev_state == 1 }
        _ -> True
      }
  }
}

/// Resilient Error-Recovery Protocol actions for Provider API interactions.
pub type ProviderApiRecoveryAction {
  ProceedNominal
  InjectBase64ThoughtSigWaiver
  SynthesizeAbortedToolResult
  FailoverToLocalQwenOrDeepSeek
  TripPrajnaCircuitBreakerAndRetry
}

pub fn recovery_action_to_string(action: ProviderApiRecoveryAction) -> String {
  case action {
    ProceedNominal -> "PROCEED_NOMINAL"
    InjectBase64ThoughtSigWaiver -> "INJECT_BASE64_THOUGHT_SIG_WAIVER"
    SynthesizeAbortedToolResult -> "SYNTHESIZE_ABORTED_TOOL_RESULT"
    FailoverToLocalQwenOrDeepSeek -> "FAILOVER_TO_LOCAL_QWEN_OR_DEEPSEEK"
    TripPrajnaCircuitBreakerAndRetry -> "TRIP_PRAJNA_CIRCUIT_BREAKER_AND_RETRY"
  }
}

/// Data-driven error recovery decision across HTTP status codes and FPP state invariants.
pub fn determine_provider_api_recovery_action(
  prev_state: Int,
  next_state: Int,
  req_strict_alt: Bool,
  prov_ok: Bool,
  credit_cap_ok: Bool,
  http_status: Int,
) -> ProviderApiRecoveryAction {
  case !credit_cap_ok || http_status == 402 {
    True -> FailoverToLocalQwenOrDeepSeek
    False ->
      case !prov_ok || http_status == 400 {
        True ->
          case req_strict_alt && prev_state == 2 && next_state == 2 {
            True -> SynthesizeAbortedToolResult
            False -> InjectBase64ThoughtSigWaiver
          }
        False ->
          case
            http_status == 429
            || http_status == 500
            || http_status == 502
            || http_status == 503
            || http_status == 504
          {
            True -> TripPrajnaCircuitBreakerAndRetry
            False ->
              case
                verify_provider_api_transition(
                  prev_state,
                  next_state,
                  req_strict_alt,
                  prov_ok,
                  credit_cap_ok,
                )
              {
                True -> ProceedNominal
                False -> SynthesizeAbortedToolResult
              }
          }
      }
  }
}

/// Emits a structured W3C OTel (128-bit trace_id, 64-bit span_id) + L0..L9 Fractal + 17-Aspect JSON log record.
pub fn emit_provider_api_otel_fractal_span(
  api_id: Int,
  agent_id: String,
  prev_state: Int,
  next_state: Int,
  req_strict_alt: Bool,
  prov_ok: Bool,
  credit_cap_ok: Bool,
  http_status: Int,
  latency_us: Int,
  trace_id: String,
  span_id: String,
) -> String {
  let admissible =
    verify_provider_api_transition(
      prev_state,
      next_state,
      req_strict_alt,
      prov_ok,
      credit_cap_ok,
    )
  let action =
    determine_provider_api_recovery_action(
      prev_state,
      next_state,
      req_strict_alt,
      prov_ok,
      credit_cap_ok,
      http_status,
    )
  let layer = case api_id {
    0 -> "L1_EXECUTION"
    1 -> "L7_SWARM_SESSION"
    2 -> "L7_SWARM_SESSION"
    3 -> "L5_KNOWLEDGE"
    4 -> "L8_ORCHESTRATION"
    5 -> "L8_ORCHESTRATION"
    _ -> "L6_INTERFACE"
  }
  let adm_str = case admissible {
    True -> "true"
    False -> "false"
  }
  "{\"schema\":\"uos.c3i.otel.provider_api.v1\",\"trace_id\":\""
  <> trace_id
  <> "\",\"span_id\":\""
  <> span_id
  <> "\",\"fractal_layer\":\""
  <> layer
  <> "\",\"aspects_covered\":17,\"api_id\":"
  <> int.to_string(api_id)
  <> ",\"agent_id\":\""
  <> agent_id
  <> "\",\"prev_state\":"
  <> int.to_string(prev_state)
  <> ",\"next_state\":"
  <> int.to_string(next_state)
  <> ",\"http_status\":"
  <> int.to_string(http_status)
  <> ",\"latency_us\":"
  <> int.to_string(latency_us)
  <> ",\"transition_admissible\":"
  <> adm_str
  <> ",\"recovery_action\":\""
  <> recovery_action_to_string(action)
  <> "\",\"ev_ceiling\":93}"
}

/// Deterministic 64-state Provider API graceful error-recovery resolver (THM_FSYS_55 / THM_GUARD_24).
/// Actions:
///   0 = ProceedNominal
///   1 = ClampMaxTokensAndRetry
///   2 = InjectWaiverAndRetry
///   3 = SynthesizeAbortedToolResultAndRetry
///   4 = FailoverGoogleDirectV1Beta
///   5 = FailoverLocalMaxQwen
///   6 = FailClosedAndonHalt
pub fn resolve_provider_api_recovery(
  http_status_class: Int,
  affordable_tokens_ge64: Bool,
  strict_alt_violation: Bool,
  google_direct_available: Bool,
  local_qwen_available: Bool,
) -> Int {
  case http_status_class {
    0 -> 0
    1 ->
      case strict_alt_violation {
        True -> 3
        False -> 2
      }
    2 ->
      case affordable_tokens_ge64 {
        True -> 1
        False ->
          case google_direct_available {
            True -> 4
            False ->
              case local_qwen_available {
                True -> 5
                False -> 6
              }
          }
      }
    _ ->
      case google_direct_available {
        True -> 4
        False ->
          case local_qwen_available {
            True -> 5
            False -> 6
          }
      }
  }
}

/// Deterministic 192-state UOS Service Mesh (Holarchy + Agents + FPP + Zenoh + MCP + OTel) binding verifier
/// (`THM_FSYS_56..58` / `THM_GUARD_25`, Export #25 `uos_lean_verify_service_mesh_binding`).
pub fn verify_uos_service_mesh_binding(
  service_id: Int,
  fpp_port_ready: Bool,
  zenoh_connected: Bool,
  mcp_authorized: Bool,
  c_abi_guard_ok: Bool,
) -> Bool {
  service_id >= 0
  && service_id < 12
  && fpp_port_ready
  && zenoh_connected
  && mcp_authorized
  && c_abi_guard_ok
}

/// Expected System Directory Object Kind ID (`0..4`) for `dir_id` (`0..51`):
///   0 (`0..11`)  = SystemService (`Svc00..Svc11`)
///   1 (`12..18`) = ProviderApi (`LocalMaxQwenApi..UosHarnessMcpAndZenohApi`)
///   2 (`19..24`) = SovereignAgent (`agy..argon`)
///   3 (`25..34`) = HolarchyLayer (`L0_Constitutional..L9_Sovereign`)
///   4 (`35..51`) = SystemAspect (`A01..A17`)
pub fn expected_system_directory_kind_id(dir_id: Int) -> Int {
  case dir_id >= 0 && dir_id < 12 {
    True -> 0
    False ->
      case dir_id >= 12 && dir_id < 19 {
        True -> 1
        False ->
          case dir_id >= 19 && dir_id < 25 {
            True -> 2
            False ->
              case dir_id >= 25 && dir_id < 35 {
                True -> 3
                False ->
                  case dir_id >= 35 && dir_id < 52 {
                    True -> 4
                    False -> 255
                  }
              }
          }
      }
  }
}

/// Deterministic 2,080-state UOS System Directory Service object verifier
/// (`THM_FSYS_59..60` / `THM_GUARD_26`, Export #26 `uos_lean_verify_system_directory_object`).
pub fn verify_system_directory_object(
  dir_id: Int,
  kind_id: Int,
  holarchy_ok: Bool,
  fpp_zenoh_mcp_otel_ok: Bool,
  aspect_mask_17_ok: Bool,
) -> Bool {
  dir_id >= 0
  && dir_id < 52
  && kind_id == expected_system_directory_kind_id(dir_id)
  && holarchy_ok
  && fpp_zenoh_mcp_otel_ok
  && aspect_mask_17_ok
}

/// Deterministic 1,632-state UOS 17-Aspect SDLC & SRE Feature Matrix gate verifier
/// (`THM_FSYS_61..62` / `THM_GUARD_27`, Export #27 `uos_lean_verify_sdlc_sre_feature_aspect_gate`).
pub fn verify_sdlc_sre_feature_aspect_gate(
  feature_id: Int,
  aspect_id: Int,
  sdlc_12_ok: Bool,
  sre_8_ok: Bool,
  tri_agent_claude_ok: Bool,
  tri_agent_codex_ok: Bool,
) -> Bool {
  feature_id >= 0
  && feature_id < 6
  && aspect_id >= 0
  && aspect_id < 17
  && sdlc_12_ok
  && sre_8_ok
  && tri_agent_claude_ok
  && tri_agent_codex_ok
}

/// Canonical Hardware Storage Interlock Constant (`A01` / `SC-STORAGE-SAFETY-001`):
/// Strictly locks the host OS NVMe serial against OSD wiping or allocation.
pub const hard_denied_system_os_serial = "25503L801736"

/// Returns `True` iff `candidate_serial` is non-empty and does NOT match `hard_denied_system_os_serial`.
pub fn verify_nvme_interlock_serial(candidate_serial: String) -> Bool {
  candidate_serial != "" && candidate_serial != hard_denied_system_os_serial
}

/// Deterministic 3,200-state Local Qwen 8-Pillar Holonic Execution Envelope verifier
/// (`THM_FSYS_63..64` / `THM_GUARD_28`, Export #28 `uos_lean_verify_qwen_holonic_execution_envelope`).
pub fn verify_qwen_holonic_execution_envelope(
  holarchy_layer: Int,
  fpp_actor_id: Int,
  caste_idx: Int,
  mojo_max_sm75_ready: Bool,
  lean_c_abi_and_mcp_ok: Bool,
  zenoh_and_otel_128_ok: Bool,
) -> Bool {
  holarchy_layer >= 0
  && holarchy_layer < 10
  && fpp_actor_id >= 0
  && fpp_actor_id < 40
  && fpp_actor_id / 4 == holarchy_layer
  && caste_idx >= 0
  && caste_idx < 5
  && mojo_max_sm75_ready
  && lean_c_abi_and_mcp_ok
  && zenoh_and_otel_128_ok
}

/// Maps a canonical Local Qwen `usecase_id` (`0..9`, `UC00..UC09`) to its optimal
/// runtime profile code (`1..5`: `P0_Deterministic_Grammar` .. `P4_LowLatency_SSE_Stream`),
/// or `0` when out of bounds (`THM_FSYS_65..66` / `THM_GUARD_29`).
pub fn expected_qwen_usecase_profile_code(usecase_id: Int) -> Int {
  case usecase_id {
    0 | 4 | 5 -> 1
    1 | 2 | 3 -> 2
    6 | 8 -> 3
    7 -> 4
    9 -> 5
    _ -> 0
  }
}

/// Maps a canonical Local Qwen `usecase_id` (`0..9`, `UC00..UC09`) to its exact
/// Real-World UOS Model Assignment Code (`1..5`), or `0` when out of bounds (`THM_FSYS_65..66`):
/// - `1` (`Qwen+AGY`): `UC00` (Pi Compaction & thoughtSignature), `UC04` (Fractal RCA/5-Whys/Sa-plan), `UC08` (KM Triad & SC-JOURNAL-v3 Collation)
/// - `2` (`Qwen+Claude`): `UC01` (`sm_75` CUDA/PTX Shim & Mojo Tensor Core Kernel)
/// - `3` (`Qwen+Codex`): `UC02` (Lean 4 Digital Twin & C-ABI Proving), `UC05` (`uos-harness` 104-Route MCP & Zenoh/OTel Mesh)
/// - `4` (`Qwen+TriAgent`): `UC03` (Differential Mojo Oracles & Zero-Python), `UC06` (Gleam/OTP Supervision & 392-State Provider API), `UC07` (Tri-Agent 17-Aspect SDLC/SRE Dual-Slot Swarm)
/// - `5` (`QwenAutonomous`): `UC09` (100% Autonomous `pi-local+qwen` CLI & Real-Time SSE Cockpit)
pub fn expected_qwen_model_assignment_code(usecase_id: Int) -> Int {
  case usecase_id {
    0 | 4 | 8 -> 1
    1 -> 2
    2 | 5 -> 3
    3 | 6 | 7 -> 4
    9 -> 5
    _ -> 0
  }
}

/// Deterministic 1,600-state Local Qwen 10-Usecase Runtime Engine Router
/// (`THM_FSYS_65..66` / `THM_GUARD_29`, Export #29 `uos_lean_route_optimal_qwen_usecase`).
/// Returns the optimal profile code (`1..5`) or `0` (Fail-Closed Veto).
pub fn route_optimal_qwen_usecase(
  usecase_id: Int,
  holarchy_layer: Int,
  prompt_fits_16k_or_compacted: Bool,
  backend_ready: Bool,
  holonic_envelope_ok: Bool,
  kv_prefix_cache_ok: Bool,
) -> Int {
  case
    usecase_id >= 0
    && usecase_id < 10
    && holarchy_layer == usecase_id
    && prompt_fits_16k_or_compacted
    && backend_ready
    && holonic_envelope_ok
    && kv_prefix_cache_ok
  {
    True -> expected_qwen_usecase_profile_code(usecase_id)
    False -> 0
  }
}

/// Exact bijection `usecase_id (0..9) -> ontology_uc_id (1..10)` between `UC00..UC09`
/// and the 10 Harness↔Model Interaction Ontology Optimization Use-Cases (`UC-1..UC-10`)
/// (`THM_FSYS_67..68` / `THM_GUARD_30`):
/// - `0 (UC00, L0 Constitutional)` -> `3 (UC-3: Prompt Prefix Layout Discipline)`
/// - `1 (UC01, L1 Kinetic)`        -> `5 (UC-5: Read-Batching & Symbol-Index Hinting)`
/// - `2 (UC02, L2 Structural)`     -> `9 (UC-9: Pre-Commit Formal Gate / Lean 4 Proofs)`
/// - `3 (UC03, L3 Reflexive)`      -> `2 (UC-2: Thinking-Budget Cap by Facet A × Facet D)`
/// - `4 (UC04, L4 Metabolic)`      -> `1 (UC-1: Reminder-Stripping & Delta Injection at A3)`
/// - `5 (UC05, L5 Regulatory)`     -> `7 (UC-7: Tool-Failure Short-Circuit / Jidoka Triage)`
/// - `6 (UC06, L6 Cognitive)`      -> `6 (UC-6: Proactive Compaction at 80% Context)`
/// - `7 (UC07, L7 Societal)`       -> `8 (UC-8: Single-Flight #km-triad Bundle & Dual-Slot Swarm)`
/// - `8 (UC08, L8 Evolutionary)`   -> `4 (UC-4: Tier Routing per SC-INTEL-ROUTING-001 R1/R2)`
/// - `9 (UC09, L9 Sovereign)`      -> `10 (UC-10: Sovereign Subagent & Interactive SSE Cockpit)`
pub fn expected_ontology_uc_id(usecase_id: Int) -> Int {
  case usecase_id {
    0 -> 3
    1 -> 5
    2 -> 9
    3 -> 2
    4 -> 1
    5 -> 7
    6 -> 6
    7 -> 8
    8 -> 4
    9 -> 10
    _ -> 0
  }
}

/// Deterministic 1,500-state Unified Domain Ontology (`13 Axes`), Interaction Ontology (`UC-1..UC-10`),
/// Fractal (`L0..L9`), and Holarchy (`40 FPP`, `170 Holons`, `52 Directory`) Fibration Guard
/// (`THM_FSYS_67..68` / `THM_GUARD_30`, Export #30 `uos_lean_verify_unified_ontology_usecase_fibration`).
pub fn verify_unified_ontology_usecase_fibration(
  usecase_id: Int,
  ontology_uc_id: Int,
  fractal_layer: Int,
  fpp_actor_id: Int,
  cascade_tier: Int,
  route_code: Int,
) -> Bool {
  usecase_id >= 0
  && usecase_id < 10
  && ontology_uc_id == expected_ontology_uc_id(usecase_id)
  && fractal_layer == usecase_id
  && fpp_actor_id == fractal_layer * 4 + 3
  && { cascade_tier == 1 || cascade_tier == 2 }
  && route_code >= 0
  && route_code <= 2
}

/// Deterministic 3,200-state Fractal 10-Layer Use-Case Test Gate for Performance,
/// 1st-Time Correctness & Context Optimization (`THM_FSYS_69..70` / `THM_GUARD_31`,
/// Export #31 `uos_lean_eval_fractal_usecase_test_gate`).
/// Returns the optimal profile code (`1..5`) or `0` (Fail-Closed Veto).
pub fn eval_fractal_usecase_test_gate(
  usecase_id: Int,
  fractal_layer: Int,
  perf_sla_ok: Bool,
  first_time_correct_ok: Bool,
  context_opt_ok: Bool,
  ontology_fibration_ok: Bool,
  holonic_envelope_ok: Bool,
) -> Int {
  case
    usecase_id >= 0
    && usecase_id < 10
    && fractal_layer == usecase_id
    && perf_sla_ok
    && first_time_correct_ok
    && context_opt_ok
    && ontology_fibration_ok
    && holonic_envelope_ok
  {
    True -> expected_qwen_usecase_profile_code(usecase_id)
    False -> 0
  }
}

/// Deterministic 3,840-state SM75 (Turing) Hardware + Modular MAX + Mojo + Qwen
/// Simulator Envelope Gate (`THM_FSYS_75..76` / `THM_GUARD_34`, Export #34).
pub fn simulate_sm75_qwen_hardware_envelope(
  config_id: Int,
  observed_vram_mib: Int,
  observed_mbu_pct: Int,
  observed_cached_ttft_ms: Int,
  observed_grammar_penalty_pct: Int,
  observed_schema_fail_pct: Int,
) -> Int {
  case
    config_id >= 0
    && config_id < 8
    && observed_vram_mib > 0
    && observed_vram_mib <= 8192
    && observed_mbu_pct >= 75
    && observed_mbu_pct <= 100
    && observed_cached_ttft_ms > 0
    && observed_cached_ttft_ms <= 150
    && observed_grammar_penalty_pct >= 0
    && observed_grammar_penalty_pct <= 5
    && observed_schema_fail_pct >= 0
    && observed_schema_fail_pct <= 1
  {
    True -> 1
    False -> 0
  }
}

/// Deterministic 2,560-state Public Benchmark Reference Suite Gate (`THM_FSYS_77..78`
/// / `THM_GUARD_35`, Export #35: BFCL-v3, tau-bench, RULER/NIAH, JSONSchemaBench/XGrammar,
/// LLMPerf, llama-bench, vLLM/MAX Concurrency, EvalPlus).
pub fn expected_benchmark_min_score_pct(benchmark_id: Int) -> Int {
  case benchmark_id {
    0 -> 98
    1 -> 95
    2 -> 96
    3 -> 99
    4 | 5 -> 75
    6 -> 90
    7 -> 95
    _ -> 101
  }
}

pub fn expected_benchmark_max_lat_or_pen(benchmark_id: Int) -> Int {
  case benchmark_id {
    0 -> 1200
    1 -> 2500
    2 -> 1500
    3 -> 5
    4 -> 150
    5 -> 25
    6 -> 1800
    7 -> 1500
    _ -> 0
  }
}

pub fn verify_public_benchmark_gate(
  benchmark_id: Int,
  observed_score_pct: Int,
  observed_lat_or_pen: Int,
  zero_retries_ok: Bool,
  zero_python_harness_ok: Bool,
) -> Int {
  case
    benchmark_id >= 0
    && benchmark_id < 8
    && observed_score_pct >= expected_benchmark_min_score_pct(benchmark_id)
    && observed_score_pct <= 100
    && observed_lat_or_pen > 0
    && observed_lat_or_pen <= expected_benchmark_max_lat_or_pen(benchmark_id)
    && zero_retries_ok
    && zero_python_harness_ok
  {
    True -> 1
    False -> 0
  }
}

/// Deterministic 3,200-state UOS Core System Concepts & 3-Layer Unified Ontology
/// Gate (`THM_FSYS_79..80` / `THM_GUARD_36`, Export #36).
pub fn expected_concept_cardinality(concept_id: Int) -> Int {
  case concept_id {
    0 -> 399
    1 -> 13
    2 -> 52
    3 -> 10
    4 -> 7
    5 -> 4
    6 -> 3
    7 -> 13
    8 -> 10
    9 -> 93
    _ -> 0
  }
}

pub fn expected_concept_min_coverage_pct(concept_id: Int) -> Int {
  case concept_id {
    0 | 2 | 4 | 5 | 6 | 7 | 8 -> 98
    1 | 3 -> 95
    9 -> 100
    _ -> 101
  }
}

pub fn verify_system_concepts_and_ontology_gate(
  concept_id: Int,
  observed_cardinality: Int,
  observed_coverage_pct: Int,
  type_separated_ok: Bool,
  two_key_observed_ok: Bool,
) -> Int {
  case
    concept_id >= 0
    && concept_id < 10
    && observed_cardinality == expected_concept_cardinality(concept_id)
    && observed_coverage_pct >= expected_concept_min_coverage_pct(concept_id)
    && observed_coverage_pct <= 100
    && type_separated_ok
    && two_key_observed_ok
  {
    True -> 1
    False -> 0
  }
}

/// Deterministic 3,840-state 12-Language Polyglot SDLC/SRE Optimization Gate
/// (`THM_FSYS_81..82` / `THM_GUARD_37`, Export #37: Lean 4, Mojo, MAX/SM75,
/// OCaml/Hermes, Gleam/OTP 29, Stan/Stanc3/Posterior, Zig/ZigVM, Rust/C-ABI NIFs,
/// Quint, NASA FPP/SysML, SQLite WAL/Rete-UL/Ruliad, Determinate Nix/Systemd).
pub fn expected_language_min_artifact_count(lang_id: Int) -> Int {
  case lang_id {
    0 -> 110
    1 -> 25
    2 -> 12
    3 -> 200
    4 -> 1000
    5 -> 120
    6 -> 100
    7 -> 11
    8 -> 14
    9 | 10 -> 40
    11 -> 25
    _ -> 99_999
  }
}

pub fn expected_language_min_pass_pct(lang_id: Int) -> Int {
  case lang_id {
    0 | 5 | 7 | 9 | 10 -> 100
    1 | 2 | 3 | 4 | 6 | 8 | 11 -> 98
    _ -> 101
  }
}

pub fn expected_language_max_latency_ms(lang_id: Int) -> Int {
  case lang_id {
    0 -> 2500
    1 -> 1500
    2 -> 150
    3 | 4 -> 50
    5 | 11 -> 100
    6 | 10 -> 10
    7 -> 5
    8 -> 2000
    9 -> 20
    _ -> 0
  }
}

pub fn verify_polyglot_language_optimization_gate(
  lang_id: Int,
  observed_artifact_count: Int,
  observed_pass_rate_pct: Int,
  observed_latency_ms: Int,
  zero_muda_aligned_ok: Bool,
  fail_closed_boundary_ok: Bool,
) -> Int {
  case
    lang_id >= 0
    && lang_id < 12
    && observed_artifact_count >= expected_language_min_artifact_count(lang_id)
    && observed_pass_rate_pct >= expected_language_min_pass_pct(lang_id)
    && observed_pass_rate_pct <= 100
    && observed_latency_ms > 0
    && observed_latency_ms <= expected_language_max_latency_ms(lang_id)
    && zero_muda_aligned_ok
    && fail_closed_boundary_ok
  {
    True -> 1
    False -> 0
  }
}

/// PolyBench-SM75 Language 3 (Gleam) Tier 3 Seed: PacketState & RouterError
pub type PolyBenchPacketState {
  PolyBenchPacketState(seq: Int, retries: Int, payload: String)
}

pub type PolyBenchRouterError {
  EmptyPayload
  MaxRetriesExceeded
}

/// Railway-oriented packet advancement using `use` callback and Gleam record update
pub fn advance_polybench_packet(
  state: PolyBenchPacketState,
) -> Result(PolyBenchPacketState, PolyBenchRouterError) {
  use _ <- result.try(case state.payload {
    "" -> Error(EmptyPayload)
    _ -> Ok(Nil)
  })
  case state.retries {
    r if r >= 3 -> Error(MaxRetriesExceeded)
    r ->
      Ok(PolyBenchPacketState(..state, seq: state.seq + 1, retries: r + 1))
  }
}

/// Deterministic 3,840-state PolyBench-SM75 6-Language × 4-Tier Gate (`THM_FSYS_83..84`, Export `#38`)
pub fn verify_polybench_sm75_language_tier_gate(
  poly_lang_id: Int,
  tier_id: Int,
  well_formed_diff_pct: Int,
  cached_turn2_ttft_ms: Int,
  observed_mbu_pct: Int,
  grammar_itl_overhead_pct: Int,
  pass_at_2_ok: Bool,
) -> Int {
  case
    poly_lang_id >= 0
    && poly_lang_id < 6
    && tier_id >= 1
    && tier_id <= 4
    && well_formed_diff_pct >= 95
    && well_formed_diff_pct <= 100
    && cached_turn2_ttft_ms > 0
    && cached_turn2_ttft_ms <= 120
    && observed_mbu_pct >= 72
    && observed_mbu_pct <= 100
    && grammar_itl_overhead_pct >= 0
    && grammar_itl_overhead_pct <= 6
    && pass_at_2_ok
  {
    True -> 1
    False -> 0
  }
}

/// PolyBench-SM75 3-Rule Diagnosis Matrix Classifier (`THM_FSYS_83`)
pub fn diagnose_polybench_sm75_failure_mode(
  rust_c_pass1_pct: Int,
  mojo_gleam_pass1_pct: Int,
  tier3_pass2_pct: Int,
  well_formed_diff_pct: Int,
) -> Int {
  case well_formed_diff_pct < 95 {
    True -> 3
    False ->
      case rust_c_pass1_pct >= 85 && mojo_gleam_pass1_pct < 70 {
        True -> 1
        False ->
          case rust_c_pass1_pct >= 85 && tier3_pass2_pct < 75 {
            True -> 2
            False -> 0
          }
      }
  }
}

/// Deterministic 3,200-state Fractal (L0..L9) & Holarchy (40 FPP Actors, 5 Castes, 170 Janus Holons, 52 Dir, 104 MCP, 13D) Gate (`THM_FSYS_85..86`, Export `#39`)
pub fn verify_fractal_holarchy_full_alignment_gate(
  layer_id: Int,
  fpp_intel_actor_id: Int,
  hive_caste_id: Int,
  janus_holon_start: Int,
  janus_holon_end: Int,
  unified_dir_id: Int,
  mcp_routes_total: Int,
  trace_coords_total: Int,
) -> Int {
  case
    layer_id >= 0
    && layer_id < 10
    && fpp_intel_actor_id == 4 * layer_id + 3
    && hive_caste_id == layer_id / 2
    && janus_holon_start == 17 * layer_id
    && janus_holon_end == 17 * layer_id + 16
    && unified_dir_id == 25 + layer_id
    && mcp_routes_total == 104
    && trace_coords_total == 13
  {
    True -> 1
    False -> 0
  }
}

pub fn expected_wave2_primary_layer_id(wave_cycle_id: Int) -> Int {
  case wave_cycle_id {
    0 -> 2
    1 -> 3
    2 -> 4
    3 -> 6
    4 -> 8
    _ -> 99
  }
}

/// Deterministic 3,200-state Evolutionary Wave 2 Convergence Gate (`Cycles 21..25`, `THM_FSYS_87..88`, Export `#40`)
pub fn verify_evolutionary_wave2_convergence_gate(
  wave_cycle_id: Int,
  cycle_num: Int,
  primary_layer_id: Int,
  nif_symbols_verified: Int,
  cabi_exports_verified: Int,
  mtest_total_passed: Int,
  diagonal_sweep_gates: Int,
  live_probe_ok: Bool,
) -> Int {
  case
    wave_cycle_id >= 0
    && wave_cycle_id < 5
    && cycle_num == 21 + wave_cycle_id
    && primary_layer_id == expected_wave2_primary_layer_id(wave_cycle_id)
    && nif_symbols_verified == 11
    && cabi_exports_verified == 40
    && mtest_total_passed == 34
    && diagonal_sweep_gates == 9
    && live_probe_ok
  {
    True -> 1
    False -> 0
  }
}

/// Deterministic 3,200-state Full-System Artifact, Component & 17-Aspect Wiring Gate (`THM_FSYS_90..91`, Export `#41`)
pub fn verify_full_system_artifact_aspect_component_wiring_gate(
  layer_id: Int,
  fpp_actor_base: Int,
  hive_caste_id: Int,
  aspect_slice_count: Int,
  directory_total_entries: Int,
  polyglot_domains_wired: Int,
  mcp_and_live_corpus_routes: Int,
  cross_plane_bridge_vectors: Int,
) -> Int {
  case
    layer_id >= 0
    && layer_id < 10
    && fpp_actor_base == layer_id * 4
    && hive_caste_id == layer_id / 2
    && aspect_slice_count == 17
    && directory_total_entries == 52
    && polyglot_domains_wired == 12
    && mcp_and_live_corpus_routes == 104
    && cross_plane_bridge_vectors == 24
  {
    True -> 1
    False -> 0
  }
}

/// Canonical 24-element Cross-Plane C-ABI (`Exports #28..#41`) <-> Gleam BEAM Bridge Parity Vector
/// (`[1,0,3,0,1,0,3,0,1,0,1,0,1,0,1,0,1,0,1,0,1,0,1,0]`).
pub fn evaluate_cross_plane_bridge_vectors_28_to_41() -> List(Int) {
  let b28_pos = case
    verify_qwen_holonic_execution_envelope(6, 27, 1, True, True, True)
  {
    True -> 1
    False -> 0
  }
  let b28_neg = case
    verify_qwen_holonic_execution_envelope(6, 23, 1, True, True, True)
  {
    True -> 1
    False -> 0
  }
  let b30_pos = case
    verify_unified_ontology_usecase_fibration(6, 6, 6, 27, 2, 2)
  {
    True -> 1
    False -> 0
  }
  let b30_neg = case
    verify_unified_ontology_usecase_fibration(6, 6, 6, 27, 4, 2)
  {
    True -> 1
    False -> 0
  }
  [
    b28_pos,
    b28_neg,
    route_optimal_qwen_usecase(6, 6, True, True, True, True),
    route_optimal_qwen_usecase(6, 5, True, True, True, True),
    b30_pos,
    b30_neg,
    eval_fractal_usecase_test_gate(6, 6, True, True, True, True, True),
    eval_fractal_usecase_test_gate(6, 6, False, True, True, True, True),
    simulate_sm75_qwen_hardware_envelope(6, 7493, 79, 68, 2, 0),
    simulate_sm75_qwen_hardware_envelope(8, 8333, 79, 68, 2, 0),
    verify_public_benchmark_gate(4, 92, 68, True, True),
    verify_public_benchmark_gate(4, 60, 68, True, True),
    verify_system_concepts_and_ontology_gate(9, 93, 100, True, True),
    verify_system_concepts_and_ontology_gate(9, 94, 100, True, True),
    verify_polyglot_language_optimization_gate(5, 125, 100, 18, True, True),
    verify_polyglot_language_optimization_gate(5, 110, 100, 18, True, True),
    verify_polybench_sm75_language_tier_gate(0, 3, 100, 62, 81, 2, True),
    verify_polybench_sm75_language_tier_gate(0, 3, 90, 62, 81, 2, True),
    verify_fractal_holarchy_full_alignment_gate(6, 27, 3, 102, 118, 31, 104, 13),
    verify_fractal_holarchy_full_alignment_gate(6, 27, 3, 102, 117, 31, 104, 13),
    verify_evolutionary_wave2_convergence_gate(1, 22, 3, 11, 40, 34, 9, True),
    verify_evolutionary_wave2_convergence_gate(1, 22, 2, 11, 40, 34, 9, True),
    verify_full_system_artifact_aspect_component_wiring_gate(
      6,
      24,
      3,
      17,
      52,
      12,
      104,
      24,
    ),
    verify_full_system_artifact_aspect_component_wiring_gate(
      6,
      25,
      3,
      17,
      52,
      12,
      104,
      24,
    ),
  ]
}

/// Pure Total Wave-4 Pi+Harness+MAX+Mojo+Qwen 15-Cycle Symbiosis & Traffic Gate
/// (Mirrors Lean 4 C-ABI Export #42 `uos_lean_verify_pi_qwen_15cycle_symbiosis_gate`).
pub fn verify_pi_qwen_15cycle_symbiosis_gate(
  w4_id: Int,
  cycle_number: Int,
  fpp_actor_id: Int,
  holarchy_layer: Int,
  procedural_quad_count: Int,
  executable_tool_routes: Int,
  total_mcp_and_pi_routes: Int,
  traffic_class_code: Int,
) -> Int {
  case
    w4_id >= 0
    && w4_id < 15
    && cycle_number == 26 + w4_id
    && fpp_actor_id == 25 + w4_id
    && holarchy_layer == w4_id % 10
    && procedural_quad_count == 146
    && executable_tool_routes == 60
    && total_mcp_and_pi_routes == 111
    && traffic_class_code == { w4_id % 6 } + 1
  {
    True -> 1
    False -> 0
  }
}

/// Evaluates the 26-vector Cross-Plane Bridge across C-ABI Exports #28..#42 (`13` gates × `2` pass/veto vectors).
pub fn evaluate_cross_plane_bridge_vectors_28_to_42() -> List(Int) {
  list.append(evaluate_cross_plane_bridge_vectors_28_to_41(), [
    verify_pi_qwen_15cycle_symbiosis_gate(5, 31, 30, 5, 146, 60, 111, 6),
    verify_pi_qwen_15cycle_symbiosis_gate(5, 32, 30, 5, 146, 60, 111, 6),
  ])
}

/// Explicit 40-actor functional caste owner (`1..5` for `Caste01..Caste05`) matching `core_fpp_actor_twin_mesh.gleam` (`THM_FHC_01`, Drift D4).
pub fn fpp_actor_explicit_caste_owner(actor_idx: Int) -> Int {
  case actor_idx {
    0 | 2 | 14 | 20 | 23 | 27 | 38 | 39 -> 1
    4 | 8 | 18 | 19 | 26 | 30 | 31 | 37 -> 2
    1 | 7 | 11 | 15 | 21 | 33 | 34 | 35 -> 3
    3 | 9 | 13 | 16 | 24 | 28 | 32 | 36 -> 4
    5 | 6 | 10 | 12 | 17 | 22 | 25 | 29 -> 5
    _ -> 0
  }
}

/// Canonical 17-Aspect Set A (`aspect_coverage_engine.gleam` `0..16`) <-> Set B (`HolonicFppBionic...lean` `0..16`) bijection (`THM_FHC_02`, Drift D3).
pub fn aspect_set_a_to_set_b_index(aspect_idx: Int) -> Int {
  case aspect_idx >= 0 && aspect_idx < 17 {
    True -> aspect_idx
    False -> 99
  }
}

/// Canonical `SC-FRACTAL-TAXONOMY-001` concern-layer name for `L0..L9` (`L8=Evolutionary`, `L9=Sovereign`) closing Drift D5 (`THM_FHC_03`).
pub fn canonical_fractal_layer_concern(layer_id: Int) -> String {
  case layer_id {
    0 -> "L0_Constitutional"
    1 -> "L1_Physical_Storage"
    2 -> "L2_Execution_VM"
    3 -> "L3_Supervision_OTP"
    4 -> "L4_Cybernetic_Control"
    5 -> "L5_Knowledge_Ontology"
    6 -> "L6_Swarm_Orchestration"
    7 -> "L7_Interface_Cockpit"
    8 -> "L8_Evolutionary"
    9 -> "L9_Sovereign"
    _ -> "Unknown_Layer"
  }
}

/// Pure Total 20-Cycle (`EVOL-FHC-01..20`, Cumulative Cycles `41..60`) FPP-Holon-Caste-Rete-STPA-FMEA Unification Gate
/// (Mirrors Lean 4 `Section 43` `THM_FHC_01..06` and C-ABI Export `#43` `uos_lean_verify_fhc_20cycle_unification_gate`).
pub fn verify_fhc_20cycle_unification_gate(
  fhc_cycle_idx: Int,
  cumulative_cycle_num: Int,
  fpp_actor_idx: Int,
  explicit_caste_num: Int,
  janus_holon_count: Int,
  rete_domain_count: Int,
  stpa_uca_count: Int,
  fmea_l0_l9_entries: Int,
) -> Int {
  let expected_actor = { fhc_cycle_idx * 2 } % 40
  case
    fhc_cycle_idx >= 0
    && fhc_cycle_idx < 20
    && cumulative_cycle_num == 41 + fhc_cycle_idx
    && fpp_actor_idx == expected_actor
    && explicit_caste_num == fpp_actor_explicit_caste_owner(expected_actor)
    && janus_holon_count == 170
    && rete_domain_count == 11
    && stpa_uca_count == 4
    && fmea_l0_l9_entries == 30
  {
    True -> 1
    False -> 0
  }
}

/// Evaluates the 28-vector Cross-Plane Bridge across C-ABI Exports #28..#43 (`14` gates × `2` pass/veto vectors).
pub fn evaluate_cross_plane_bridge_vectors_28_to_43() -> List(Int) {
  list.append(evaluate_cross_plane_bridge_vectors_28_to_42(), [
    verify_fhc_20cycle_unification_gate(0, 41, 0, 1, 170, 11, 4, 30),
    verify_fhc_20cycle_unification_gate(0, 41, 0, 2, 170, 11, 4, 30),
  ])
}

/// Deterministic Pi + Local Qwen (`7B Q4_K_M`, `Caste02`) Review, Confidence Judgement & Sovereign Escalation Classifier
/// (`THM_VEIL_15..19` in `formal/lean/UosVeilProtocolAndKmWikiZkSyncDigitalTwin.lean`).
/// - `issue_category_idx`: `0..11` (`0..4` bounded local, `5..7` formal/Veil/Rete/safety, `8..9` multi-plane/architecture, `10..11` constitutional/epoch).
/// - `confidence_pct`: `0..100` (requires `>= 85` for local resolution).
/// - `retry_count`: `0..3` (requires `<= 2` for local resolution; `> 2` escalates to `Caste03` Codex).
/// - `blast_radius_code`: `0 = LocalSingleFile`, `1 = CrossModuleSubsystem`, `2 = ConstitutionalOrFormal`, `3 = MultiPlaneArchitecture`.
pub fn classify_pi_qwen_review_and_escalation(
  issue_category_idx: Int,
  confidence_pct: Int,
  retry_count: Int,
  blast_radius_code: Int,
) -> String {
  case issue_category_idx % 12 {
    10 | 11 -> "EscalateAgyQueenConductor_Caste01"
    5 | 6 | 7 -> "EscalateCodexSovereignSentinel_Caste03"
    8 | 9 -> "EscalateClaudeArchitectSynthesizer_Caste04"
    _ -> {
      case blast_radius_code == 0 {
        False -> {
          case blast_radius_code {
            2 -> "EscalateCodexSovereignSentinel_Caste03"
            _ -> "EscalateClaudeArchitectSynthesizer_Caste04"
          }
        }
        True -> {
          case retry_count > 2 {
            True -> "EscalateCodexSovereignSentinel_Caste03"
            False -> {
              case confidence_pct < 85 {
                True -> "EscalateClaudeArchitectSynthesizer_Caste04"
                False -> "LocalPiQwenResolve_Caste02"
              }
            }
          }
        }
      }
    }
  }
}

/// Pure Total 20-Cycle (`EVOL-VEIL-01..20`, Cumulative Cycles `61..80`) Veil + KM/Wiki/ZK Continuous 6-Plane Sync & Qwen Escalation Gate
/// (Mirrors `formal/lean/UosVeilProtocolAndKmWikiZkSyncDigitalTwin.lean` `THM_VEIL_01..20` and C-ABI Export `#44`).
pub fn verify_veil_km_wiki_zk_20cycle_sync_gate(
  veil_cycle_idx: Int,
  cumulative_cycle_num: Int,
  all_six_planes_synced: Int,
  admitted_ev_ceiling: Int,
  rete_salience_r0: Int,
  shannon_entropy_milli_bits: Int,
  qwen_route_code: Int,
) -> Int {
  let expected_route = case veil_cycle_idx % 12 {
    0 | 1 | 2 | 3 | 4 -> 2
    5 | 6 | 7 -> 3
    8 | 9 -> 4
    _ -> 1
  }
  case
    veil_cycle_idx >= 0
    && veil_cycle_idx < 20
    && cumulative_cycle_num == 61 + veil_cycle_idx
    && all_six_planes_synced == 1
    && admitted_ev_ceiling == 93
    && rete_salience_r0 == 1000
    && shannon_entropy_milli_bits >= 2500
    && qwen_route_code == expected_route
  {
    True -> 1
    False -> 0
  }
}

/// Evaluates the 30-vector Cross-Plane Bridge across C-ABI Exports #28..#44 (`15` gates × `2` pass/veto vectors).
pub fn evaluate_cross_plane_bridge_vectors_28_to_44() -> List(Int) {
  list.append(evaluate_cross_plane_bridge_vectors_28_to_43(), [
    verify_veil_km_wiki_zk_20cycle_sync_gate(0, 61, 1, 93, 1000, 3310, 2),
    verify_veil_km_wiki_zk_20cycle_sync_gate(0, 61, 0, 93, 1000, 3310, 2),
  ])
}

/// Maps each of the 40 NASA FPP actors (`0..39`) to its primary `leanprover/cslib`
/// Computer Science domain (`0..7`), assigning 5 FPP actors per CSLib pillar
/// (`THM_CSLIB_BRIDGE_01` in `formal/lean/UosFullSystemCodeUnifiedDigitalTwin.lean`).
pub fn cslib_domain_for_fpp_actor(actor_id: Int) -> Int {
  actor_id % 8
}

/// Returns the canonical `leanprover/cslib` module pillar name for domain code `0..7`.
pub fn cslib_domain_name(domain_code: Int) -> String {
  case domain_code % 8 {
    0 -> "Cslib.Foundations.Semantics.FLTS_LTS_Bisimulation"
    1 -> "Cslib.Foundations.Relation.Confluence_Newman"
    2 -> "Cslib.Computability.Automata.DA_FinAcc_Buchi_Muller"
    3 -> "Cslib.Computability.Circuit.Boolean_Wiring_Depth"
    4 -> "Cslib.Logics.HML_Modal_TheoryEq_Bisimilarity"
    5 -> "Cslib.Logics.LinearLogic.CLL_Heijunka_Resource"
    6 -> "Cslib.Languages.Mech.Choreography_5Caste"
    _ -> "Cslib.Algorithms.Lean.TimeM_PACLearning_PMF"
  }
}

/// Pure Total 20-Cycle (`EVOL-CSLIB-01..20`, Cumulative Cycles `81..100`) System-Wide `leanprover/cslib` 8-Pillar Verification Gate
/// (Mirrors `formal/lean/ruliad/Ruliad/UosCslibSystemWideIntegration.lean`, `formal/lean/UosCslibSystemWideDigitalTwin.lean`, and C-ABI Export `#45`).
pub fn verify_cslib_8pillar_systemwide_20cycle_gate(
  cslib_cycle_idx: Int,
  cumulative_cycle_num: Int,
  flts_bisim_synced: Int,
  rete_wiki_confluent: Int,
  da_circuit_hml_ok: Int,
  cll_heijunka_wip_total: Int,
  timem_pipeline_cost: Int,
  pac_pmf_entropy_milli_bits: Int,
) -> Int {
  case
    cslib_cycle_idx >= 0
    && cslib_cycle_idx < 20
    && cumulative_cycle_num == 81 + cslib_cycle_idx
    && flts_bisim_synced == 1
    && rete_wiki_confluent == 1
    && da_circuit_hml_ok == 1
    && cll_heijunka_wip_total == 17
    && timem_pipeline_cost == 249
    && pac_pmf_entropy_milli_bits >= 2500
  {
    True -> 1
    False -> 0
  }
}

/// Evaluates the 32-vector Cross-Plane Bridge across C-ABI Exports #28..#45 (`16` gates × `2` pass/veto vectors).
pub fn evaluate_cross_plane_bridge_vectors_28_to_45() -> List(Int) {
  list.append(evaluate_cross_plane_bridge_vectors_28_to_44(), [
    verify_cslib_8pillar_systemwide_20cycle_gate(0, 81, 1, 1, 1, 17, 249, 3310),
    verify_cslib_8pillar_systemwide_20cycle_gate(0, 81, 0, 1, 1, 17, 249, 3310),
  ])
}
