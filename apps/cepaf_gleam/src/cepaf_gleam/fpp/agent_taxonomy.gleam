//// =============================================================================
//// [UOS-C3I-AGENT-TAXONOMY] C3I SDLC, SRE & Verification Aerospace Agent Ecology
//// =============================================================================
//// Formal specification of all 48 canonical sovereign agent types created via
//// the FPP pure BEAM substrate across all 3 C3I pillars (SDLC, SRE, Verification)
//// and fractal layers (L0..L9), components, SRE resilience tiers, and evidence.
//// =============================================================================

import cepaf_gleam/fpp/domain.{
  type ComponentKind, type QueueFull, type SignalDef, type StateMachine, Active,
  Assert, Block, Drop, HierarchicalMachine, HierarchicalState, Queued, SignalDef,
  ToState, Transition,
}
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}

// =============================================================================
// Helper
// =============================================================================

fn make_signals(names: List(String)) -> List(SignalDef) {
  list.map(names, fn(n) { SignalDef(signal_name: n, signal_type: None) })
}

// =============================================================================
// Agent Kind Enumeration
// =============================================================================

// =============================================================================
// C3I Subsystem Classification Pillar
// =============================================================================

pub type C3iSystem {
  C3iSdlc
  C3iSre
  C3iVerification
}

pub fn c3i_system_to_string(sys: C3iSystem) -> String {
  case sys {
    C3iSdlc -> "C3I-SDLC"
    C3iSre -> "C3I-SRE"
    C3iVerification -> "C3I-VERIFICATION"
  }
}

pub fn string_to_c3i_system(s: String) -> Result(C3iSystem, Nil) {
  case s {
    "C3I-SDLC" -> Ok(C3iSdlc)
    "C3I-SRE" -> Ok(C3iSre)
    "C3I-VERIFICATION" -> Ok(C3iVerification)
    _ -> Error(Nil)
  }
}

pub type AgentKind {
  ConstitutionalGuardian
  DeterministicFlightController
  AvionicsTelemetry
  ParameterDatabase
  MissionPhaseHsm
  SreSentinel
  CyberneticImmune
  CognitiveOodaIntent
  SwarmMesh
  GroundGateway
  LivingMetaEvolution
  FormalOracle
  CockpitTelemetry
  PayloadScience
  StorageCustodian
  KmSync
  HardwareDriveInterlock
  RochaSemioticCutGuard
  DeterministicReductionScheduler
  SubstrateReactor
  LinearArenaReclaimer
  LocklessHamtStorage
  TaggedPointerGuard
  HierarchicalTimerWheel
  McdcAvionicsTap
  CrashWalReplay
  DifferentialBisimulation
  AppupHotReloadCoordinator
  SlmBifInference
  FastPatternFilter
  EpidemicGossip
  DynamicAgentBytecodeSynthesizer
  SdlcArchitectureSynthesizer
  SdlcContractCodeGenerator
  SdlcStaticAnalysisAuditor
  SdlcReleasePackagingOrchestrator
  SdlcDocumentationTransclusionSync
  SdlcEvolutionaryLoopGovernor
  SreLyapunovTrendDetector
  SreChaosFaultInjector
  SreFreshnessMonitor
  SreCpuBudgetGovernor
  VerificationChecklistAuditor
  VerificationMathGateCertifier
  VerificationNineModalityExecutor
  VerificationBrowserMatrixTester
  VerificationTcmCoordinateProtector
  VerificationZeroMudaPurityEnforcer
  SdlcGraphWorkflowOrchestrator
  SdlcSessionMemoryReplay
  SdlcA2aMultiAgentDelegation
  SdlcToolRegistryMcpBridge
  SdlcOntologyInfranodusSynthesizer
  SdlcDesignSystemFigmaBridge
  SdlcGospelOrtacSpecification
  SdlcAlgebraicAtlasRouter
  SreRunnerLifecycleHookSupervisor
  SrePluginPolicyGuardrail
  SreOpenTelemetrySpanTracer
  SreSaPlanTaskLeaser
  SreReteFailClosedAdmission
  SreForecastPredictivePreflight
  SreStpaSafetyController
  SreDatabaseActorWalSerializer
  VerificationAdkEvalBenchmark
  VerificationSimulationEnvironment
  VerificationLeanFormalProofOracle
  VerificationPinnedOtpDifferential
  VerificationMutationAdequacyKiller
  VerificationSheafGluingHarmonizer
  VerificationPlaywrightControlAuditor
  VerificationZkKmKnowledgeCurrency
}

pub fn agent_kind_to_string(kind: AgentKind) -> String {
  case kind {
    ConstitutionalGuardian -> "ConstitutionalGuardian"
    DeterministicFlightController -> "DeterministicFlightController"
    AvionicsTelemetry -> "AvionicsTelemetry"
    ParameterDatabase -> "ParameterDatabase"
    MissionPhaseHsm -> "MissionPhaseHsm"
    SreSentinel -> "SreSentinel"
    CyberneticImmune -> "CyberneticImmune"
    CognitiveOodaIntent -> "CognitiveOodaIntent"
    SwarmMesh -> "SwarmMesh"
    GroundGateway -> "GroundGateway"
    LivingMetaEvolution -> "LivingMetaEvolution"
    FormalOracle -> "FormalOracle"
    CockpitTelemetry -> "CockpitTelemetry"
    PayloadScience -> "PayloadScience"
    StorageCustodian -> "StorageCustodian"
    KmSync -> "KmSync"
    HardwareDriveInterlock -> "HardwareDriveInterlock"
    RochaSemioticCutGuard -> "RochaSemioticCutGuard"
    DeterministicReductionScheduler -> "DeterministicReductionScheduler"
    SubstrateReactor -> "SubstrateReactor"
    LinearArenaReclaimer -> "LinearArenaReclaimer"
    LocklessHamtStorage -> "LocklessHamtStorage"
    TaggedPointerGuard -> "TaggedPointerGuard"
    HierarchicalTimerWheel -> "HierarchicalTimerWheel"
    McdcAvionicsTap -> "McdcAvionicsTap"
    CrashWalReplay -> "CrashWalReplay"
    DifferentialBisimulation -> "DifferentialBisimulation"
    AppupHotReloadCoordinator -> "AppupHotReloadCoordinator"
    SlmBifInference -> "SlmBifInference"
    FastPatternFilter -> "FastPatternFilter"
    EpidemicGossip -> "EpidemicGossip"
    DynamicAgentBytecodeSynthesizer -> "DynamicAgentBytecodeSynthesizer"
    SdlcArchitectureSynthesizer -> "SdlcArchitectureSynthesizer"
    SdlcContractCodeGenerator -> "SdlcContractCodeGenerator"
    SdlcStaticAnalysisAuditor -> "SdlcStaticAnalysisAuditor"
    SdlcReleasePackagingOrchestrator -> "SdlcReleasePackagingOrchestrator"
    SdlcDocumentationTransclusionSync -> "SdlcDocumentationTransclusionSync"
    SdlcEvolutionaryLoopGovernor -> "SdlcEvolutionaryLoopGovernor"
    SreLyapunovTrendDetector -> "SreLyapunovTrendDetector"
    SreChaosFaultInjector -> "SreChaosFaultInjector"
    SreFreshnessMonitor -> "SreFreshnessMonitor"
    SreCpuBudgetGovernor -> "SreCpuBudgetGovernor"
    VerificationChecklistAuditor -> "VerificationChecklistAuditor"
    VerificationMathGateCertifier -> "VerificationMathGateCertifier"
    VerificationNineModalityExecutor -> "VerificationNineModalityExecutor"
    VerificationBrowserMatrixTester -> "VerificationBrowserMatrixTester"
    VerificationTcmCoordinateProtector -> "VerificationTcmCoordinateProtector"
    VerificationZeroMudaPurityEnforcer -> "VerificationZeroMudaPurityEnforcer"
    SdlcGraphWorkflowOrchestrator -> "SdlcGraphWorkflowOrchestrator"
    SdlcSessionMemoryReplay -> "SdlcSessionMemoryReplay"
    SdlcA2aMultiAgentDelegation -> "SdlcA2aMultiAgentDelegation"
    SdlcToolRegistryMcpBridge -> "SdlcToolRegistryMcpBridge"
    SdlcOntologyInfranodusSynthesizer -> "SdlcOntologyInfranodusSynthesizer"
    SdlcDesignSystemFigmaBridge -> "SdlcDesignSystemFigmaBridge"
    SdlcGospelOrtacSpecification -> "SdlcGospelOrtacSpecification"
    SdlcAlgebraicAtlasRouter -> "SdlcAlgebraicAtlasRouter"
    SreRunnerLifecycleHookSupervisor -> "SreRunnerLifecycleHookSupervisor"
    SrePluginPolicyGuardrail -> "SrePluginPolicyGuardrail"
    SreOpenTelemetrySpanTracer -> "SreOpenTelemetrySpanTracer"
    SreSaPlanTaskLeaser -> "SreSaPlanTaskLeaser"
    SreReteFailClosedAdmission -> "SreReteFailClosedAdmission"
    SreForecastPredictivePreflight -> "SreForecastPredictivePreflight"
    SreStpaSafetyController -> "SreStpaSafetyController"
    SreDatabaseActorWalSerializer -> "SreDatabaseActorWalSerializer"
    VerificationAdkEvalBenchmark -> "VerificationAdkEvalBenchmark"
    VerificationSimulationEnvironment -> "VerificationSimulationEnvironment"
    VerificationLeanFormalProofOracle -> "VerificationLeanFormalProofOracle"
    VerificationPinnedOtpDifferential -> "VerificationPinnedOtpDifferential"
    VerificationMutationAdequacyKiller -> "VerificationMutationAdequacyKiller"
    VerificationSheafGluingHarmonizer -> "VerificationSheafGluingHarmonizer"
    VerificationPlaywrightControlAuditor ->
      "VerificationPlaywrightControlAuditor"
    VerificationZkKmKnowledgeCurrency -> "VerificationZkKmKnowledgeCurrency"
  }
}

pub fn string_to_agent_kind(s: String) -> Result(AgentKind, Nil) {
  case s {
    "ConstitutionalGuardian" -> Ok(ConstitutionalGuardian)
    "DeterministicFlightController" -> Ok(DeterministicFlightController)
    "AvionicsTelemetry" -> Ok(AvionicsTelemetry)
    "ParameterDatabase" -> Ok(ParameterDatabase)
    "MissionPhaseHsm" -> Ok(MissionPhaseHsm)
    "SreSentinel" -> Ok(SreSentinel)
    "CyberneticImmune" -> Ok(CyberneticImmune)
    "CognitiveOodaIntent" -> Ok(CognitiveOodaIntent)
    "SwarmMesh" -> Ok(SwarmMesh)
    "GroundGateway" -> Ok(GroundGateway)
    "LivingMetaEvolution" -> Ok(LivingMetaEvolution)
    "FormalOracle" -> Ok(FormalOracle)
    "CockpitTelemetry" -> Ok(CockpitTelemetry)
    "PayloadScience" -> Ok(PayloadScience)
    "StorageCustodian" -> Ok(StorageCustodian)
    "KmSync" -> Ok(KmSync)
    "HardwareDriveInterlock" -> Ok(HardwareDriveInterlock)
    "RochaSemioticCutGuard" -> Ok(RochaSemioticCutGuard)
    "DeterministicReductionScheduler" -> Ok(DeterministicReductionScheduler)
    "SubstrateReactor" -> Ok(SubstrateReactor)
    "LinearArenaReclaimer" -> Ok(LinearArenaReclaimer)
    "LocklessHamtStorage" -> Ok(LocklessHamtStorage)
    "TaggedPointerGuard" -> Ok(TaggedPointerGuard)
    "HierarchicalTimerWheel" -> Ok(HierarchicalTimerWheel)
    "McdcAvionicsTap" -> Ok(McdcAvionicsTap)
    "CrashWalReplay" -> Ok(CrashWalReplay)
    "DifferentialBisimulation" -> Ok(DifferentialBisimulation)
    "AppupHotReloadCoordinator" -> Ok(AppupHotReloadCoordinator)
    "SlmBifInference" -> Ok(SlmBifInference)
    "FastPatternFilter" -> Ok(FastPatternFilter)
    "EpidemicGossip" -> Ok(EpidemicGossip)
    "DynamicAgentBytecodeSynthesizer" -> Ok(DynamicAgentBytecodeSynthesizer)
    "SdlcArchitectureSynthesizer" -> Ok(SdlcArchitectureSynthesizer)
    "SdlcContractCodeGenerator" -> Ok(SdlcContractCodeGenerator)
    "SdlcStaticAnalysisAuditor" -> Ok(SdlcStaticAnalysisAuditor)
    "SdlcReleasePackagingOrchestrator" -> Ok(SdlcReleasePackagingOrchestrator)
    "SdlcDocumentationTransclusionSync" -> Ok(SdlcDocumentationTransclusionSync)
    "SdlcEvolutionaryLoopGovernor" -> Ok(SdlcEvolutionaryLoopGovernor)
    "SreLyapunovTrendDetector" -> Ok(SreLyapunovTrendDetector)
    "SreChaosFaultInjector" -> Ok(SreChaosFaultInjector)
    "SreFreshnessMonitor" -> Ok(SreFreshnessMonitor)
    "SreCpuBudgetGovernor" -> Ok(SreCpuBudgetGovernor)
    "VerificationChecklistAuditor" -> Ok(VerificationChecklistAuditor)
    "VerificationMathGateCertifier" -> Ok(VerificationMathGateCertifier)
    "VerificationNineModalityExecutor" -> Ok(VerificationNineModalityExecutor)
    "VerificationBrowserMatrixTester" -> Ok(VerificationBrowserMatrixTester)
    "VerificationTcmCoordinateProtector" ->
      Ok(VerificationTcmCoordinateProtector)
    "VerificationZeroMudaPurityEnforcer" ->
      Ok(VerificationZeroMudaPurityEnforcer)
    "SdlcGraphWorkflowOrchestrator" -> Ok(SdlcGraphWorkflowOrchestrator)
    "SdlcSessionMemoryReplay" -> Ok(SdlcSessionMemoryReplay)
    "SdlcA2aMultiAgentDelegation" -> Ok(SdlcA2aMultiAgentDelegation)
    "SdlcToolRegistryMcpBridge" -> Ok(SdlcToolRegistryMcpBridge)
    "SdlcOntologyInfranodusSynthesizer" -> Ok(SdlcOntologyInfranodusSynthesizer)
    "SdlcDesignSystemFigmaBridge" -> Ok(SdlcDesignSystemFigmaBridge)
    "SdlcGospelOrtacSpecification" -> Ok(SdlcGospelOrtacSpecification)
    "SdlcAlgebraicAtlasRouter" -> Ok(SdlcAlgebraicAtlasRouter)
    "SreRunnerLifecycleHookSupervisor" -> Ok(SreRunnerLifecycleHookSupervisor)
    "SrePluginPolicyGuardrail" -> Ok(SrePluginPolicyGuardrail)
    "SreOpenTelemetrySpanTracer" -> Ok(SreOpenTelemetrySpanTracer)
    "SreSaPlanTaskLeaser" -> Ok(SreSaPlanTaskLeaser)
    "SreReteFailClosedAdmission" -> Ok(SreReteFailClosedAdmission)
    "SreForecastPredictivePreflight" -> Ok(SreForecastPredictivePreflight)
    "SreStpaSafetyController" -> Ok(SreStpaSafetyController)
    "SreDatabaseActorWalSerializer" -> Ok(SreDatabaseActorWalSerializer)
    "VerificationAdkEvalBenchmark" -> Ok(VerificationAdkEvalBenchmark)
    "VerificationSimulationEnvironment" -> Ok(VerificationSimulationEnvironment)
    "VerificationLeanFormalProofOracle" -> Ok(VerificationLeanFormalProofOracle)
    "VerificationPinnedOtpDifferential" -> Ok(VerificationPinnedOtpDifferential)
    "VerificationMutationAdequacyKiller" ->
      Ok(VerificationMutationAdequacyKiller)
    "VerificationSheafGluingHarmonizer" -> Ok(VerificationSheafGluingHarmonizer)
    "VerificationPlaywrightControlAuditor" ->
      Ok(VerificationPlaywrightControlAuditor)
    "VerificationZkKmKnowledgeCurrency" -> Ok(VerificationZkKmKnowledgeCurrency)
    _ -> Error(Nil)
  }
}

// =============================================================================
// Agent Specification
// =============================================================================

pub type AgentTypeSpec {
  AgentTypeSpec(
    kind: AgentKind,
    name: String,
    c3i_system: C3iSystem,
    fractal_layer: Int,
    fractal_tag: String,
    fpp_component_kind: ComponentKind,
    base_id: Int,
    id_span: Int,
    queue_policy: QueueFull,
    description: String,
    operational_domain: String,
    sdlc_phase: String,
    sre_resilience_tier: String,
    evidence_contracts: List(String),
    hsm_machine: StateMachine,
  )
}

// =============================================================================
// Canonical Agent Type Builders
// =============================================================================

fn build_guardian_spec() -> AgentTypeSpec {
  let standby =
    HierarchicalState(
      name: "Standby",
      parent: Some("Operational"),
      entry: ["guardian_standby_entered"],
      exit: ["guardian_standby_exited"],
      transitions: [
        Transition(
          on_signal: "evaluate_intent",
          guard: None,
          do_actions: ["verify_safety_invariants"],
          target: ToState("Verifying"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let verifying =
    HierarchicalState(
      name: "Verifying",
      parent: Some("Operational"),
      entry: ["guardian_verifying_entered"],
      exit: ["guardian_verifying_exited"],
      transitions: [
        Transition(
          on_signal: "consensus_pass",
          guard: None,
          do_actions: ["grant_authorization"],
          target: ToState("Approved"),
        ),
        Transition(
          on_signal: "violation_detected",
          guard: None,
          do_actions: ["trip_safety_veto"],
          target: ToState("VetoTripped"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let approved =
    HierarchicalState(
      name: "Approved",
      parent: Some("Operational"),
      entry: ["guardian_approved_entered"],
      exit: ["guardian_approved_exited"],
      transitions: [
        Transition(
          on_signal: "cycle_complete",
          guard: None,
          do_actions: ["reset_evaluator"],
          target: ToState("Standby"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let operational =
    HierarchicalState(
      name: "Operational",
      parent: None,
      entry: ["guardian_operational_entered"],
      exit: ["guardian_operational_exited"],
      transitions: [
        Transition(
          on_signal: "fatal_hardware_violation",
          guard: None,
          do_actions: ["emergency_lockdown"],
          target: ToState("VetoTripped"),
        ),
      ],
      sub_states: [standby, verifying, approved],
      initial_sub_state: Some("Standby"),
    )

  let veto_tripped =
    HierarchicalState(
      name: "VetoTripped",
      parent: None,
      entry: ["fail_closed_halt"],
      exit: ["operator_override_exit"],
      transitions: [
        Transition(
          on_signal: "operator_reset",
          guard: None,
          do_actions: ["clear_veto"],
          target: ToState("Standby"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "GuardianHSM",
      signals: make_signals([
        "evaluate_intent", "consensus_pass", "violation_detected",
        "cycle_complete", "fatal_hardware_violation", "operator_reset",
      ]),
      guards: ["is_two_key_approved", "is_os_nvme_target"],
      actions: [
        "verify_safety_invariants", "grant_authorization", "trip_safety_veto",
        "reset_evaluator", "emergency_lockdown", "clear_veto",
      ],
      root_states: [operational, veto_tripped],
      choices: [],
      initial: #([], "Operational"),
    )

  AgentTypeSpec(
    kind: ConstitutionalGuardian,
    name: "C3I Verification Constitutional Guardian Agent",
    c3i_system: C3iVerification,
    fractal_layer: 0,
    fractal_tag: "#fractal-l0",
    fpp_component_kind: Active,
    base_id: 0x1000,
    id_span: 64,
    queue_policy: Assert,
    description: "Enforces Psi-0..5 invariants, DAL-A hardware interlock on OS NVMe 25503L801736, and 2oo3 constitutional consensus.",
    operational_domain: "Constitutional Safety & Governance",
    sdlc_phase: "Verification & Gatekeeping",
    sre_resilience_tier: "SIL-6 / Fail-Closed",
    evidence_contracts: [
      "SC-CHECKLIST-001", "SC-STORAGE-001", "SC-FPP-INTENT-001",
    ],
    hsm_machine: hsm,
  )
}

fn build_flight_controller_spec() -> AgentTypeSpec {
  let disarmed =
    HierarchicalState(
      name: "Disarmed",
      parent: Some("FlightState"),
      entry: ["controller_disarmed"],
      exit: ["controller_arming"],
      transitions: [
        Transition(
          on_signal: "arm_controller",
          guard: None,
          do_actions: ["enable_actuators"],
          target: ToState("Armed"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let armed =
    HierarchicalState(
      name: "Armed",
      parent: Some("FlightState"),
      entry: ["controller_armed"],
      exit: ["controller_launching"],
      transitions: [
        Transition(
          on_signal: "engage_trajectory",
          guard: None,
          do_actions: ["execute_rate_group"],
          target: ToState("TrajectoryActive"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let trajectory_active =
    HierarchicalState(
      name: "TrajectoryActive",
      parent: Some("FlightState"),
      entry: ["controller_tracking"],
      exit: ["controller_stopping"],
      transitions: [
        Transition(
          on_signal: "disengage",
          guard: None,
          do_actions: ["standby_actuators"],
          target: ToState("Disarmed"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let flight_state =
    HierarchicalState(
      name: "FlightState",
      parent: None,
      entry: ["flight_subsystem_init"],
      exit: ["flight_subsystem_shutdown"],
      transitions: [
        Transition(
          on_signal: "emergency_stop",
          guard: None,
          do_actions: ["cut_power"],
          target: ToState("EmergencyHalt"),
        ),
      ],
      sub_states: [disarmed, armed, trajectory_active],
      initial_sub_state: Some("Disarmed"),
    )

  let emergency_halt =
    HierarchicalState(
      name: "EmergencyHalt",
      parent: None,
      entry: ["halt_controller"],
      exit: ["reboot_controller"],
      transitions: [
        Transition(
          on_signal: "reboot",
          guard: None,
          do_actions: ["warm_boot"],
          target: ToState("FlightState"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "FlightControllerHSM",
      signals: make_signals([
        "arm_controller", "engage_trajectory", "disengage", "emergency_stop",
        "reboot",
      ]),
      guards: ["actuators_nominal"],
      actions: [
        "enable_actuators", "execute_rate_group", "standby_actuators",
        "cut_power", "warm_boot",
      ],
      root_states: [flight_state, emergency_halt],
      choices: [],
      initial: #([], "FlightState"),
    )

  AgentTypeSpec(
    kind: DeterministicFlightController,
    name: "C3I Verification Deterministic Flight Controller Agent",
    c3i_system: C3iVerification,
    fractal_layer: 1,
    fractal_tag: "#fractal-l1",
    fpp_component_kind: Active,
    base_id: 0x1040,
    id_span: 64,
    queue_policy: Block,
    description: "Sub-millisecond periodic command execution, actuator trajectory dispatching, and hardware register bridging.",
    operational_domain: "Avionics Real-Time Control",
    sdlc_phase: "Execution & Flight Runtime",
    sre_resilience_tier: "SIL-4 / Real-Time Bounded",
    evidence_contracts: ["SC-FPP-002", "SC-TCM-001"],
    hsm_machine: hsm,
  )
}

fn build_telemetry_spec() -> AgentTypeSpec {
  let idle =
    HierarchicalState(
      name: "Idle",
      parent: None,
      entry: ["tlm_idle"],
      exit: ["tlm_start_sampling"],
      transitions: [
        Transition(
          on_signal: "tick_sample",
          guard: None,
          do_actions: ["sample_channels"],
          target: ToState("Packetizing"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let packetizing =
    HierarchicalState(
      name: "Packetizing",
      parent: None,
      entry: ["tlm_packetizing"],
      exit: ["tlm_emit_frame"],
      transitions: [
        Transition(
          on_signal: "flush_packet",
          guard: None,
          do_actions: ["serialize_ccsds"],
          target: ToState("Idle"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "TelemetryHSM",
      signals: make_signals(["tick_sample", "flush_packet"]),
      guards: [],
      actions: ["sample_channels", "serialize_ccsds"],
      root_states: [idle, packetizing],
      choices: [],
      initial: #([], "Idle"),
    )

  AgentTypeSpec(
    kind: AvionicsTelemetry,
    name: "C3I Verification Avionics Telemetry Stream Agent",
    c3i_system: C3iVerification,
    fractal_layer: 2,
    fractal_tag: "#fractal-l2",
    fpp_component_kind: Active,
    base_id: 0x1080,
    id_span: 64,
    queue_policy: Drop,
    description: "Aggregates channel samples, generates CCSDS-compatible packets, and streams telemetry over Zenoh/WebSocket.",
    operational_domain: "Telemetry & Observability",
    sdlc_phase: "Telemetry Streaming",
    sre_resilience_tier: "SIL-2 / Non-Blocking",
    evidence_contracts: ["SC-FPP-005", "SC-OTEL-001"],
    hsm_machine: hsm,
  )
}

fn build_prm_db_spec() -> AgentTypeSpec {
  let ready =
    HierarchicalState(
      name: "Ready",
      parent: None,
      entry: ["prm_db_ready"],
      exit: ["prm_db_updating"],
      transitions: [
        Transition(
          on_signal: "set_param",
          guard: None,
          do_actions: ["validate_range", "write_slot"],
          target: ToState("Ready"),
        ),
        Transition(
          on_signal: "save_all",
          guard: None,
          do_actions: ["flush_non_volatile"],
          target: ToState("Saved"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let saved =
    HierarchicalState(
      name: "Saved",
      parent: None,
      entry: ["prm_db_saved"],
      exit: ["prm_db_resume"],
      transitions: [
        Transition(
          on_signal: "resume",
          guard: None,
          do_actions: [],
          target: ToState("Ready"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "PrmDbHSM",
      signals: make_signals(["set_param", "save_all", "resume"]),
      guards: ["param_in_range"],
      actions: ["validate_range", "write_slot", "flush_non_volatile"],
      root_states: [ready, saved],
      choices: [],
      initial: #([], "Ready"),
    )

  AgentTypeSpec(
    kind: ParameterDatabase,
    name: "C3I SDLC Parameter Database Custodian Agent",
    c3i_system: C3iSdlc,
    fractal_layer: 2,
    fractal_tag: "#fractal-l2",
    fpp_component_kind: Queued,
    base_id: 0x10C0,
    id_span: 64,
    queue_policy: Block,
    description: "Implements Svc::PrmDb parameter updates, boundary validation, non-volatile slot commits, and ground station synchronization.",
    operational_domain: "Parameter Management & Storage",
    sdlc_phase: "Configuration & Calibration",
    sre_resilience_tier: "SIL-3 / ACID Persistent",
    evidence_contracts: ["SC-FPP-004", "SC-DMC-001"],
    hsm_machine: hsm,
  )
}

fn build_mission_phase_spec() -> AgentTypeSpec {
  let pre_launch =
    HierarchicalState(
      name: "PreLaunch",
      parent: Some("MissionLifecycle"),
      entry: ["prelaunch_checks"],
      exit: ["countdown_complete"],
      transitions: [
        Transition(
          on_signal: "launch",
          guard: None,
          do_actions: ["ignite_ascent"],
          target: ToState("Ascent"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let ascent =
    HierarchicalState(
      name: "Ascent",
      parent: Some("MissionLifecycle"),
      entry: ["ascent_guidance"],
      exit: ["meco_achieved"],
      transitions: [
        Transition(
          on_signal: "meco",
          guard: None,
          do_actions: ["stage_separation"],
          target: ToState("NominalScience"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let nominal_science =
    HierarchicalState(
      name: "NominalScience",
      parent: Some("MissionLifecycle"),
      entry: ["deploy_instruments"],
      exit: ["stow_instruments"],
      transitions: [
        Transition(
          on_signal: "anomaly",
          guard: None,
          do_actions: ["enter_safe_hold"],
          target: ToState("SafeHold"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let mission_lifecycle =
    HierarchicalState(
      name: "MissionLifecycle",
      parent: None,
      entry: ["mission_clock_start"],
      exit: ["mission_end"],
      transitions: [],
      sub_states: [pre_launch, ascent, nominal_science],
      initial_sub_state: Some("PreLaunch"),
    )

  let safe_hold =
    HierarchicalState(
      name: "SafeHold",
      parent: None,
      entry: ["sun_point_panels"],
      exit: ["telemetry_diagnostics_cleared"],
      transitions: [
        Transition(
          on_signal: "recovery_pass",
          guard: None,
          do_actions: ["resume_mission"],
          target: ToState("NominalScience"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "MissionPhaseHSM",
      signals: make_signals(["launch", "meco", "anomaly", "recovery_pass"]),
      guards: ["orbit_stable"],
      actions: [
        "ignite_ascent", "stage_separation", "enter_safe_hold", "resume_mission",
      ],
      root_states: [mission_lifecycle, safe_hold],
      choices: [],
      initial: #([], "MissionLifecycle"),
    )

  AgentTypeSpec(
    kind: MissionPhaseHsm,
    name: "C3I SDLC Mission Phase Orchestrator Agent",
    c3i_system: C3iSdlc,
    fractal_layer: 3,
    fractal_tag: "#fractal-l3",
    fpp_component_kind: Active,
    base_id: 0x1100,
    id_span: 64,
    queue_policy: Assert,
    description: "Complex spacecraft operational phase management using David Harel HSM LCA transitions and nested fault handling.",
    operational_domain: "Mission Phase Autonomy",
    sdlc_phase: "Mission Orchestration",
    sre_resilience_tier: "SIL-5 / Critical Autonomous",
    evidence_contracts: ["SC-FPP-003", "SC-TCM-001"],
    hsm_machine: hsm,
  )
}

fn build_sre_sentinel_spec() -> AgentTypeSpec {
  let observing =
    HierarchicalState(
      name: "Observing",
      parent: None,
      entry: ["sre_start_tick"],
      exit: ["sre_window_ready"],
      transitions: [
        Transition(
          on_signal: "window_elapsed",
          guard: None,
          do_actions: ["compute_lyapunov_exponent"],
          target: ToState("Observing"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "SreSentinelHSM",
      signals: make_signals(["window_elapsed"]),
      guards: [],
      actions: ["compute_lyapunov_exponent"],
      root_states: [observing],
      choices: [],
      initial: #([], "Observing"),
    )

  AgentTypeSpec(
    kind: SreSentinel,
    name: "C3I SRE Sentinel Health & Circuit Breaker Agent",
    c3i_system: C3iSre,
    fractal_layer: 4,
    fractal_tag: "#fractal-l4",
    fpp_component_kind: Active,
    base_id: 0x1140,
    id_span: 64,
    queue_policy: Drop,
    description: "Real-time rate-group deadline monitoring, Lyapunov exponential decay tracking (lambda <= -0.05), and MTTR enforcement.",
    operational_domain: "SRE & Resilience Telemetry",
    sdlc_phase: "Operations & Reliability",
    sre_resilience_tier: "SIL-4 / Real-Time Watchdog",
    evidence_contracts: ["SC-CHECKLIST-001", "SC-MATH-001"],
    hsm_machine: hsm,
  )
}

fn build_cybernetic_immune_spec() -> AgentTypeSpec {
  let monitoring =
    HierarchicalState(
      name: "Monitoring",
      parent: None,
      entry: ["immune_monitoring"],
      exit: ["immune_anomaly_seen"],
      transitions: [
        Transition(
          on_signal: "isolate_fault",
          guard: None,
          do_actions: ["trip_circuit_breaker"],
          target: ToState("FaultIsolated"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let fault_isolated =
    HierarchicalState(
      name: "FaultIsolated",
      parent: None,
      entry: ["immune_isolated"],
      exit: ["immune_synthesize_antibody"],
      transitions: [
        Transition(
          on_signal: "synthesize_fix",
          guard: None,
          do_actions: ["reset_breaker"],
          target: ToState("Monitoring"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "CyberneticImmuneHSM",
      signals: make_signals(["isolate_fault", "synthesize_fix"]),
      guards: [],
      actions: ["trip_circuit_breaker", "reset_breaker"],
      root_states: [monitoring, fault_isolated],
      choices: [],
      initial: #([], "Monitoring"),
    )

  AgentTypeSpec(
    kind: CyberneticImmune,
    name: "C3I SRE Cybernetic Immune Self-Healing Agent",
    c3i_system: C3iSre,
    fractal_layer: 4,
    fractal_tag: "#fractal-l4",
    fpp_component_kind: Active,
    base_id: 0x1180,
    id_span: 64,
    queue_policy: Block,
    description: "Fault Detection, Isolation, and Recovery (FDIR); Prajna 3-state circuit breaker tripping and automated recovery within HSM substates.",
    operational_domain: "Cybernetic Self-Healing",
    sdlc_phase: "Immune Response & Self-Healing",
    sre_resilience_tier: "SIL-5 / Auto-Remediating",
    evidence_contracts: ["SC-PRAJNA-001", "SC-LYAPUNOV-001"],
    hsm_machine: hsm,
  )
}

fn build_cognitive_ooda_spec() -> AgentTypeSpec {
  let observe =
    HierarchicalState(
      name: "Observe",
      parent: None,
      entry: ["ingest_telemetry_sheaf"],
      exit: ["sheaf_ready"],
      transitions: [
        Transition(
          on_signal: "orient",
          guard: None,
          do_actions: ["evaluate_rete_rules"],
          target: ToState("Orient"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let orient =
    HierarchicalState(
      name: "Orient",
      parent: None,
      entry: ["knowledge_lookup"],
      exit: ["context_bound"],
      transitions: [
        Transition(
          on_signal: "decide",
          guard: None,
          do_actions: ["formulate_intent"],
          target: ToState("Decide"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let decide =
    HierarchicalState(
      name: "Decide",
      parent: None,
      entry: ["intent_generation"],
      exit: ["intent_sealed"],
      transitions: [
        Transition(
          on_signal: "act",
          guard: None,
          do_actions: ["dispatch_flight_intent"],
          target: ToState("Observe"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "CognitiveOodaHSM",
      signals: make_signals(["orient", "decide", "act"]),
      guards: [],
      actions: [
        "evaluate_rete_rules", "formulate_intent", "dispatch_flight_intent",
      ],
      root_states: [observe, orient, decide],
      choices: [],
      initial: #([], "Observe"),
    )

  AgentTypeSpec(
    kind: CognitiveOodaIntent,
    name: "C3I SDLC Cognitive OODA Intent Arbiter Agent",
    c3i_system: C3iSdlc,
    fractal_layer: 5,
    fractal_tag: "#fractal-l5",
    fpp_component_kind: Active,
    base_id: 0x11C0,
    id_span: 64,
    queue_policy: Block,
    description: "Autonomous decision-making using telemetry sheaf inputs, ontology Rete rules, and generating typed Denotational Flight Intents.",
    operational_domain: "Cognitive Decision & OODA",
    sdlc_phase: "Autonomous Planning",
    sre_resilience_tier: "SIL-4 / Gated Intent",
    evidence_contracts: ["SC-FPP-INTENT-001", "SC-ROCHA-001"],
    hsm_machine: hsm,
  )
}

fn build_swarm_mesh_spec() -> AgentTypeSpec {
  let sync =
    HierarchicalState(
      name: "MeshSync",
      parent: None,
      entry: ["swarm_sync"],
      exit: ["swarm_synced"],
      transitions: [
        Transition(
          on_signal: "vote",
          guard: None,
          do_actions: ["run_paxos_vote"],
          target: ToState("MeshSync"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "SwarmMeshHSM",
      signals: make_signals(["vote"]),
      guards: [],
      actions: ["run_paxos_vote"],
      root_states: [sync],
      choices: [],
      initial: #([], "MeshSync"),
    )

  AgentTypeSpec(
    kind: SwarmMesh,
    name: "C3I SRE Swarm Mesh Topology Coordinator Agent",
    c3i_system: C3iSre,
    fractal_layer: 6,
    fractal_tag: "#fractal-l6",
    fpp_component_kind: Active,
    base_id: 0x1200,
    id_span: 64,
    queue_policy: Drop,
    description: "Peer-to-peer A2A coordination across distributed nodes, sheaf restriction maps, and boundary agreement verification.",
    operational_domain: "Distributed Swarm Consensus",
    sdlc_phase: "Ecosystem Coordination",
    sre_resilience_tier: "SIL-3 / Partition Tolerant",
    evidence_contracts: ["SC-FPP-004", "SC-ZENOH-001"],
    hsm_machine: hsm,
  )
}

fn build_ground_gateway_spec() -> AgentTypeSpec {
  let awaiting =
    HierarchicalState(
      name: "PassAwaiting",
      parent: None,
      entry: ["gateway_standby"],
      exit: ["gateway_pass_open"],
      transitions: [
        Transition(
          on_signal: "start_pass",
          guard: None,
          do_actions: ["open_rf_stream"],
          target: ToState("PassAwaiting"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "GroundGatewayHSM",
      signals: make_signals(["start_pass"]),
      guards: [],
      actions: ["open_rf_stream"],
      root_states: [awaiting],
      choices: [],
      initial: #([], "PassAwaiting"),
    )

  AgentTypeSpec(
    kind: GroundGateway,
    name: "C3I SRE Ground Uplink & Downlink Gateway Agent",
    c3i_system: C3iSre,
    fractal_layer: 7,
    fractal_tag: "#fractal-l7",
    fpp_component_kind: Active,
    base_id: 0x1240,
    id_span: 64,
    queue_policy: Block,
    description: "CCSDS Space Packet Protocol decoding, Delay-Tolerant Networking (DTN) bundle storage, ground dictionary schema binding.",
    operational_domain: "Deep Space Communications",
    sdlc_phase: "Uplink/Downlink Gateway",
    sre_resilience_tier: "SIL-4 / DTN Bounded",
    evidence_contracts: ["SC-FPP-006", "SC-TAILSCALE-WEB-001"],
    hsm_machine: hsm,
  )
}

fn build_living_meta_spec() -> AgentTypeSpec {
  let introspect =
    HierarchicalState(
      name: "Introspecting",
      parent: None,
      entry: ["audit_nodes"],
      exit: ["nodes_verified"],
      transitions: [
        Transition(
          on_signal: "evolve_ontology",
          guard: None,
          do_actions: ["verify_topological_closure"],
          target: ToState("Introspecting"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "LivingMetaEvolutionHSM",
      signals: make_signals(["evolve_ontology"]),
      guards: [],
      actions: ["verify_topological_closure"],
      root_states: [introspect],
      choices: [],
      initial: #([], "Introspecting"),
    )

  AgentTypeSpec(
    kind: LivingMetaEvolution,
    name: "C3I SDLC Living Meta-Evolution Supervisor Agent",
    c3i_system: C3iSdlc,
    fractal_layer: 9,
    fractal_tag: "#fractal-l9",
    fpp_component_kind: Active,
    base_id: 0x1280,
    id_span: 64,
    queue_policy: Assert,
    description: "Dynamic ontology schema validation, 5-tier algebraic atlas verification, and topological closure maintenance.",
    operational_domain: "Meta-System Evolution & Governance",
    sdlc_phase: "Meta-Evolution & Hot-Reloading",
    sre_resilience_tier: "SIL-6 / Sovereign Core",
    evidence_contracts: ["SC-ONTO-001", "SC-FPP-004"],
    hsm_machine: hsm,
  )
}

fn build_formal_oracle_spec() -> AgentTypeSpec {
  let verifying =
    HierarchicalState(
      name: "Verifying",
      parent: None,
      entry: ["load_gospel_contracts"],
      exit: ["contracts_checked"],
      transitions: [
        Transition(
          on_signal: "query_z3",
          guard: None,
          do_actions: ["execute_bounded_smt"],
          target: ToState("Verifying"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "FormalOracleHSM",
      signals: make_signals(["query_z3"]),
      guards: [],
      actions: ["execute_bounded_smt"],
      root_states: [verifying],
      choices: [],
      initial: #([], "Verifying"),
    )

  AgentTypeSpec(
    kind: FormalOracle,
    name: "C3I Verification Formal Gospel & Z3 Oracle Agent",
    c3i_system: C3iVerification,
    fractal_layer: 0,
    fractal_tag: "#fractal-l0",
    fpp_component_kind: Active,
    base_id: 0x12C0,
    id_span: 64,
    queue_policy: Assert,
    description: "Gospel specification verification, bounded Z3 SMT queries, OCaml differential oracle parity checking, and two-key verification.",
    operational_domain: "Formal Verification & Proofs",
    sdlc_phase: "Formal Mathematical Proof",
    sre_resilience_tier: "SIL-6 / Zero-Defect",
    evidence_contracts: ["SC-LEAN-001", "SC-GOSPEL-001"],
    hsm_machine: hsm,
  )
}

fn build_cockpit_telemetry_spec() -> AgentTypeSpec {
  let streaming =
    HierarchicalState(
      name: "Streaming",
      parent: None,
      entry: ["cockpit_poll"],
      exit: ["cockpit_rendered"],
      transitions: [
        Transition(
          on_signal: "flush_ui",
          guard: None,
          do_actions: ["render_lustre_mvu"],
          target: ToState("Streaming"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "CockpitTelemetryHSM",
      signals: make_signals(["flush_ui"]),
      guards: [],
      actions: ["render_lustre_mvu"],
      root_states: [streaming],
      choices: [],
      initial: #([], "Streaming"),
    )

  AgentTypeSpec(
    kind: CockpitTelemetry,
    name: "C3I Verification Cockpit Telemetry Presenter Agent",
    c3i_system: C3iVerification,
    fractal_layer: 2,
    fractal_tag: "#fractal-l2",
    fpp_component_kind: Active,
    base_id: 0x1300,
    id_span: 64,
    queue_policy: Drop,
    description: "Binds 32 AG-UI lifecycle events to Lustre WebUI, ANSI TUI, and Wisp REST streaming endpoints over Tailscale FQDN.",
    operational_domain: "Human-Machine Interface (HMI)",
    sdlc_phase: "User Experience & Cockpit Delivery",
    sre_resilience_tier: "SIL-2 / Low-Latency",
    evidence_contracts: ["SC-AGUI-001", "SC-A2UI-001"],
    hsm_machine: hsm,
  )
}

fn build_payload_science_spec() -> AgentTypeSpec {
  let collecting =
    HierarchicalState(
      name: "Collecting",
      parent: None,
      entry: ["payload_active"],
      exit: ["payload_storing"],
      transitions: [
        Transition(
          on_signal: "sample_payload",
          guard: None,
          do_actions: ["read_payload_channel"],
          target: ToState("Collecting"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "PayloadScienceHSM",
      signals: make_signals(["sample_payload"]),
      guards: [],
      actions: ["read_payload_channel"],
      root_states: [collecting],
      choices: [],
      initial: #([], "Collecting"),
    )

  AgentTypeSpec(
    kind: PayloadScience,
    name: "C3I SDLC Payload Science Processor Agent",
    c3i_system: C3iSdlc,
    fractal_layer: 3,
    fractal_tag: "#fractal-l3",
    fpp_component_kind: Queued,
    base_id: 0x1340,
    id_span: 64,
    queue_policy: Block,
    description: "Supervised payload instruments, high-rate data collection, on-board semantic filtering, and scientific data staging.",
    operational_domain: "Scientific Instruments & Payloads",
    sdlc_phase: "Science Operations",
    sre_resilience_tier: "SIL-3 / High Throughput",
    evidence_contracts: ["SC-FPP-001", "SC-DMC-001"],
    hsm_machine: hsm,
  )
}

fn build_storage_custodian_spec() -> AgentTypeSpec {
  let guarding =
    HierarchicalState(
      name: "Guarding",
      parent: None,
      entry: ["lock_os_nvme"],
      exit: ["interlock_verified"],
      transitions: [
        Transition(
          on_signal: "validate_drive_target",
          guard: None,
          do_actions: ["enforce_hardware_serial_lock"],
          target: ToState("Guarding"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "StorageCustodianHSM",
      signals: make_signals(["validate_drive_target"]),
      guards: ["is_hard_denied_serial"],
      actions: ["enforce_hardware_serial_lock"],
      root_states: [guarding],
      choices: [],
      initial: #([], "Guarding"),
    )

  AgentTypeSpec(
    kind: StorageCustodian,
    name: "C3I SRE Descriptor-Relative VFS Storage Custodian Agent",
    c3i_system: C3iSre,
    fractal_layer: 1,
    fractal_tag: "#fractal-l1",
    fpp_component_kind: Active,
    base_id: 0x1380,
    id_span: 64,
    queue_policy: Assert,
    description: "Physical drive allocation, partition health monitoring, and absolute fail-closed locking of OS root NVMe 25503L801736.",
    operational_domain: "Hardware & Storage Safety",
    sdlc_phase: "Bare-Metal Security & Interlocks",
    sre_resilience_tier: "SIL-6 / DAL-A Hardware Locked",
    evidence_contracts: ["SC-STORAGE-001", "HARD_DENIED_SYSTEM_OS_SERIAL"],
    hsm_machine: hsm,
  )
}

fn build_km_sync_spec() -> AgentTypeSpec {
  let syncing =
    HierarchicalState(
      name: "Syncing",
      parent: None,
      entry: ["scan_km_triad"],
      exit: ["triad_consistent"],
      transitions: [
        Transition(
          on_signal: "check_sync",
          guard: None,
          do_actions: ["glue_km_sheaf"],
          target: ToState("Syncing"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "KmSyncHSM",
      signals: make_signals(["check_sync"]),
      guards: [],
      actions: ["glue_km_sheaf"],
      root_states: [syncing],
      choices: [],
      initial: #([], "Syncing"),
    )

  AgentTypeSpec(
    kind: KmSync,
    name: "C3I SDLC KM Triad Knowledge Sync Agent",
    c3i_system: C3iSdlc,
    fractal_layer: 5,
    fractal_tag: "#fractal-l5",
    fpp_component_kind: Queued,
    base_id: 0x13C0,
    id_span: 64,
    queue_policy: Block,
    description: "Bidirectional synchronization across Hermes Wiki, ZigVM ZK ADRs, and C3I Living Ontology with YYYYMMDD-HHSS- timestamp enforcement.",
    operational_domain: "Knowledge Management & Synthesis",
    sdlc_phase: "Documentation & Knowledge Ledgering",
    sre_resilience_tier: "SIL-3 / Consistent Sheaf",
    evidence_contracts: ["SC-KM-001", "SC-TIME-001"],
    hsm_machine: hsm,
  )
}

// =============================================================================
// Catalog API
// =============================================================================

fn build_hardware_drive_interlock_spec() -> AgentTypeSpec {
  let active_guard =
    HierarchicalState(
      name: "Guarding",
      parent: None,
      entry: ["drive_guard_armed"],
      exit: ["drive_guard_standdown"],
      transitions: [
        Transition(
          on_signal: "probe_target",
          guard: None,
          do_actions: ["verify_nvme_serial"],
          target: ToState("Guarding"),
        ),
        Transition(
          on_signal: "denied_serial_detected",
          guard: None,
          do_actions: ["trip_hardware_fault_lock"],
          target: ToState("LockedOut"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let locked_out =
    HierarchicalState(
      name: "LockedOut",
      parent: None,
      entry: ["halt_controller_io"],
      exit: ["cold_reboot_required"],
      transitions: [],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "HardwareDriveInterlockHSM",
      signals: make_signals([
        "probe_target",
        "denied_serial_detected",
        "system_reboot",
      ]),
      guards: ["is_hard_denied_serial"],
      actions: [
        "verify_nvme_serial",
        "trip_hardware_fault_lock",
        "halt_controller_io",
      ],
      root_states: [active_guard, locked_out],
      choices: [],
      initial: #([], "Guarding"),
    )

  AgentTypeSpec(
    kind: HardwareDriveInterlock,
    name: "C3I Verification Hardware Drive Safety Interlock Agent",
    c3i_system: C3iVerification,
    fractal_layer: 0,
    fractal_tag: "#fractal-l0",
    fpp_component_kind: Active,
    base_id: 0x1400,
    id_span: 64,
    queue_policy: Assert,
    description: "Guarantees block-driver level isolation and permanent denial of root OS NVMe serial 25503L801736.",
    operational_domain: "Hardware Storage Protection",
    sdlc_phase: "Runtime Safety Kernel",
    sre_resilience_tier: "SIL-6 / Fail-Closed",
    evidence_contracts: ["SC-STORAGE-001", "SC-FPP-INTENT-001"],
    hsm_machine: hsm,
  )
}

fn build_rocha_cut_guard_spec() -> AgentTypeSpec {
  let decoupled =
    HierarchicalState(
      name: "Decoupled",
      parent: None,
      entry: ["semiotic_boundary_verified"],
      exit: ["semiotic_boundary_breached"],
      transitions: [
        Transition(
          on_signal: "inspect_coupling",
          guard: None,
          do_actions: ["verify_rocha_cut"],
          target: ToState("Decoupled"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "RochaCutGuardHSM",
      signals: make_signals(["inspect_coupling", "realign_cut"]),
      guards: ["is_semiotically_decoupled"],
      actions: ["verify_rocha_cut", "force_semiotic_isolation"],
      root_states: [decoupled],
      choices: [],
      initial: #([], "Decoupled"),
    )

  AgentTypeSpec(
    kind: RochaSemioticCutGuard,
    name: "C3I Verification Rocha Semiotic Cut Guard Agent",
    c3i_system: C3iVerification,
    fractal_layer: 0,
    fractal_tag: "#fractal-l0",
    fpp_component_kind: Queued,
    base_id: 0x1440,
    id_span: 64,
    queue_policy: Assert,
    description: "Maintains biosemiotic decoupling between informational signs (code) and dynamic material laws (physics).",
    operational_domain: "Biosemiotic Cybernetics",
    sdlc_phase: "Formal Semantic Architecture",
    sre_resilience_tier: "SIL-5 / Informational Closure",
    evidence_contracts: ["SC-ROCHA-001", "SC-DMC-001"],
    hsm_machine: hsm,
  )
}

fn build_reduction_scheduler_spec() -> AgentTypeSpec {
  let running =
    HierarchicalState(
      name: "Executing",
      parent: None,
      entry: ["reset_reduction_counter"],
      exit: ["yield_cpu_slice"],
      transitions: [
        Transition(
          on_signal: "reduction_exhausted",
          guard: None,
          do_actions: ["suspend_and_enqueue"],
          target: ToState("Yielded"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let yielded =
    HierarchicalState(
      name: "Yielded",
      parent: None,
      entry: ["schedule_next_process"],
      exit: ["resume_process_context"],
      transitions: [
        Transition(
          on_signal: "timeslice_granted",
          guard: None,
          do_actions: ["load_registers"],
          target: ToState("Executing"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "ReductionSchedulerHSM",
      signals: make_signals([
        "reduction_exhausted",
        "timeslice_granted",
        "priority_bump",
      ]),
      guards: ["is_budget_exceeded"],
      actions: [
        "reset_reduction_counter",
        "suspend_and_enqueue",
        "schedule_next_process",
        "load_registers",
      ],
      root_states: [running, yielded],
      choices: [],
      initial: #([], "Executing"),
    )

  AgentTypeSpec(
    kind: DeterministicReductionScheduler,
    name: "C3I SRE Deterministic Reduction Scheduler Agent",
    c3i_system: C3iSre,
    fractal_layer: 1,
    fractal_tag: "#fractal-l1",
    fpp_component_kind: Active,
    base_id: 0x1480,
    id_span: 64,
    queue_policy: Block,
    description: "Enforces 4,000-reduction budget yield points (proc.zig), preventing starvation and priority inversion.",
    operational_domain: "Deterministic Runtime Engine",
    sdlc_phase: "Microsecond Actuator Execution",
    sre_resilience_tier: "SIL-6 / Real-Time Bounded",
    evidence_contracts: ["SC-ZIGVM-REDUCTIONS-001"],
    hsm_machine: hsm,
  )
}

fn build_substrate_reactor_spec() -> AgentTypeSpec {
  let polling =
    HierarchicalState(
      name: "Polling",
      parent: None,
      entry: ["arm_epoll_wait"],
      exit: ["disarm_epoll_wait"],
      transitions: [
        Transition(
          on_signal: "io_event_ready",
          guard: None,
          do_actions: ["dispatch_row_event"],
          target: ToState("Dispatching"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let dispatching =
    HierarchicalState(
      name: "Dispatching",
      parent: None,
      entry: ["propagate_actor_effect"],
      exit: ["complete_dispatch"],
      transitions: [
        Transition(
          on_signal: "dispatch_complete",
          guard: None,
          do_actions: ["rearm_interest"],
          target: ToState("Polling"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "SubstrateReactorHSM",
      signals: make_signals([
        "io_event_ready",
        "dispatch_complete",
        "timeout_tick",
      ]),
      guards: ["has_ready_events"],
      actions: [
        "arm_epoll_wait",
        "dispatch_row_event",
        "propagate_actor_effect",
        "rearm_interest",
      ],
      root_states: [polling, dispatching],
      choices: [],
      initial: #([], "Polling"),
    )

  AgentTypeSpec(
    kind: SubstrateReactor,
    name: "C3I Verification Substrate Reactor Event Multiplexer Agent",
    c3i_system: C3iVerification,
    fractal_layer: 1,
    fractal_tag: "#fractal-l1",
    fpp_component_kind: Active,
    base_id: 0x14C0,
    id_span: 64,
    queue_policy: Block,
    description: "Drives non-blocking epoll/kqueue event demuxing and row-polymorphic struct event propagation.",
    operational_domain: "Non-Blocking Async I/O",
    sdlc_phase: "I/O Multiplexing & Kernel Events",
    sre_resilience_tier: "SIL-5 / High-Throughput",
    evidence_contracts: ["SC-ZIGVM-REACTOR-001"],
    hsm_machine: hsm,
  )
}

fn build_linear_arena_reclaimer_spec() -> AgentTypeSpec {
  let active =
    HierarchicalState(
      name: "ActiveAllocation",
      parent: None,
      entry: ["mark_arena_watermark"],
      exit: ["lock_arena_for_reset"],
      transitions: [
        Transition(
          on_signal: "trigger_apoptosis",
          guard: None,
          do_actions: ["execute_linear_reset"],
          target: ToState("Reclaiming"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let reclaiming =
    HierarchicalState(
      name: "Reclaiming",
      parent: None,
      entry: ["zero_arena_header"],
      exit: ["unlock_arena"],
      transitions: [
        Transition(
          on_signal: "reset_complete",
          guard: None,
          do_actions: ["restore_nominal_capacity"],
          target: ToState("ActiveAllocation"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "LinearArenaReclaimerHSM",
      signals: make_signals([
        "trigger_apoptosis",
        "reset_complete",
        "overflow_warning",
      ]),
      guards: ["is_arena_dirty"],
      actions: [
        "mark_arena_watermark",
        "execute_linear_reset",
        "zero_arena_header",
        "restore_nominal_capacity",
      ],
      root_states: [active, reclaiming],
      choices: [],
      initial: #([], "ActiveAllocation"),
    )

  AgentTypeSpec(
    kind: LinearArenaReclaimer,
    name: "C3I SRE Linear Arena Memory Reclaimer Agent",
    c3i_system: C3iSre,
    fractal_layer: 1,
    fractal_tag: "#fractal-l1",
    fpp_component_kind: Active,
    base_id: 0x1500,
    id_span: 64,
    queue_policy: Drop,
    description: "Executes process apoptosis and reclaims linear execution frames in O(1) time without GC pauses.",
    operational_domain: "Zero-Muda Memory Management",
    sdlc_phase: "Process Apoptosis & Lifecycle",
    sre_resilience_tier: "SIL-6 / O(1) Reset",
    evidence_contracts: ["SC-MUDA-001", "SC-ZIGVM-ARENA-001"],
    hsm_machine: hsm,
  )
}

fn build_lockless_hamt_spec() -> AgentTypeSpec {
  let serving =
    HierarchicalState(
      name: "Serving",
      parent: None,
      entry: ["init_root_trie"],
      exit: ["quiesce_trie"],
      transitions: [
        Transition(
          on_signal: "atomic_cas_update",
          guard: None,
          do_actions: ["commit_hamt_node"],
          target: ToState("Serving"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "LocklessHamtStorageHSM",
      signals: make_signals(["atomic_cas_update", "compact_tree"]),
      guards: ["cas_matches_current"],
      actions: ["init_root_trie", "commit_hamt_node", "quiesce_trie"],
      root_states: [serving],
      choices: [],
      initial: #([], "Serving"),
    )

  AgentTypeSpec(
    kind: LocklessHamtStorage,
    name: "C3I SRE Lockless HAMT Storage Engine Agent",
    c3i_system: C3iSre,
    fractal_layer: 2,
    fractal_tag: "#fractal-l2",
    fpp_component_kind: Active,
    base_id: 0x1540,
    id_span: 64,
    queue_policy: Block,
    description: "Provides sub-microsecond atomic state exchange and parameter storage using lockless HAMT ETS.",
    operational_domain: "Concurrent In-Memory Storage",
    sdlc_phase: "High-Frequency Telemetry Cache",
    sre_resilience_tier: "SIL-5 / Non-Blocking CAS",
    evidence_contracts: ["SC-ZIGVM-HAMT-001"],
    hsm_machine: hsm,
  )
}

fn build_tagged_pointer_guard_spec() -> AgentTypeSpec {
  let verifying =
    HierarchicalState(
      name: "Verifying",
      parent: None,
      entry: ["enable_nan_box_check"],
      exit: ["disable_nan_box_check"],
      transitions: [
        Transition(
          on_signal: "inspect_term",
          guard: None,
          do_actions: ["validate_tag_bits"],
          target: ToState("Verifying"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "TaggedPointerGuardHSM",
      signals: make_signals(["inspect_term", "trap_escaped_pointer"]),
      guards: ["is_valid_nan_tagged"],
      actions: [
        "enable_nan_box_check",
        "validate_tag_bits",
        "trap_escaped_pointer",
      ],
      root_states: [verifying],
      choices: [],
      initial: #([], "Verifying"),
    )

  AgentTypeSpec(
    kind: TaggedPointerGuard,
    name: "C3I SRE Tagged Pointer NaN-Box Guard Agent",
    c3i_system: C3iSre,
    fractal_layer: 2,
    fractal_tag: "#fractal-l2",
    fpp_component_kind: Queued,
    base_id: 0x1580,
    id_span: 64,
    queue_policy: Assert,
    description: "Validates 64-bit NaN-boxed tagged pointer representation and prevents pointer escaping.",
    operational_domain: "Memory Coherence & Term Safety",
    sdlc_phase: "64-bit NaN-Box Pointer Invariant",
    sre_resilience_tier: "SIL-6 / Zero Memory Corruption",
    evidence_contracts: ["SC-DMC-001", "SC-ZIGVM-TERM-001"],
    hsm_machine: hsm,
  )
}

fn build_hierarchical_timer_wheel_spec() -> AgentTypeSpec {
  let ticking =
    HierarchicalState(
      name: "Ticking",
      parent: None,
      entry: ["start_hardware_timer_channel"],
      exit: ["stop_timer_channel"],
      transitions: [
        Transition(
          on_signal: "wheel_tick",
          guard: None,
          do_actions: ["cascade_buckets"],
          target: ToState("Ticking"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "HierarchicalTimerWheelHSM",
      signals: make_signals(["wheel_tick", "insert_timer", "cancel_timer"]),
      guards: ["is_within_jitter_bound"],
      actions: [
        "start_hardware_timer_channel",
        "cascade_buckets",
        "fire_expired_timers",
      ],
      root_states: [ticking],
      choices: [],
      initial: #([], "Ticking"),
    )

  AgentTypeSpec(
    kind: HierarchicalTimerWheel,
    name: "C3I SRE Hierarchical Timer Wheel Jitter Agent",
    c3i_system: C3iSre,
    fractal_layer: 2,
    fractal_tag: "#fractal-l2",
    fpp_component_kind: Active,
    base_id: 0x15C0,
    id_span: 64,
    queue_policy: Drop,
    description: "Manages 4-level timing bucket wheels with < 2us jitter for precision flight command dispatch.",
    operational_domain: "Timing & Actuation Sequencing",
    sdlc_phase: "Real-Time Clock & Jitter Control",
    sre_resilience_tier: "SIL-5 / Sub-2us Drift",
    evidence_contracts: ["SC-TIME-001", "SC-ZIGVM-TIMER-001"],
    hsm_machine: hsm,
  )
}

fn build_mcdc_tap_spec() -> AgentTypeSpec {
  let logging =
    HierarchicalState(
      name: "Recording",
      parent: None,
      entry: ["bind_decision_probes"],
      exit: ["flush_decision_vectors"],
      transitions: [
        Transition(
          on_signal: "branch_evaluated",
          guard: None,
          do_actions: ["record_truth_table_entry"],
          target: ToState("Recording"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "McdcAvionicsTapHSM",
      signals: make_signals(["branch_evaluated", "dump_coverage_matrix"]),
      guards: ["is_mcdc_complete"],
      actions: [
        "bind_decision_probes",
        "record_truth_table_entry",
        "flush_decision_vectors",
      ],
      root_states: [logging],
      choices: [],
      initial: #([], "Recording"),
    )

  AgentTypeSpec(
    kind: McdcAvionicsTap,
    name: "C3I Verification DO-178C Level-A MC/DC Tap Agent",
    c3i_system: C3iVerification,
    fractal_layer: 3,
    fractal_tag: "#fractal-l3",
    fpp_component_kind: Queued,
    base_id: 0x1600,
    id_span: 64,
    queue_policy: Block,
    description: "Records in-flight truth tables for branch conditions to achieve 100% DO-178C Level-A coverage.",
    operational_domain: "Avionics Verification & Certification",
    sdlc_phase: "DO-178C Level-A MC/DC Compliance",
    sre_resilience_tier: "SIL-6 / Auditable Trail",
    evidence_contracts: ["SC-DO178C-001", "SC-MCDC-001"],
    hsm_machine: hsm,
  )
}

fn build_crash_wal_spec() -> AgentTypeSpec {
  let appending =
    HierarchicalState(
      name: "Appending",
      parent: None,
      entry: ["open_wal_file_descriptor"],
      exit: ["sync_and_close_fd"],
      transitions: [
        Transition(
          on_signal: "log_event_entry",
          guard: None,
          do_actions: ["append_with_crc32"],
          target: ToState("Appending"),
        ),
        Transition(
          on_signal: "reboot_recovery_requested",
          guard: None,
          do_actions: ["scan_and_replay_log"],
          target: ToState("Replaying"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let replaying =
    HierarchicalState(
      name: "Replaying",
      parent: None,
      entry: ["verify_log_crc32"],
      exit: ["mark_replay_complete"],
      transitions: [
        Transition(
          on_signal: "replay_done",
          guard: None,
          do_actions: ["resume_append_mode"],
          target: ToState("Appending"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "CrashWalReplayHSM",
      signals: make_signals([
        "log_event_entry",
        "reboot_recovery_requested",
        "replay_done",
      ]),
      guards: ["is_wal_crc_valid"],
      actions: [
        "open_wal_file_descriptor",
        "append_with_crc32",
        "scan_and_replay_log",
        "verify_log_crc32",
        "resume_append_mode",
      ],
      root_states: [appending, replaying],
      choices: [],
      initial: #([], "Appending"),
    )

  AgentTypeSpec(
    kind: CrashWalReplay,
    name: "C3I SRE Crash-Consistent WAL Replay Agent",
    c3i_system: C3iSre,
    fractal_layer: 3,
    fractal_tag: "#fractal-l3",
    fpp_component_kind: Active,
    base_id: 0x1640,
    id_span: 64,
    queue_policy: Assert,
    description: "Appends transaction logs with CRC32 checksums and provides deterministic state reconstitution.",
    operational_domain: "Crash Resilience & State Recovery",
    sdlc_phase: "Write-Ahead Log & Deterministic Replay",
    sre_resilience_tier: "SIL-6 / Zero Data Loss",
    evidence_contracts: ["SC-ZIGVM-WAL-001"],
    hsm_machine: hsm,
  )
}

fn build_differential_bisim_spec() -> AgentTypeSpec {
  let checking =
    HierarchicalState(
      name: "Proving",
      parent: None,
      entry: ["init_bisimulation_oracle"],
      exit: ["emit_parity_certificate"],
      transitions: [
        Transition(
          on_signal: "compare_step_traces",
          guard: None,
          do_actions: ["assert_trace_isomorphism"],
          target: ToState("Proving"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "DifferentialBisimulationHSM",
      signals: make_signals(["compare_step_traces", "flag_divergence"]),
      guards: ["is_step_identical"],
      actions: [
        "init_bisimulation_oracle",
        "assert_trace_isomorphism",
        "emit_parity_certificate",
      ],
      root_states: [checking],
      choices: [],
      initial: #([], "Proving"),
    )

  AgentTypeSpec(
    kind: DifferentialBisimulation,
    name: "C3I Verification Cross-Runtime Bisimulation Agent",
    c3i_system: C3iVerification,
    fractal_layer: 3,
    fractal_tag: "#fractal-l3",
    fpp_component_kind: Queued,
    base_id: 0x1680,
    id_span: 64,
    queue_policy: Drop,
    description: "Continuously proves trace equivalence between Gleam HSM specifications and ZigVM bytecode slices.",
    operational_domain: "Formal Parity & Coherence",
    sdlc_phase: "Cross-Runtime Bisimulation",
    sre_resilience_tier: "SIL-5 / Mathematical Closure",
    evidence_contracts: ["SC-BISIM-001", "SC-PARITY-001"],
    hsm_machine: hsm,
  )
}

fn build_appup_coordinator_spec() -> AgentTypeSpec {
  let stable =
    HierarchicalState(
      name: "Stable",
      parent: None,
      entry: ["track_active_vsn"],
      exit: ["begin_prepare_upgrade"],
      transitions: [
        Transition(
          on_signal: "start_upgrade",
          guard: None,
          do_actions: ["quiesce_processes"],
          target: ToState("Migrating"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let migrating =
    HierarchicalState(
      name: "Migrating",
      parent: None,
      entry: ["execute_state_transform"],
      exit: ["commit_new_vsn"],
      transitions: [
        Transition(
          on_signal: "transform_success",
          guard: None,
          do_actions: ["switch_code_pointers"],
          target: ToState("Stable"),
        ),
        Transition(
          on_signal: "transform_failed",
          guard: None,
          do_actions: ["rollback_to_old_vsn"],
          target: ToState("Stable"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "AppupHotReloadHSM",
      signals: make_signals([
        "start_upgrade",
        "transform_success",
        "transform_failed",
      ]),
      guards: ["is_state_valid_for_vsn"],
      actions: [
        "track_active_vsn",
        "quiesce_processes",
        "execute_state_transform",
        "switch_code_pointers",
        "rollback_to_old_vsn",
      ],
      root_states: [stable, migrating],
      choices: [],
      initial: #([], "Stable"),
    )

  AgentTypeSpec(
    kind: AppupHotReloadCoordinator,
    name: "C3I SDLC Appup Hot Reload Coordinator Agent",
    c3i_system: C3iSdlc,
    fractal_layer: 4,
    fractal_tag: "#fractal-l4",
    fpp_component_kind: Active,
    base_id: 0x16C0,
    id_span: 64,
    queue_policy: Assert,
    description: "Coordinates atomic two-phase commit state migration and release upgrades without process restarts.",
    operational_domain: "Zero-Downtime System Upgrade",
    sdlc_phase: "Two-Phase Appup Release Upgrades",
    sre_resilience_tier: "SIL-5 / Atomic Cutover",
    evidence_contracts: ["SC-APPUP-001", "SC-RELEASE-001"],
    hsm_machine: hsm,
  )
}

fn build_slm_bif_spec() -> AgentTypeSpec {
  let ready =
    HierarchicalState(
      name: "Ready",
      parent: None,
      entry: ["warm_slm_weights"],
      exit: ["cool_slm_cache"],
      transitions: [
        Transition(
          on_signal: "score_tokens",
          guard: None,
          do_actions: ["invoke_slm_bif"],
          target: ToState("Ready"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "SlmBifInferenceHSM",
      signals: make_signals(["score_tokens", "reload_model"]),
      guards: ["is_latency_sub_5ms"],
      actions: ["warm_slm_weights", "invoke_slm_bif", "cool_slm_cache"],
      root_states: [ready],
      choices: [],
      initial: #([], "Ready"),
    )

  AgentTypeSpec(
    kind: SlmBifInference,
    name: "C3I SDLC SLM BIF Isolated Inference Agent",
    c3i_system: C3iSdlc,
    fractal_layer: 5,
    fractal_tag: "#fractal-l5",
    fpp_component_kind: Active,
    base_id: 0x1700,
    id_span: 64,
    queue_policy: Drop,
    description: "Executes low-latency neural token scoring and cognitive intention parsing in < 5ms via SLM BIFs.",
    operational_domain: "Edge Neural Intelligence",
    sdlc_phase: "Sub-5ms Token Scoring & Extraction",
    sre_resilience_tier: "SIL-4 / Real-Time Bounded",
    evidence_contracts: ["SC-SLM-BIF-001"],
    hsm_machine: hsm,
  )
}

fn build_fast_pattern_filter_spec() -> AgentTypeSpec {
  let filtering =
    HierarchicalState(
      name: "Filtering",
      parent: None,
      entry: ["compile_matchspec_bytecode"],
      exit: ["clear_filter_slots"],
      transitions: [
        Transition(
          on_signal: "filter_tuple",
          guard: None,
          do_actions: ["run_matchspec_eval"],
          target: ToState("Filtering"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "FastPatternFilterHSM",
      signals: make_signals(["filter_tuple", "update_patterns"]),
      guards: ["is_pattern_compiled"],
      actions: [
        "compile_matchspec_bytecode",
        "run_matchspec_eval",
        "clear_filter_slots",
      ],
      root_states: [filtering],
      choices: [],
      initial: #([], "Filtering"),
    )

  AgentTypeSpec(
    kind: FastPatternFilter,
    name: "C3I SDLC Fast Pattern Bitmask Filter Agent",
    c3i_system: C3iSdlc,
    fractal_layer: 5,
    fractal_tag: "#fractal-l5",
    fpp_component_kind: Queued,
    base_id: 0x1740,
    id_span: 64,
    queue_policy: Drop,
    description: "Compiles match specifications into bytecode for wire-speed filtering of telemetry tuples.",
    operational_domain: "High-Throughput Telemetry Filtering",
    sdlc_phase: "Match Specification Compilation",
    sre_resilience_tier: "SIL-5 / Constant-Time",
    evidence_contracts: ["SC-MATCHSPEC-001"],
    hsm_machine: hsm,
  )
}

fn build_epidemic_gossip_spec() -> AgentTypeSpec {
  let gossiping =
    HierarchicalState(
      name: "Disseminating",
      parent: None,
      entry: ["broadcast_swarm_ping"],
      exit: ["aggregate_vector_clocks"],
      transitions: [
        Transition(
          on_signal: "gossip_tick",
          guard: None,
          do_actions: ["send_random_peer_digest"],
          target: ToState("Disseminating"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "EpidemicGossipHSM",
      signals: make_signals(["gossip_tick", "peer_timeout", "merge_crdt_state"]),
      guards: ["is_gossip_converged"],
      actions: [
        "broadcast_swarm_ping",
        "send_random_peer_digest",
        "aggregate_vector_clocks",
      ],
      root_states: [gossiping],
      choices: [],
      initial: #([], "Disseminating"),
    )

  AgentTypeSpec(
    kind: EpidemicGossip,
    name: "C3I SRE Epidemic Gossip Convergence Agent",
    c3i_system: C3iSre,
    fractal_layer: 6,
    fractal_tag: "#fractal-l6",
    fpp_component_kind: Active,
    base_id: 0x1780,
    id_span: 64,
    queue_policy: Drop,
    description: "Disseminates swarm node heartbeats, CRDT state updates, and failure alerts in < 50ms.",
    operational_domain: "Distributed Swarm Health",
    sdlc_phase: "Decentralized Failure Detection",
    sre_resilience_tier: "SIL-5 / Epidemic Convergence",
    evidence_contracts: ["SC-GOSSIP-001", "SC-CRDT-001"],
    hsm_machine: hsm,
  )
}

fn build_bytecode_synthesizer_spec() -> AgentTypeSpec {
  let synthesizing =
    HierarchicalState(
      name: "Compiling",
      parent: None,
      entry: ["parse_fpp_hsm_ir"],
      exit: ["emit_beam_chunk"],
      transitions: [
        Transition(
          on_signal: "compile_agent_spec",
          guard: None,
          do_actions: ["generate_zigvm_opcodes"],
          target: ToState("Compiling"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "BytecodeSynthesizerHSM",
      signals: make_signals(["compile_agent_spec", "validate_bytecode"]),
      guards: ["is_bytecode_verifiable"],
      actions: ["parse_fpp_hsm_ir", "generate_zigvm_opcodes", "emit_beam_chunk"],
      root_states: [synthesizing],
      choices: [],
      initial: #([], "Compiling"),
    )

  AgentTypeSpec(
    kind: DynamicAgentBytecodeSynthesizer,
    name: "C3I SDLC Dynamic Agent Bytecode Synthesizer Agent",
    c3i_system: C3iSdlc,
    fractal_layer: 9,
    fractal_tag: "#fractal-l9",
    fpp_component_kind: Active,
    base_id: 0x17C0,
    id_span: 64,
    queue_policy: Block,
    description: "Compiles high-level FPP state machine specifications into native ZigVM bytecode during runtime reconfiguration.",
    operational_domain: "Metamorphic Self-Synthesis",
    sdlc_phase: "Runtime Bytecode Compilation",
    sre_resilience_tier: "SIL-5 / Hot Deployable",
    evidence_contracts: ["SC-AGENT-CODEGEN-001"],
    hsm_machine: hsm,
  )
}

fn build_sdlc_arch_synth_spec() -> AgentTypeSpec {
  let modeling =
    HierarchicalState(
      name: "Modeling",
      parent: None,
      entry: ["arch_modeling_init"],
      exit: ["arch_model_ready"],
      transitions: [
        Transition(
          on_signal: "start_decomposition",
          guard: None,
          do_actions: ["decompose_fractal_layers"],
          target: ToState("Decomposing"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let decomposing =
    HierarchicalState(
      name: "Decomposing",
      parent: None,
      entry: ["arch_decomposition_active"],
      exit: ["arch_decomposition_done"],
      transitions: [
        Transition(
          on_signal: "verify_invariants",
          guard: None,
          do_actions: ["validate_ast_invariants"],
          target: ToState("Synthesized"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let synthesized =
    HierarchicalState(
      name: "Synthesized",
      parent: None,
      entry: ["arch_spec_sealed"],
      exit: ["arch_spec_reopened"],
      transitions: [
        Transition(
          on_signal: "synthesis_complete",
          guard: None,
          do_actions: ["publish_architecture_spec"],
          target: ToState("Modeling"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "SdlcArchSynthHSM",
      signals: make_signals([
        "start_decomposition", "verify_invariants", "synthesis_complete",
      ]),
      guards: ["is_valid_fractal_topology"],
      actions: [
        "decompose_fractal_layers", "validate_ast_invariants",
        "publish_architecture_spec",
      ],
      root_states: [modeling, decomposing, synthesized],
      choices: [],
      initial: #([], "Modeling"),
    )

  AgentTypeSpec(
    kind: SdlcArchitectureSynthesizer,
    name: "C3I SDLC Architecture Synthesizer Agent",
    c3i_system: C3iSdlc,
    fractal_layer: 0,
    fractal_tag: "#fractal-l0",
    fpp_component_kind: Active,
    base_id: 0x1800,
    id_span: 64,
    queue_policy: Assert,
    description: "Formal architecture specification, AST decomposition, and domain model synthesis across all fractal layers.",
    operational_domain: "Formal Architecture Specification",
    sdlc_phase: "Specification & Invariant Definition",
    sre_resilience_tier: "SIL-6 / Fail-Closed",
    evidence_contracts: ["SC-SDLC-SPEC-001", "SC-FORMAL-001"],
    hsm_machine: hsm,
  )
}

fn build_sdlc_contract_gen_spec() -> AgentTypeSpec {
  let idle =
    HierarchicalState(
      name: "Idle",
      parent: None,
      entry: ["codegen_idle_entry"],
      exit: ["codegen_started"],
      transitions: [
        Transition(
          on_signal: "fpp_model_received",
          guard: None,
          do_actions: ["parse_fpp_ast"],
          target: ToState("GeneratingCode"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let generating =
    HierarchicalState(
      name: "GeneratingCode",
      parent: None,
      entry: ["emitting_gleam_modules"],
      exit: ["code_emission_complete"],
      transitions: [
        Transition(
          on_signal: "compilation_pass",
          guard: None,
          do_actions: ["verify_type_conformance"],
          target: ToState("CompilingTypes"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let compiling =
    HierarchicalState(
      name: "CompilingTypes",
      parent: None,
      entry: ["checking_type_soundness"],
      exit: ["type_soundness_verified"],
      transitions: [
        Transition(
          on_signal: "codegen_reset",
          guard: None,
          do_actions: ["flush_codegen_pipeline"],
          target: ToState("Idle"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "SdlcContractGenHSM",
      signals: make_signals([
        "fpp_model_received", "compilation_pass", "codegen_reset",
      ]),
      guards: ["is_clean_type_ast"],
      actions: [
        "parse_fpp_ast", "verify_type_conformance", "flush_codegen_pipeline",
      ],
      root_states: [idle, generating, compiling],
      choices: [],
      initial: #([], "Idle"),
    )

  AgentTypeSpec(
    kind: SdlcContractCodeGenerator,
    name: "C3I SDLC Contract Code Generator Agent",
    c3i_system: C3iSdlc,
    fractal_layer: 1,
    fractal_tag: "#fractal-l1",
    fpp_component_kind: Active,
    base_id: 0x1840,
    id_span: 64,
    queue_policy: Block,
    description: "Automated pure BEAM Gleam code and Gospel contract generation from NASA JPL FPP formal models.",
    operational_domain: "Automated Gospel & FPP Code Synthesis",
    sdlc_phase: "Synthesis & Code Evolution",
    sre_resilience_tier: "SIL-5 / Deterministic CodeGen",
    evidence_contracts: ["SC-CODEGEN-001", "SC-GOSPEL-001"],
    hsm_machine: hsm,
  )
}

fn build_sdlc_static_analysis_spec() -> AgentTypeSpec {
  let auditing =
    HierarchicalState(
      name: "Auditing",
      parent: None,
      entry: ["static_linter_start"],
      exit: ["linter_pass_complete"],
      transitions: [
        Transition(
          on_signal: "scan_tree",
          guard: None,
          do_actions: ["scan_for_compiler_warnings"],
          target: ToState("Auditing"),
        ),
        Transition(
          on_signal: "audit_passed",
          guard: None,
          do_actions: ["certify_zero_warning_purity"],
          target: ToState("Clean"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let clean =
    HierarchicalState(
      name: "Clean",
      parent: None,
      entry: ["zero_muda_certified"],
      exit: ["audit_retriggered"],
      transitions: [
        Transition(
          on_signal: "scan_tree",
          guard: None,
          do_actions: ["recheck_codebase_integrity"],
          target: ToState("Auditing"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "SdlcStaticAnalysisHSM",
      signals: make_signals(["scan_tree", "audit_passed"]),
      guards: ["is_zero_warning"],
      actions: [
        "scan_for_compiler_warnings", "certify_zero_warning_purity",
        "recheck_codebase_integrity",
      ],
      root_states: [auditing, clean],
      choices: [],
      initial: #([], "Auditing"),
    )

  AgentTypeSpec(
    kind: SdlcStaticAnalysisAuditor,
    name: "C3I SDLC Static Analysis & Linter Auditor Agent",
    c3i_system: C3iSdlc,
    fractal_layer: 2,
    fractal_tag: "#fractal-l2",
    fpp_component_kind: Active,
    base_id: 0x1880,
    id_span: 64,
    queue_policy: Assert,
    description: "Strict zero-warning, zero-muda, and dead-code elimination enforcement across Gleam, OCaml, and Rust codelines.",
    operational_domain: "Zero-Warning & Zero-Muda Quality Linter",
    sdlc_phase: "Verification & Gatekeeping",
    sre_resilience_tier: "SIL-6 / Zero-Warning Invariant",
    evidence_contracts: ["SC-MUDA-001", "SC-LINT-001"],
    hsm_machine: hsm,
  )
}

fn build_sdlc_release_packager_spec() -> AgentTypeSpec {
  let staging =
    HierarchicalState(
      name: "Staging",
      parent: None,
      entry: ["release_staging_entry"],
      exit: ["release_staged"],
      transitions: [
        Transition(
          on_signal: "package_trigger",
          guard: None,
          do_actions: ["assemble_release_artifacts"],
          target: ToState("GeneratingSbom"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let sbom =
    HierarchicalState(
      name: "GeneratingSbom",
      parent: None,
      entry: ["generating_cyclonedx_sbom"],
      exit: ["sbom_verified"],
      transitions: [
        Transition(
          on_signal: "package_sealed",
          guard: None,
          do_actions: ["sign_release_cryptographically"],
          target: ToState("Sealed"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let sealed =
    HierarchicalState(
      name: "Sealed",
      parent: None,
      entry: ["release_ready_for_cutover"],
      exit: ["release_archive_stored"],
      transitions: [
        Transition(
          on_signal: "package_trigger",
          guard: None,
          do_actions: ["reset_packager"],
          target: ToState("Staging"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "SdlcReleasePackagerHSM",
      signals: make_signals(["package_trigger", "package_sealed"]),
      guards: ["is_two_key_signed"],
      actions: [
        "assemble_release_artifacts", "sign_release_cryptographically",
        "reset_packager",
      ],
      root_states: [staging, sbom, sealed],
      choices: [],
      initial: #([], "Staging"),
    )

  AgentTypeSpec(
    kind: SdlcReleasePackagingOrchestrator,
    name: "C3I SDLC Release Packaging Orchestrator Agent",
    c3i_system: C3iSdlc,
    fractal_layer: 4,
    fractal_tag: "#fractal-l4",
    fpp_component_kind: Active,
    base_id: 0x18C0,
    id_span: 64,
    queue_policy: Block,
    description: "Deterministic release tarball assembly, CycloneDX SBOM generation, and cryptographic two-key release signing.",
    operational_domain: "Deterministic Release Packaging & SBOM",
    sdlc_phase: "Release & Appup Cutover",
    sre_resilience_tier: "SIL-5 / Cryptographic Manifest",
    evidence_contracts: ["SC-RELEASE-001", "SC-SBOM-001"],
    hsm_machine: hsm,
  )
}

fn build_sdlc_doc_sync_spec() -> AgentTypeSpec {
  let indexing =
    HierarchicalState(
      name: "Indexing",
      parent: None,
      entry: ["indexing_wiki_zk_corpora"],
      exit: ["index_up_to_date"],
      transitions: [
        Transition(
          on_signal: "scan_docs",
          guard: None,
          do_actions: ["validate_timestamp_prefix"],
          target: ToState("ValidatingPrefix"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let validating =
    HierarchicalState(
      name: "ValidatingPrefix",
      parent: None,
      entry: ["checking_yyyy_mm_dd_prefix"],
      exit: ["all_docs_prefixed"],
      transitions: [
        Transition(
          on_signal: "sync_complete",
          guard: None,
          do_actions: ["commit_transclusion_graph"],
          target: ToState("Synced"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let synced =
    HierarchicalState(
      name: "Synced",
      parent: None,
      entry: ["km_triad_in_parity"],
      exit: ["docs_modified"],
      transitions: [
        Transition(
          on_signal: "scan_docs",
          guard: None,
          do_actions: ["reindex_corpus"],
          target: ToState("Indexing"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "SdlcDocSyncHSM",
      signals: make_signals(["scan_docs", "sync_complete"]),
      guards: ["has_valid_timestamp_prefix"],
      actions: [
        "validate_timestamp_prefix", "commit_transclusion_graph",
        "reindex_corpus",
      ],
      root_states: [indexing, validating, synced],
      choices: [],
      initial: #([], "Indexing"),
    )

  AgentTypeSpec(
    kind: SdlcDocumentationTransclusionSync,
    name: "C3I SDLC Documentation Transclusion Sync Agent",
    c3i_system: C3iSdlc,
    fractal_layer: 6,
    fractal_tag: "#fractal-l6",
    fpp_component_kind: Active,
    base_id: 0x1900,
    id_span: 64,
    queue_policy: Drop,
    description: "Enforces mandatory YYYYMMDD-HHSS- timestamp prefix and transclusion link integrity across Wiki and ZK corpora.",
    operational_domain: "Living KM & Transclusion Synchronizer",
    sdlc_phase: "Documentation & Knowledge Sync",
    sre_resilience_tier: "SIL-5 / Eventual ZK Parity",
    evidence_contracts: ["SC-TIME-001", "SC-KM-TRIAD-001"],
    hsm_machine: hsm,
  )
}

fn build_sdlc_evolution_governor_spec() -> AgentTypeSpec {
  let iterating =
    HierarchicalState(
      name: "Iterating",
      parent: None,
      entry: ["cycle_stepping_active"],
      exit: ["cycle_step_finished"],
      transitions: [
        Transition(
          on_signal: "step_cycle",
          guard: None,
          do_actions: ["advance_codex_claude_cycle"],
          target: ToState("EvaluatingEntropy"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let evaluating =
    HierarchicalState(
      name: "EvaluatingEntropy",
      parent: None,
      entry: ["measuring_shannon_entropy"],
      exit: ["entropy_bound_verified"],
      transitions: [
        Transition(
          on_signal: "cycles_ratified",
          guard: None,
          do_actions: ["ratify_tri_sovereign_consensus"],
          target: ToState("Converged"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let converged =
    HierarchicalState(
      name: "Converged",
      parent: None,
      entry: ["evolution_cycle_sealed"],
      exit: ["new_cycles_requested"],
      transitions: [
        Transition(
          on_signal: "step_cycle",
          guard: None,
          do_actions: ["reopen_evolutionary_loop"],
          target: ToState("Iterating"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "SdlcEvolutionGovernorHSM",
      signals: make_signals(["step_cycle", "cycles_ratified"]),
      guards: ["is_entropy_sufficient"],
      actions: [
        "advance_codex_claude_cycle", "ratify_tri_sovereign_consensus",
        "reopen_evolutionary_loop",
      ],
      root_states: [iterating, evaluating, converged],
      choices: [],
      initial: #([], "Iterating"),
    )

  AgentTypeSpec(
    kind: SdlcEvolutionaryLoopGovernor,
    name: "C3I SDLC Evolutionary Loop Governor Agent",
    c3i_system: C3iSdlc,
    fractal_layer: 9,
    fractal_tag: "#fractal-l9",
    fpp_component_kind: Active,
    base_id: 0x1940,
    id_span: 64,
    queue_policy: Block,
    description: "Supervises the recursive multi-cycle Codex-Claude evolutionary iteration, Shannon entropy, and convergence algebra.",
    operational_domain: "Codex-Claude Evolutionary Cycle Engine",
    sdlc_phase: "Meta-Evolution & Hot-Reloading",
    sre_resilience_tier: "SIL-6 / Tri-Sovereign Consensus",
    evidence_contracts: ["SC-EVOLUTION-001", "SC-SOV-001"],
    hsm_machine: hsm,
  )
}

fn build_sre_lyapunov_detector_spec() -> AgentTypeSpec {
  let sampling =
    HierarchicalState(
      name: "WindowSampling",
      parent: None,
      entry: ["sampling_telemetry_window"],
      exit: ["telemetry_window_full"],
      transitions: [
        Transition(
          on_signal: "sample_tick",
          guard: None,
          do_actions: ["compute_trajectory_drift"],
          target: ToState("EvaluatingLambda"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let evaluating =
    HierarchicalState(
      name: "EvaluatingLambda",
      parent: None,
      entry: ["solving_least_squares_lambda"],
      exit: ["lambda_computed_exit"],
      transitions: [
        Transition(
          on_signal: "lambda_computed",
          guard: None,
          do_actions: ["verify_negative_exponent"],
          target: ToState("TrendStable"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let stable =
    HierarchicalState(
      name: "TrendStable",
      parent: None,
      entry: ["asymptotically_stable_state"],
      exit: ["new_window_started"],
      transitions: [
        Transition(
          on_signal: "sample_tick",
          guard: None,
          do_actions: ["shift_sample_window"],
          target: ToState("WindowSampling"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "SreLyapunovTrendHSM",
      signals: make_signals(["sample_tick", "lambda_computed"]),
      guards: ["is_lambda_negative"],
      actions: [
        "compute_trajectory_drift", "verify_negative_exponent",
        "shift_sample_window",
      ],
      root_states: [sampling, evaluating, stable],
      choices: [],
      initial: #([], "WindowSampling"),
    )

  AgentTypeSpec(
    kind: SreLyapunovTrendDetector,
    name: "C3I SRE Lyapunov Trend Detector Agent",
    c3i_system: C3iSre,
    fractal_layer: 4,
    fractal_tag: "#fractal-l4",
    fpp_component_kind: Active,
    base_id: 0x1980,
    id_span: 64,
    queue_policy: Drop,
    description: "Windowed numerical trajectory tracking proving negative Lyapunov exponents (lambda < 0) and early bifurcation warning.",
    operational_domain: "Continuous Lyapunov Stability Proof",
    sdlc_phase: "Operations & Reliability",
    sre_resilience_tier: "SIL-6 / Lyapunov Negative Drift",
    evidence_contracts: ["SC-SRE-LYAPUNOV-001", "SC-MATH-001"],
    hsm_machine: hsm,
  )
}

fn build_sre_chaos_injector_spec() -> AgentTypeSpec {
  let dormant =
    HierarchicalState(
      name: "Dormant",
      parent: None,
      entry: ["chaos_dormant_entry"],
      exit: ["chaos_armed"],
      transitions: [
        Transition(
          on_signal: "arm_chaos",
          guard: None,
          do_actions: ["prepare_bounded_fault"],
          target: ToState("InjectingFault"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let injecting =
    HierarchicalState(
      name: "InjectingFault",
      parent: None,
      entry: ["fault_injection_active"],
      exit: ["fault_burst_complete"],
      transitions: [
        Transition(
          on_signal: "trigger_partition",
          guard: None,
          do_actions: ["observe_circuit_breaker_trip"],
          target: ToState("ObservingRecovery"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let observing =
    HierarchicalState(
      name: "ObservingRecovery",
      parent: None,
      entry: ["monitoring_reconvergence"],
      exit: ["system_healed"],
      transitions: [
        Transition(
          on_signal: "fault_cleared",
          guard: None,
          do_actions: ["certify_self_healing_time"],
          target: ToState("Dormant"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "SreChaosInjectorHSM",
      signals: make_signals(["arm_chaos", "trigger_partition", "fault_cleared"]),
      guards: ["is_safe_test_environment"],
      actions: [
        "prepare_bounded_fault", "observe_circuit_breaker_trip",
        "certify_self_healing_time",
      ],
      root_states: [dormant, injecting, observing],
      choices: [],
      initial: #([], "Dormant"),
    )

  AgentTypeSpec(
    kind: SreChaosFaultInjector,
    name: "C3I SRE Chaos Fault Injector Agent",
    c3i_system: C3iSre,
    fractal_layer: 4,
    fractal_tag: "#fractal-l4",
    fpp_component_kind: Active,
    base_id: 0x19C0,
    id_span: 64,
    queue_policy: Assert,
    description: "Controlled chaos injection, network partition simulation, and automatic Prajna circuit-breaker tripping validation.",
    operational_domain: "Controlled Chaos & Fault Injection",
    sdlc_phase: "Operations & Reliability",
    sre_resilience_tier: "SIL-5 / Bounded Blast Radius",
    evidence_contracts: ["SC-CHAOS-001", "SC-SRE-RECOVERY-001"],
    hsm_machine: hsm,
  )
}

fn build_sre_freshness_monitor_spec() -> AgentTypeSpec {
  let monitoring =
    HierarchicalState(
      name: "Monitoring",
      parent: None,
      entry: ["freshness_timer_start"],
      exit: ["heartbeat_received"],
      transitions: [
        Transition(
          on_signal: "heartbeat_tick",
          guard: None,
          do_actions: ["reset_deadmans_timer"],
          target: ToState("Monitoring"),
        ),
        Transition(
          on_signal: "drift_warning",
          guard: None,
          do_actions: ["flag_clock_skew"],
          target: ToState("Warning"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let warning =
    HierarchicalState(
      name: "Warning",
      parent: None,
      entry: ["drift_exceeded_threshold"],
      exit: ["drift_corrected"],
      transitions: [
        Transition(
          on_signal: "heartbeat_tick",
          guard: None,
          do_actions: ["realign_timesync"],
          target: ToState("Monitoring"),
        ),
        Transition(
          on_signal: "ttl_expired",
          guard: None,
          do_actions: ["trip_deadmans_safehold"],
          target: ToState("SafeHoldTripped"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let safehold =
    HierarchicalState(
      name: "SafeHoldTripped",
      parent: None,
      entry: ["emergency_hold_active"],
      exit: ["manual_clearance_granted"],
      transitions: [
        Transition(
          on_signal: "reset_monitor",
          guard: None,
          do_actions: ["clear_deadmans_safehold"],
          target: ToState("Monitoring"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "SreFreshnessMonitorHSM",
      signals: make_signals([
        "heartbeat_tick", "drift_warning", "ttl_expired", "reset_monitor",
      ]),
      guards: ["is_clock_synchronized"],
      actions: [
        "reset_deadmans_timer", "flag_clock_skew", "realign_timesync",
        "trip_deadmans_safehold", "clear_deadmans_safehold",
      ],
      root_states: [monitoring, warning, safehold],
      choices: [],
      initial: #([], "Monitoring"),
    )

  AgentTypeSpec(
    kind: SreFreshnessMonitor,
    name: "C3I SRE Freshness Dead-Mans Monitor Agent",
    c3i_system: C3iSre,
    fractal_layer: 2,
    fractal_tag: "#fractal-l2",
    fpp_component_kind: Active,
    base_id: 0x1A00,
    id_span: 64,
    queue_policy: Drop,
    description: "Monitors microsecond host NTP clock drift and triggers fail-safe safe-holds on expired dead-man switch intervals.",
    operational_domain: "Dead-Man's Switch & Clock Drift",
    sdlc_phase: "Operations & Reliability",
    sre_resilience_tier: "SIL-6 / Microsecond Precision",
    evidence_contracts: ["SC-FRESHNESS-001", "SC-TIME-SYNC-001"],
    hsm_machine: hsm,
  )
}

fn build_sre_cpu_budget_governor_spec() -> AgentTypeSpec {
  let tracking =
    HierarchicalState(
      name: "TrackingReductions",
      parent: None,
      entry: ["reduction_budget_init"],
      exit: ["reduction_slice_finished"],
      transitions: [
        Transition(
          on_signal: "reduction_tick",
          guard: None,
          do_actions: ["decrement_process_budget"],
          target: ToState("TrackingReductions"),
        ),
        Transition(
          on_signal: "budget_exceeded",
          guard: None,
          do_actions: ["preempt_runaway_process"],
          target: ToState("Throttling"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let throttling =
    HierarchicalState(
      name: "Throttling",
      parent: None,
      entry: ["yield_mandated"],
      exit: ["next_timeslice_ready"],
      transitions: [
        Transition(
          on_signal: "timeslice_reclaimed",
          guard: None,
          do_actions: ["restore_nominal_priority"],
          target: ToState("TrackingReductions"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "SreCpuGovernorHSM",
      signals: make_signals([
        "reduction_tick", "budget_exceeded", "timeslice_reclaimed",
      ]),
      guards: ["is_quota_bounded"],
      actions: [
        "decrement_process_budget", "preempt_runaway_process",
        "restore_nominal_priority",
      ],
      root_states: [tracking, throttling],
      choices: [],
      initial: #([], "TrackingReductions"),
    )

  AgentTypeSpec(
    kind: SreCpuBudgetGovernor,
    name: "C3I SRE Preemptive CPU Budget Governor Agent",
    c3i_system: C3iSre,
    fractal_layer: 1,
    fractal_tag: "#fractal-l1",
    fpp_component_kind: Active,
    base_id: 0x1A40,
    id_span: 64,
    queue_policy: Assert,
    description: "Enforces per-process reduction limits and dynamic scheduling priority adjustment to prevent starvation.",
    operational_domain: "Preemptive Reduction Quota Enforcement",
    sdlc_phase: "Operations & Reliability",
    sre_resilience_tier: "SIL-6 / Runaway Loop Prevention",
    evidence_contracts: ["SC-REDUCTION-BUDGET-001", "SC-CPU-GOV-001"],
    hsm_machine: hsm,
  )
}

fn build_verification_checklist_auditor_spec() -> AgentTypeSpec {
  let scanning =
    HierarchicalState(
      name: "ScanningChecklist",
      parent: None,
      entry: ["evaluating_18_checkpoints"],
      exit: ["checkpoint_batch_done"],
      transitions: [
        Transition(
          on_signal: "audit_check",
          guard: None,
          do_actions: ["evaluate_single_checkpoint"],
          target: ToState("DomainEvaluated"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let domain_eval =
    HierarchicalState(
      name: "DomainEvaluated",
      parent: None,
      entry: ["aggregating_5_domains"],
      exit: ["all_domains_tallied"],
      transitions: [
        Transition(
          on_signal: "all_domains_pass",
          guard: None,
          do_actions: ["ratify_18_18_checklist"],
          target: ToState("Checklist18Green"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let green =
    HierarchicalState(
      name: "Checklist18Green",
      parent: None,
      entry: ["checklist_gate_ratified"],
      exit: ["recheck_triggered"],
      transitions: [
        Transition(
          on_signal: "checklist_reset",
          guard: None,
          do_actions: ["clear_checklist_cache"],
          target: ToState("ScanningChecklist"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "VerificationChecklistHSM",
      signals: make_signals([
        "audit_check", "all_domains_pass", "checklist_reset",
      ]),
      guards: ["is_18_of_18_passing"],
      actions: [
        "evaluate_single_checkpoint", "ratify_18_18_checklist",
        "clear_checklist_cache",
      ],
      root_states: [scanning, domain_eval, green],
      choices: [],
      initial: #([], "ScanningChecklist"),
    )

  AgentTypeSpec(
    kind: VerificationChecklistAuditor,
    name: "C3I Verification Checklist Auditor Agent",
    c3i_system: C3iVerification,
    fractal_layer: 0,
    fractal_tag: "#fractal-l0",
    fpp_component_kind: Active,
    base_id: 0x1A80,
    id_span: 64,
    queue_policy: Assert,
    description: "Continuous machine verification of the 18-checkpoint, 5-domain Comprehensive Verification Checklist (SC-CHECKLIST-001).",
    operational_domain: "Universal 18-Checkpoint Gatekeeper",
    sdlc_phase: "Verification & Gatekeeping",
    sre_resilience_tier: "SIL-6 / 100% Green Gate",
    evidence_contracts: ["SC-CHECKLIST-001", "SPEC-CHECKLIST-NAV-001"],
    hsm_machine: hsm,
  )
}

fn build_verification_math_gate_certifier_spec() -> AgentTypeSpec {
  let collecting =
    HierarchicalState(
      name: "CollectingMetrics",
      parent: None,
      entry: ["sampling_math_metrics"],
      exit: ["metrics_pool_ready"],
      transitions: [
        Transition(
          on_signal: "metrics_ready",
          guard: None,
          do_actions: ["evaluate_4_math_gates"],
          target: ToState("Gating"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let gating =
    HierarchicalState(
      name: "Gating",
      parent: None,
      entry: ["checking_entropy_and_itqs"],
      exit: ["thresholds_checked"],
      transitions: [
        Transition(
          on_signal: "gates_passed",
          guard: None,
          do_actions: ["issue_math_certificate"],
          target: ToState("Certified"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let certified =
    HierarchicalState(
      name: "Certified",
      parent: None,
      entry: ["math_gates_ratified_active"],
      exit: ["re_evaluating_metrics"],
      transitions: [
        Transition(
          on_signal: "metrics_ready",
          guard: None,
          do_actions: ["refresh_metrics"],
          target: ToState("CollectingMetrics"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "VerificationMathGatesHSM",
      signals: make_signals(["metrics_ready", "gates_passed"]),
      guards: ["satisfies_math_thresholds"],
      actions: [
        "evaluate_4_math_gates", "issue_math_certificate", "refresh_metrics",
      ],
      root_states: [collecting, gating, certified],
      choices: [],
      initial: #([], "CollectingMetrics"),
    )

  AgentTypeSpec(
    kind: VerificationMathGateCertifier,
    name: "C3I Verification 4 Math Gates Certifier Agent",
    c3i_system: C3iVerification,
    fractal_layer: 0,
    fractal_tag: "#fractal-l0",
    fpp_component_kind: Active,
    base_id: 0x1AC0,
    id_span: 64,
    queue_policy: Assert,
    description: "Certifies the 4 Mathematical Gates: Shannon Entropy H >= 2.5b, CCM >= 90%, Divergence D_EA <= 10%, ITQS >= 0.85.",
    operational_domain: "4 Mathematical Gates Evaluation",
    sdlc_phase: "Verification & Gatekeeping",
    sre_resilience_tier: "SIL-6 / Mathematical Certainty",
    evidence_contracts: ["SC-MATH-001", "SC-ENTROPY-001"],
    hsm_machine: hsm,
  )
}

fn build_verification_nine_modality_executor_spec() -> AgentTypeSpec {
  let queued =
    HierarchicalState(
      name: "SuiteQueued",
      parent: None,
      entry: ["test_protocol_queued"],
      exit: ["dispatching_modality"],
      transitions: [
        Transition(
          on_signal: "dispatch_suite",
          guard: None,
          do_actions: ["execute_modality_suite"],
          target: ToState("ExecutingModality"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let executing =
    HierarchicalState(
      name: "ExecutingModality",
      parent: None,
      entry: ["running_tests_concurrently"],
      exit: ["modality_completed"],
      transitions: [
        Transition(
          on_signal: "all_suites_green",
          guard: None,
          do_actions: ["ratify_full_protocol"],
          target: ToState("ProtocolComplete"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let complete =
    HierarchicalState(
      name: "ProtocolComplete",
      parent: None,
      entry: ["protocol_100_percent_green"],
      exit: ["new_run_queued"],
      transitions: [
        Transition(
          on_signal: "dispatch_suite",
          guard: None,
          do_actions: ["reset_protocol_runner"],
          target: ToState("SuiteQueued"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "VerificationNineModalityHSM",
      signals: make_signals(["dispatch_suite", "all_suites_green"]),
      guards: ["is_zero_failures"],
      actions: [
        "execute_modality_suite", "ratify_full_protocol",
        "reset_protocol_runner",
      ],
      root_states: [queued, executing, complete],
      choices: [],
      initial: #([], "SuiteQueued"),
    )

  AgentTypeSpec(
    kind: VerificationNineModalityExecutor,
    name: "C3I Verification 9-Modality Test Executor Agent",
    c3i_system: C3iVerification,
    fractal_layer: 3,
    fractal_tag: "#fractal-l3",
    fpp_component_kind: Active,
    base_id: 0x1B00,
    id_span: 64,
    queue_policy: Block,
    description: "Orchestrates the full 9-modality test protocol spanning Unit, System, TDD, BDD, Performance, Scale, Property, Fuzz, and Chaos.",
    operational_domain: "9-Modality Test Protocol Orchestration",
    sdlc_phase: "Verification & Gatekeeping",
    sre_resilience_tier: "SIL-6 / Full Test Spectrum",
    evidence_contracts: ["SC-9MOD-001", "SC-TEST-GOLD-001"],
    hsm_machine: hsm,
  )
}

fn build_verification_browser_matrix_tester_spec() -> AgentTypeSpec {
  let ready =
    HierarchicalState(
      name: "HeadlessReady",
      parent: None,
      entry: ["headless_browser_pool_online"],
      exit: ["launching_browser_suite"],
      transitions: [
        Transition(
          on_signal: "launch_browser",
          guard: None,
          do_actions: ["execute_page_asserts"],
          target: ToState("TestingRoutes"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let testing =
    HierarchicalState(
      name: "TestingRoutes",
      parent: None,
      entry: ["asserting_dom_elements"],
      exit: ["all_routes_tested"],
      transitions: [
        Transition(
          on_signal: "matrix_complete",
          guard: None,
          do_actions: ["certify_64_suites_green"],
          target: ToState("MatrixPassed"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let passed =
    HierarchicalState(
      name: "MatrixPassed",
      parent: None,
      entry: ["matrix_efficacy_verified"],
      exit: ["matrix_run_restarted"],
      transitions: [
        Transition(
          on_signal: "launch_browser",
          guard: None,
          do_actions: ["flush_browser_sessions"],
          target: ToState("HeadlessReady"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "VerificationBrowserMatrixHSM",
      signals: make_signals(["launch_browser", "matrix_complete"]),
      guards: ["is_all_routes_green"],
      actions: [
        "execute_page_asserts", "certify_64_suites_green",
        "flush_browser_sessions",
      ],
      root_states: [ready, testing, passed],
      choices: [],
      initial: #([], "HeadlessReady"),
    )

  AgentTypeSpec(
    kind: VerificationBrowserMatrixTester,
    name: "C3I Verification 64 Browser Matrix Tester Agent",
    c3i_system: C3iVerification,
    fractal_layer: 2,
    fractal_tag: "#fractal-l2",
    fpp_component_kind: Active,
    base_id: 0x1B40,
    id_span: 64,
    queue_policy: Block,
    description: "Automated headless runner and telemetry aggregator for all 64 browser-based Playwright, Wallaby, and CDP tests.",
    operational_domain: "64 Browser-Based Tests Execution",
    sdlc_phase: "Verification & Gatekeeping",
    sre_resilience_tier: "SIL-5 / Playwright & Wallaby Parity",
    evidence_contracts: ["SC-BROWSER-TEST-001", "SC-UI-QUALITY-001"],
    hsm_machine: hsm,
  )
}

fn build_verification_tcm_protector_spec() -> AgentTypeSpec {
  let tracking =
    HierarchicalState(
      name: "TrackingCoordinates",
      parent: None,
      entry: ["coordinate_vector_init"],
      exit: ["coordinate_transition_detected"],
      transitions: [
        Transition(
          on_signal: "tcm_transition",
          guard: None,
          do_actions: ["calculate_coordinate_delta"],
          target: ToState("ProvingConservation"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let proving =
    HierarchicalState(
      name: "ProvingConservation",
      parent: None,
      entry: ["evaluating_lean4_conservation"],
      exit: ["conservation_proved"],
      transitions: [
        Transition(
          on_signal: "conservation_pass",
          guard: None,
          do_actions: ["certify_delta_zero"],
          target: ToState("Conserved"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let conserved =
    HierarchicalState(
      name: "Conserved",
      parent: None,
      entry: ["tcm_13d_conserved_state"],
      exit: ["new_transition_event"],
      transitions: [
        Transition(
          on_signal: "tcm_transition",
          guard: None,
          do_actions: ["cycle_tcm_tracker"],
          target: ToState("TrackingCoordinates"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "VerificationTcmProtectorHSM",
      signals: make_signals(["tcm_transition", "conservation_pass"]),
      guards: ["is_delta_zero"],
      actions: [
        "calculate_coordinate_delta", "certify_delta_zero", "cycle_tcm_tracker",
      ],
      root_states: [tracking, proving, conserved],
      choices: [],
      initial: #([], "TrackingCoordinates"),
    )

  AgentTypeSpec(
    kind: VerificationTcmCoordinateProtector,
    name: "C3I Verification 13D TCM Coordinate Protector Agent",
    c3i_system: C3iVerification,
    fractal_layer: 0,
    fractal_tag: "#fractal-l0",
    fpp_component_kind: Active,
    base_id: 0x1B80,
    id_span: 64,
    queue_policy: Assert,
    description: "Proves 13-dimensional traceability coordinate conservation Delta T_13 = 0 and fail-closed indicator I(Trust) in Lean 4.",
    operational_domain: "13D TCM Coordinate Conservation",
    sdlc_phase: "Verification & Gatekeeping",
    sre_resilience_tier: "SIL-6 / Lean 4 Proved",
    evidence_contracts: ["SC-DMC-TCM-001", "formal/lean/Traceability.lean"],
    hsm_machine: hsm,
  )
}

fn build_verification_zero_muda_enforcer_spec() -> AgentTypeSpec {
  let scanning =
    HierarchicalState(
      name: "ScanningCodeline",
      parent: None,
      entry: ["zero_muda_purity_scan_init"],
      exit: ["scan_completed"],
      transitions: [
        Transition(
          on_signal: "run_purity_scan",
          guard: None,
          do_actions: ["grep_for_bevy_and_graphite"],
          target: ToState("VerifyingPurity"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let verifying =
    HierarchicalState(
      name: "VerifyingPurity",
      parent: None,
      entry: ["evaluating_dependency_graph"],
      exit: ["purity_confirmed"],
      transitions: [
        Transition(
          on_signal: "scan_complete",
          guard: None,
          do_actions: ["certify_zero_muda_purity"],
          target: ToState("PureZeroMuda"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let pure_state =
    HierarchicalState(
      name: "PureZeroMuda",
      parent: None,
      entry: ["zero_muda_100_percent_green"],
      exit: ["purity_recheck_scheduled"],
      transitions: [
        Transition(
          on_signal: "run_purity_scan",
          guard: None,
          do_actions: ["reset_purity_scanner"],
          target: ToState("ScanningCodeline"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "VerificationZeroMudaHSM",
      signals: make_signals(["run_purity_scan", "scan_complete"]),
      guards: ["is_bevy_graphite_zero"],
      actions: [
        "grep_for_bevy_and_graphite", "certify_zero_muda_purity",
        "reset_purity_scanner",
      ],
      root_states: [scanning, verifying, pure_state],
      choices: [],
      initial: #([], "ScanningCodeline"),
    )

  AgentTypeSpec(
    kind: VerificationZeroMudaPurityEnforcer,
    name: "C3I Verification Zero-Muda Purity Enforcer Agent",
    c3i_system: C3iVerification,
    fractal_layer: 0,
    fractal_tag: "#fractal-l0",
    fpp_component_kind: Active,
    base_id: 0x1BC0,
    id_span: 64,
    queue_policy: Assert,
    description: "Proves absolute Zero-Muda compliance: 0 Bevy, 0 Graphite, 0 foreign NIF shared libraries, and pure Erlang graphene_nif.",
    operational_domain: "Zero Bevy & Zero Graphite Purity Enforcement",
    sdlc_phase: "Verification & Gatekeeping",
    sre_resilience_tier: "SIL-6 / Absolute Elimination of Muda",
    evidence_contracts: ["SC-MUDA-001", "contracts/rules/zero-muda-rule.md"],
    hsm_machine: hsm,
  )
}

fn build_sdlc_graph_workflow_orchestrator_spec() -> AgentTypeSpec {
  let active_state =
    HierarchicalState(
      name: "Active",
      parent: None,
      entry: ["init_build_sdlc_graph_workflow_orchestrator_spec"],
      exit: ["stop_build_sdlc_graph_workflow_orchestrator_spec"],
      transitions: [
        Transition(
          on_signal: "tick",
          guard: None,
          do_actions: ["execute_cycle"],
          target: ToState("Active"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "SdlcGraphWorkflowOrchestratorHSM",
      signals: make_signals(["tick"]),
      guards: [],
      actions: ["execute_cycle"],
      root_states: [active_state],
      choices: [],
      initial: #([], "Active"),
    )

  AgentTypeSpec(
    kind: SdlcGraphWorkflowOrchestrator,
    name: "C3I SDLC Graph Workflow Orchestrator Agent",
    c3i_system: C3iSdlc,
    fractal_layer: 5,
    fractal_tag: "#fractal-l5",
    fpp_component_kind: Active,
    base_id: 0x1c00,
    id_span: 64,
    queue_policy: Assert,
    description: "ADK graph workflow execution engine with conditional routing and loops",
    operational_domain: "Workflow Orchestration",
    sdlc_phase: "ADK Graph & Workflows",
    sre_resilience_tier: "SIL-4 / High Availability",
    evidence_contracts: ["SC-ADK-001", "SC-FPP-049"],
    hsm_machine: hsm,
  )
}

fn build_sdlc_session_memory_replay_spec() -> AgentTypeSpec {
  let active_state =
    HierarchicalState(
      name: "Active",
      parent: None,
      entry: ["init_build_sdlc_session_memory_replay_spec"],
      exit: ["stop_build_sdlc_session_memory_replay_spec"],
      transitions: [
        Transition(
          on_signal: "tick",
          guard: None,
          do_actions: ["execute_cycle"],
          target: ToState("Active"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "SdlcSessionMemoryReplayHSM",
      signals: make_signals(["tick"]),
      guards: [],
      actions: ["execute_cycle"],
      root_states: [active_state],
      choices: [],
      initial: #([], "Active"),
    )

  AgentTypeSpec(
    kind: SdlcSessionMemoryReplay,
    name: "C3I SDLC Session Memory Replay Agent",
    c3i_system: C3iSdlc,
    fractal_layer: 4,
    fractal_tag: "#fractal-l4",
    fpp_component_kind: Active,
    base_id: 0x1c40,
    id_span: 64,
    queue_policy: Assert,
    description: "ADK stateful session manager with long-term episodic/semantic memory store",
    operational_domain: "Session & Memory",
    sdlc_phase: "State Persistence & Replay",
    sre_resilience_tier: "SIL-4 / High Availability",
    evidence_contracts: ["SC-ADK-002", "SC-FPP-050"],
    hsm_machine: hsm,
  )
}

fn build_sdlc_a2a_multi_agent_delegation_spec() -> AgentTypeSpec {
  let active_state =
    HierarchicalState(
      name: "Active",
      parent: None,
      entry: ["init_build_sdlc_a2a_multi_agent_delegation_spec"],
      exit: ["stop_build_sdlc_a2a_multi_agent_delegation_spec"],
      transitions: [
        Transition(
          on_signal: "tick",
          guard: None,
          do_actions: ["execute_cycle"],
          target: ToState("Active"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "SdlcA2aMultiAgentDelegationHSM",
      signals: make_signals(["tick"]),
      guards: [],
      actions: ["execute_cycle"],
      root_states: [active_state],
      choices: [],
      initial: #([], "Active"),
    )

  AgentTypeSpec(
    kind: SdlcA2aMultiAgentDelegation,
    name: "C3I SDLC A2A Multi Agent Delegation Agent",
    c3i_system: C3iSdlc,
    fractal_layer: 6,
    fractal_tag: "#fractal-l6",
    fpp_component_kind: Active,
    base_id: 0x1c80,
    id_span: 64,
    queue_policy: Assert,
    description: "ADK Agent-to-Agent horizontal delegation and subagent swarm routing",
    operational_domain: "Multi-Agent Swarm",
    sdlc_phase: "A2A Inter-Agent Protocol",
    sre_resilience_tier: "SIL-4 / High Availability",
    evidence_contracts: ["SC-ADK-003", "SC-FPP-051"],
    hsm_machine: hsm,
  )
}

fn build_sdlc_tool_registry_mcp_bridge_spec() -> AgentTypeSpec {
  let active_state =
    HierarchicalState(
      name: "Active",
      parent: None,
      entry: ["init_build_sdlc_tool_registry_mcp_bridge_spec"],
      exit: ["stop_build_sdlc_tool_registry_mcp_bridge_spec"],
      transitions: [
        Transition(
          on_signal: "tick",
          guard: None,
          do_actions: ["execute_cycle"],
          target: ToState("Active"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "SdlcToolRegistryMcpBridgeHSM",
      signals: make_signals(["tick"]),
      guards: [],
      actions: ["execute_cycle"],
      root_states: [active_state],
      choices: [],
      initial: #([], "Active"),
    )

  AgentTypeSpec(
    kind: SdlcToolRegistryMcpBridge,
    name: "C3I SDLC Tool Registry MCP Bridge Agent",
    c3i_system: C3iSdlc,
    fractal_layer: 3,
    fractal_tag: "#fractal-l3",
    fpp_component_kind: Active,
    base_id: 0x1cc0,
    id_span: 64,
    queue_policy: Assert,
    description: "ADK vertical tool context dispatcher and federated MCP server connector",
    operational_domain: "Tool Execution & MCP",
    sdlc_phase: "MCP Protocol & Schemas",
    sre_resilience_tier: "SIL-4 / High Availability",
    evidence_contracts: ["SC-ADK-004", "SC-FPP-052"],
    hsm_machine: hsm,
  )
}

fn build_sdlc_ontology_infranodus_synthesizer_spec() -> AgentTypeSpec {
  let active_state =
    HierarchicalState(
      name: "Active",
      parent: None,
      entry: ["init_build_sdlc_ontology_infranodus_synthesizer_spec"],
      exit: ["stop_build_sdlc_ontology_infranodus_synthesizer_spec"],
      transitions: [
        Transition(
          on_signal: "tick",
          guard: None,
          do_actions: ["execute_cycle"],
          target: ToState("Active"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "SdlcOntologyInfranodusSynthesizerHSM",
      signals: make_signals(["tick"]),
      guards: [],
      actions: ["execute_cycle"],
      root_states: [active_state],
      choices: [],
      initial: #([], "Active"),
    )

  AgentTypeSpec(
    kind: SdlcOntologyInfranodusSynthesizer,
    name: "C3I SDLC Ontology Infranodus Synthesizer Agent",
    c3i_system: C3iSdlc,
    fractal_layer: 8,
    fractal_tag: "#fractal-l8",
    fpp_component_kind: Active,
    base_id: 0x1d00,
    id_span: 64,
    queue_policy: Assert,
    description: "Infranodus semantic network synthesis, topic modeling, and Notion ontology",
    operational_domain: "Ontology & Semantics",
    sdlc_phase: "Ontology Engineering",
    sre_resilience_tier: "SIL-5 / Safety Critical",
    evidence_contracts: ["SC-ONTO-002", "SC-FPP-053"],
    hsm_machine: hsm,
  )
}

fn build_sdlc_design_system_figma_bridge_spec() -> AgentTypeSpec {
  let active_state =
    HierarchicalState(
      name: "Active",
      parent: None,
      entry: ["init_build_sdlc_design_system_figma_bridge_spec"],
      exit: ["stop_build_sdlc_design_system_figma_bridge_spec"],
      transitions: [
        Transition(
          on_signal: "tick",
          guard: None,
          do_actions: ["execute_cycle"],
          target: ToState("Active"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "SdlcDesignSystemFigmaBridgeHSM",
      signals: make_signals(["tick"]),
      guards: [],
      actions: ["execute_cycle"],
      root_states: [active_state],
      choices: [],
      initial: #([], "Active"),
    )

  AgentTypeSpec(
    kind: SdlcDesignSystemFigmaBridge,
    name: "C3I SDLC Design System Figma Bridge Agent",
    c3i_system: C3iSdlc,
    fractal_layer: 2,
    fractal_tag: "#fractal-l2",
    fpp_component_kind: Active,
    base_id: 0x1d40,
    id_span: 64,
    queue_policy: Assert,
    description: "Figma design contract translator, tokens.json parser, and layout tree generator",
    operational_domain: "Design System & UI",
    sdlc_phase: "Design-to-Code Pipeline",
    sre_resilience_tier: "SIL-3 / Standard",
    evidence_contracts: ["SC-FIGMA-001", "SC-FPP-054"],
    hsm_machine: hsm,
  )
}

fn build_sdlc_gospel_ortac_specification_spec() -> AgentTypeSpec {
  let active_state =
    HierarchicalState(
      name: "Active",
      parent: None,
      entry: ["init_build_sdlc_gospel_ortac_specification_spec"],
      exit: ["stop_build_sdlc_gospel_ortac_specification_spec"],
      transitions: [
        Transition(
          on_signal: "tick",
          guard: None,
          do_actions: ["execute_cycle"],
          target: ToState("Active"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "SdlcGospelOrtacSpecificationHSM",
      signals: make_signals(["tick"]),
      guards: [],
      actions: ["execute_cycle"],
      root_states: [active_state],
      choices: [],
      initial: #([], "Active"),
    )

  AgentTypeSpec(
    kind: SdlcGospelOrtacSpecification,
    name: "C3I SDLC Gospel Ortac Specification Agent",
    c3i_system: C3iSdlc,
    fractal_layer: 1,
    fractal_tag: "#fractal-l1",
    fpp_component_kind: Active,
    base_id: 0x1d80,
    id_span: 64,
    queue_policy: Assert,
    description: "Gospel contract specification synthesizer and Ortac runtime monitoring generator",
    operational_domain: "Contract Specification",
    sdlc_phase: "Formal Contract Synthesis",
    sre_resilience_tier: "SIL-6 / Sovereign Core",
    evidence_contracts: ["SC-GOSPEL-001", "SC-FPP-055"],
    hsm_machine: hsm,
  )
}

fn build_sdlc_algebraic_atlas_router_spec() -> AgentTypeSpec {
  let active_state =
    HierarchicalState(
      name: "Active",
      parent: None,
      entry: ["init_build_sdlc_algebraic_atlas_router_spec"],
      exit: ["stop_build_sdlc_algebraic_atlas_router_spec"],
      transitions: [
        Transition(
          on_signal: "tick",
          guard: None,
          do_actions: ["execute_cycle"],
          target: ToState("Active"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "SdlcAlgebraicAtlasRouterHSM",
      signals: make_signals(["tick"]),
      guards: [],
      actions: ["execute_cycle"],
      root_states: [active_state],
      choices: [],
      initial: #([], "Active"),
    )

  AgentTypeSpec(
    kind: SdlcAlgebraicAtlasRouter,
    name: "C3I SDLC Algebraic Atlas Router Agent",
    c3i_system: C3iSdlc,
    fractal_layer: 7,
    fractal_tag: "#fractal-l7",
    fpp_component_kind: Active,
    base_id: 0x1dc0,
    id_span: 64,
    queue_policy: Assert,
    description: "12-layer Algebraic Atlas coordinator, Route Algebra, and Table/HTML morphisms",
    operational_domain: "Algebraic Atlas",
    sdlc_phase: "Topological Mapping",
    sre_resilience_tier: "SIL-6 / Sovereign Core",
    evidence_contracts: ["SC-ATLAS-001", "SC-FPP-056"],
    hsm_machine: hsm,
  )
}

fn build_sre_runner_lifecycle_hook_supervisor_spec() -> AgentTypeSpec {
  let active_state =
    HierarchicalState(
      name: "Active",
      parent: None,
      entry: ["init_build_sre_runner_lifecycle_hook_supervisor_spec"],
      exit: ["stop_build_sre_runner_lifecycle_hook_supervisor_spec"],
      transitions: [
        Transition(
          on_signal: "tick",
          guard: None,
          do_actions: ["execute_cycle"],
          target: ToState("Active"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "SreRunnerLifecycleHookSupervisorHSM",
      signals: make_signals(["tick"]),
      guards: [],
      actions: ["execute_cycle"],
      root_states: [active_state],
      choices: [],
      initial: #([], "Active"),
    )

  AgentTypeSpec(
    kind: SreRunnerLifecycleHookSupervisor,
    name: "C3I SRE Runner Lifecycle Hook Supervisor Agent",
    c3i_system: C3iSre,
    fractal_layer: 4,
    fractal_tag: "#fractal-l4",
    fpp_component_kind: Active,
    base_id: 0x1e00,
    id_span: 64,
    queue_policy: Assert,
    description: "ADK Runner execution loop supervisor enforcing 6 before/after lifecycle hooks",
    operational_domain: "Runtime Supervision",
    sdlc_phase: "Lifecycle Hook Governance",
    sre_resilience_tier: "SIL-5 / Safety Critical",
    evidence_contracts: ["SC-ADK-005", "SC-FPP-057"],
    hsm_machine: hsm,
  )
}

fn build_sre_plugin_policy_guardrail_spec() -> AgentTypeSpec {
  let active_state =
    HierarchicalState(
      name: "Active",
      parent: None,
      entry: ["init_build_sre_plugin_policy_guardrail_spec"],
      exit: ["stop_build_sre_plugin_policy_guardrail_spec"],
      transitions: [
        Transition(
          on_signal: "tick",
          guard: None,
          do_actions: ["execute_cycle"],
          target: ToState("Active"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "SrePluginPolicyGuardrailHSM",
      signals: make_signals(["tick"]),
      guards: [],
      actions: ["execute_cycle"],
      root_states: [active_state],
      choices: [],
      initial: #([], "Active"),
    )

  AgentTypeSpec(
    kind: SrePluginPolicyGuardrail,
    name: "C3I SRE Plugin Policy Guardrail Agent",
    c3i_system: C3iSre,
    fractal_layer: 0,
    fractal_tag: "#fractal-l0",
    fpp_component_kind: Active,
    base_id: 0x1e40,
    id_span: 64,
    queue_policy: Assert,
    description: "ADK BasePlugin security policies, input/output content filtering, and quota locks",
    operational_domain: "Security Guardrails",
    sdlc_phase: "Policy Enforcement",
    sre_resilience_tier: "SIL-6 / Sovereign Core",
    evidence_contracts: ["SC-ADK-006", "SC-FPP-058"],
    hsm_machine: hsm,
  )
}

fn build_sre_open_telemetry_span_tracer_spec() -> AgentTypeSpec {
  let active_state =
    HierarchicalState(
      name: "Active",
      parent: None,
      entry: ["init_build_sre_open_telemetry_span_tracer_spec"],
      exit: ["stop_build_sre_open_telemetry_span_tracer_spec"],
      transitions: [
        Transition(
          on_signal: "tick",
          guard: None,
          do_actions: ["execute_cycle"],
          target: ToState("Active"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "SreOpenTelemetrySpanTracerHSM",
      signals: make_signals(["tick"]),
      guards: [],
      actions: ["execute_cycle"],
      root_states: [active_state],
      choices: [],
      initial: #([], "Active"),
    )

  AgentTypeSpec(
    kind: SreOpenTelemetrySpanTracer,
    name: "C3I SRE OpenTelemetry Span Tracer Agent",
    c3i_system: C3iSre,
    fractal_layer: 2,
    fractal_tag: "#fractal-l2",
    fpp_component_kind: Active,
    base_id: 0x1e80,
    id_span: 64,
    queue_policy: Assert,
    description: "Universal OpenTelemetry distributed span tracer over Zenoh pub/sub mesh",
    operational_domain: "Telemetry & Observability",
    sdlc_phase: "OTel Tracing & Context",
    sre_resilience_tier: "SIL-4 / High Availability",
    evidence_contracts: ["SC-OTEL-002", "SC-FPP-059"],
    hsm_machine: hsm,
  )
}

fn build_sre_sa_plan_task_leaser_spec() -> AgentTypeSpec {
  let active_state =
    HierarchicalState(
      name: "Active",
      parent: None,
      entry: ["init_build_sre_sa_plan_task_leaser_spec"],
      exit: ["stop_build_sre_sa_plan_task_leaser_spec"],
      transitions: [
        Transition(
          on_signal: "tick",
          guard: None,
          do_actions: ["execute_cycle"],
          target: ToState("Active"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "SreSaPlanTaskLeaserHSM",
      signals: make_signals(["tick"]),
      guards: [],
      actions: ["execute_cycle"],
      root_states: [active_state],
      choices: [],
      initial: #([], "Active"),
    )

  AgentTypeSpec(
    kind: SreSaPlanTaskLeaser,
    name: "C3I SRE SaPlan Task Leaser Agent",
    c3i_system: C3iSre,
    fractal_layer: 3,
    fractal_tag: "#fractal-l3",
    fpp_component_kind: Active,
    base_id: 0x1ec0,
    id_span: 64,
    queue_policy: Assert,
    description: "Sa-plan durable workflow coordinator, at-least-once task leasing, and idempotent jobs",
    operational_domain: "Task Durability",
    sdlc_phase: "Durable Workflow Leasing",
    sre_resilience_tier: "SIL-5 / Safety Critical",
    evidence_contracts: ["SC-SAPLAN-001", "SC-FPP-060"],
    hsm_machine: hsm,
  )
}

fn build_sre_rete_fail_closed_admission_spec() -> AgentTypeSpec {
  let active_state =
    HierarchicalState(
      name: "Active",
      parent: None,
      entry: ["init_build_sre_rete_fail_closed_admission_spec"],
      exit: ["stop_build_sre_rete_fail_closed_admission_spec"],
      transitions: [
        Transition(
          on_signal: "tick",
          guard: None,
          do_actions: ["execute_cycle"],
          target: ToState("Active"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "SreReteFailClosedAdmissionHSM",
      signals: make_signals(["tick"]),
      guards: [],
      actions: ["execute_cycle"],
      root_states: [active_state],
      choices: [],
      initial: #([], "Active"),
    )

  AgentTypeSpec(
    kind: SreReteFailClosedAdmission,
    name: "C3I SRE Rete Fail Closed Admission Agent",
    c3i_system: C3iSre,
    fractal_layer: 0,
    fractal_tag: "#fractal-l0",
    fpp_component_kind: Active,
    base_id: 0x1f00,
    id_span: 64,
    queue_policy: Assert,
    description: "Rete-UL forward-chaining rule engine enforcing fail-closed state transition gates",
    operational_domain: "Rule Admission & Gate",
    sdlc_phase: "Fail-Closed Governance",
    sre_resilience_tier: "SIL-6 / Sovereign Core",
    evidence_contracts: ["SC-RETE-001", "SC-FPP-061"],
    hsm_machine: hsm,
  )
}

fn build_sre_forecast_predictive_preflight_spec() -> AgentTypeSpec {
  let active_state =
    HierarchicalState(
      name: "Active",
      parent: None,
      entry: ["init_build_sre_forecast_predictive_preflight_spec"],
      exit: ["stop_build_sre_forecast_predictive_preflight_spec"],
      transitions: [
        Transition(
          on_signal: "tick",
          guard: None,
          do_actions: ["execute_cycle"],
          target: ToState("Active"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "SreForecastPredictivePreflightHSM",
      signals: make_signals(["tick"]),
      guards: [],
      actions: ["execute_cycle"],
      root_states: [active_state],
      choices: [],
      initial: #([], "Active"),
    )

  AgentTypeSpec(
    kind: SreForecastPredictivePreflight,
    name: "C3I SRE Forecast Predictive Preflight Agent",
    c3i_system: C3iSre,
    fractal_layer: 5,
    fractal_tag: "#fractal-l5",
    fpp_component_kind: Active,
    base_id: 0x1f40,
    id_span: 64,
    queue_policy: Assert,
    description: "Predictive resource preflight, Bayesian execution duration learning, and cost control",
    operational_domain: "Predictive Operations",
    sdlc_phase: "Preflight Resource Planning",
    sre_resilience_tier: "SIL-4 / High Availability",
    evidence_contracts: ["SC-FORECAST-001", "SC-FPP-062"],
    hsm_machine: hsm,
  )
}

fn build_sre_stpa_safety_controller_spec() -> AgentTypeSpec {
  let active_state =
    HierarchicalState(
      name: "Active",
      parent: None,
      entry: ["init_build_sre_stpa_safety_controller_spec"],
      exit: ["stop_build_sre_stpa_safety_controller_spec"],
      transitions: [
        Transition(
          on_signal: "tick",
          guard: None,
          do_actions: ["execute_cycle"],
          target: ToState("Active"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "SreStpaSafetyControllerHSM",
      signals: make_signals(["tick"]),
      guards: [],
      actions: ["execute_cycle"],
      root_states: [active_state],
      choices: [],
      initial: #([], "Active"),
    )

  AgentTypeSpec(
    kind: SreStpaSafetyController,
    name: "C3I SRE STPA Safety Controller Agent",
    c3i_system: C3iSre,
    fractal_layer: 0,
    fractal_tag: "#fractal-l0",
    fpp_component_kind: Active,
    base_id: 0x1f80,
    id_span: 64,
    queue_policy: Assert,
    description: "STAMP/STPA safety control loop, Unsafe Control Action (UCA) interception, and FMEA",
    operational_domain: "Safety Control Loop",
    sdlc_phase: "Hazard & UCA Prevention",
    sre_resilience_tier: "SIL-6 / Sovereign Core",
    evidence_contracts: ["SC-STPA-001", "SC-FPP-063"],
    hsm_machine: hsm,
  )
}

fn build_sre_database_actor_wal_serializer_spec() -> AgentTypeSpec {
  let active_state =
    HierarchicalState(
      name: "Active",
      parent: None,
      entry: ["init_build_sre_database_actor_wal_serializer_spec"],
      exit: ["stop_build_sre_database_actor_wal_serializer_spec"],
      transitions: [
        Transition(
          on_signal: "tick",
          guard: None,
          do_actions: ["execute_cycle"],
          target: ToState("Active"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "SreDatabaseActorWalSerializerHSM",
      signals: make_signals(["tick"]),
      guards: [],
      actions: ["execute_cycle"],
      root_states: [active_state],
      choices: [],
      initial: #([], "Active"),
    )

  AgentTypeSpec(
    kind: SreDatabaseActorWalSerializer,
    name: "C3I SRE Database Actor WAL Serializer Agent",
    c3i_system: C3iSre,
    fractal_layer: 3,
    fractal_tag: "#fractal-l3",
    fpp_component_kind: Active,
    base_id: 0x1fc0,
    id_span: 64,
    queue_policy: Assert,
    description: "SQLite Db actor evidence serializer enforcing WAL append-only Zero-Trust records",
    operational_domain: "Evidence Persistence",
    sdlc_phase: "Durable WAL Storage",
    sre_resilience_tier: "SIL-6 / Sovereign Core",
    evidence_contracts: ["SC-DB-001", "SC-FPP-064"],
    hsm_machine: hsm,
  )
}

fn build_verification_adk_eval_benchmark_spec() -> AgentTypeSpec {
  let active_state =
    HierarchicalState(
      name: "Active",
      parent: None,
      entry: ["init_build_verification_adk_eval_benchmark_spec"],
      exit: ["stop_build_verification_adk_eval_benchmark_spec"],
      transitions: [
        Transition(
          on_signal: "tick",
          guard: None,
          do_actions: ["execute_cycle"],
          target: ToState("Active"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "VerificationAdkEvalBenchmarkHSM",
      signals: make_signals(["tick"]),
      guards: [],
      actions: ["execute_cycle"],
      root_states: [active_state],
      choices: [],
      initial: #([], "Active"),
    )

  AgentTypeSpec(
    kind: VerificationAdkEvalBenchmark,
    name: "C3I Verification ADK Eval Benchmark Agent",
    c3i_system: C3iVerification,
    fractal_layer: 5,
    fractal_tag: "#fractal-l5",
    fpp_component_kind: Active,
    base_id: 0x2000,
    id_span: 64,
    queue_policy: Assert,
    description: "ADK evaluation benchmark executor (adk eval), criteria scoring, and rubric certifier",
    operational_domain: "Benchmark Evaluation",
    sdlc_phase: "Automated Agent Scoring",
    sre_resilience_tier: "SIL-5 / Safety Critical",
    evidence_contracts: ["SC-ADK-007", "SC-FPP-065"],
    hsm_machine: hsm,
  )
}

fn build_verification_simulation_environment_spec() -> AgentTypeSpec {
  let active_state =
    HierarchicalState(
      name: "Active",
      parent: None,
      entry: ["init_build_verification_simulation_environment_spec"],
      exit: ["stop_build_verification_simulation_environment_spec"],
      transitions: [
        Transition(
          on_signal: "tick",
          guard: None,
          do_actions: ["execute_cycle"],
          target: ToState("Active"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "VerificationSimulationEnvironmentHSM",
      signals: make_signals(["tick"]),
      guards: [],
      actions: ["execute_cycle"],
      root_states: [active_state],
      choices: [],
      initial: #([], "Active"),
    )

  AgentTypeSpec(
    kind: VerificationSimulationEnvironment,
    name: "C3I Verification Simulation Environment Agent",
    c3i_system: C3iVerification,
    fractal_layer: 6,
    fractal_tag: "#fractal-l6",
    fpp_component_kind: Active,
    base_id: 0x2040,
    id_span: 64,
    queue_policy: Assert,
    description: "ADK user and environment simulator, synthetic input generator, and multi-turn tester",
    operational_domain: "Simulation & Replay",
    sdlc_phase: "Synthetic Dialogue Testing",
    sre_resilience_tier: "SIL-4 / High Availability",
    evidence_contracts: ["SC-ADK-008", "SC-FPP-066"],
    hsm_machine: hsm,
  )
}

fn build_verification_lean_formal_proof_oracle_spec() -> AgentTypeSpec {
  let active_state =
    HierarchicalState(
      name: "Active",
      parent: None,
      entry: ["init_build_verification_lean_formal_proof_oracle_spec"],
      exit: ["stop_build_verification_lean_formal_proof_oracle_spec"],
      transitions: [
        Transition(
          on_signal: "tick",
          guard: None,
          do_actions: ["execute_cycle"],
          target: ToState("Active"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "VerificationLeanFormalProofOracleHSM",
      signals: make_signals(["tick"]),
      guards: [],
      actions: ["execute_cycle"],
      root_states: [active_state],
      choices: [],
      initial: #([], "Active"),
    )

  AgentTypeSpec(
    kind: VerificationLeanFormalProofOracle,
    name: "C3I Verification Lean Formal Proof Oracle Agent",
    c3i_system: C3iVerification,
    fractal_layer: 0,
    fractal_tag: "#fractal-l0",
    fpp_component_kind: Active,
    base_id: 0x2080,
    id_span: 64,
    queue_policy: Assert,
    description: "Lean 4 coordinate conservation oracle (Delta T_13 = 0) and TwoLattice_STM verifier",
    operational_domain: "Formal Proofs",
    sdlc_phase: "Mathematical Verification",
    sre_resilience_tier: "SIL-6 / Sovereign Core",
    evidence_contracts: ["SC-LEAN-001", "SC-FPP-067"],
    hsm_machine: hsm,
  )
}

fn build_verification_pinned_otp_differential_spec() -> AgentTypeSpec {
  let active_state =
    HierarchicalState(
      name: "Active",
      parent: None,
      entry: ["init_build_verification_pinned_otp_differential_spec"],
      exit: ["stop_build_verification_pinned_otp_differential_spec"],
      transitions: [
        Transition(
          on_signal: "tick",
          guard: None,
          do_actions: ["execute_cycle"],
          target: ToState("Active"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "VerificationPinnedOtpDifferentialHSM",
      signals: make_signals(["tick"]),
      guards: [],
      actions: ["execute_cycle"],
      root_states: [active_state],
      choices: [],
      initial: #([], "Active"),
    )

  AgentTypeSpec(
    kind: VerificationPinnedOtpDifferential,
    name: "C3I Verification Pinned OTP Differential Agent",
    c3i_system: C3iVerification,
    fractal_layer: 1,
    fractal_tag: "#fractal-l1",
    fpp_component_kind: Active,
    base_id: 0x20c0,
    id_span: 64,
    queue_policy: Assert,
    description: "Pinned OTP 30 differential oracle, opcode conformance rachet, and corpus evaluator",
    operational_domain: "Differential Testing",
    sdlc_phase: "OTP Conformance Ratchet",
    sre_resilience_tier: "SIL-6 / Sovereign Core",
    evidence_contracts: ["SC-OTP-001", "SC-FPP-068"],
    hsm_machine: hsm,
  )
}

fn build_verification_mutation_adequacy_killer_spec() -> AgentTypeSpec {
  let active_state =
    HierarchicalState(
      name: "Active",
      parent: None,
      entry: ["init_build_verification_mutation_adequacy_killer_spec"],
      exit: ["stop_build_verification_mutation_adequacy_killer_spec"],
      transitions: [
        Transition(
          on_signal: "tick",
          guard: None,
          do_actions: ["execute_cycle"],
          target: ToState("Active"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "VerificationMutationAdequacyKillerHSM",
      signals: make_signals(["tick"]),
      guards: [],
      actions: ["execute_cycle"],
      root_states: [active_state],
      choices: [],
      initial: #([], "Active"),
    )

  AgentTypeSpec(
    kind: VerificationMutationAdequacyKiller,
    name: "C3I Verification Mutation Adequacy Killer Agent",
    c3i_system: C3iVerification,
    fractal_layer: 2,
    fractal_tag: "#fractal-l2",
    fpp_component_kind: Active,
    base_id: 0x2100,
    id_span: 64,
    queue_policy: Assert,
    description: "Causal mutant generator and kill score analyzer (MUTATION_LOG.md) across test suites",
    operational_domain: "Mutation Testing",
    sdlc_phase: "Mutant Adequacy Scoring",
    sre_resilience_tier: "SIL-5 / Safety Critical",
    evidence_contracts: ["SC-MUTATION-001", "SC-FPP-069"],
    hsm_machine: hsm,
  )
}

fn build_verification_sheaf_gluing_harmonizer_spec() -> AgentTypeSpec {
  let active_state =
    HierarchicalState(
      name: "Active",
      parent: None,
      entry: ["init_build_verification_sheaf_gluing_harmonizer_spec"],
      exit: ["stop_build_verification_sheaf_gluing_harmonizer_spec"],
      transitions: [
        Transition(
          on_signal: "tick",
          guard: None,
          do_actions: ["execute_cycle"],
          target: ToState("Active"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "VerificationSheafGluingHarmonizerHSM",
      signals: make_signals(["tick"]),
      guards: [],
      actions: ["execute_cycle"],
      root_states: [active_state],
      choices: [],
      initial: #([], "Active"),
    )

  AgentTypeSpec(
    kind: VerificationSheafGluingHarmonizer,
    name: "C3I Verification Sheaf Gluing Harmonizer Agent",
    c3i_system: C3iVerification,
    fractal_layer: 7,
    fractal_tag: "#fractal-l7",
    fpp_component_kind: Active,
    base_id: 0x2140,
    id_span: 64,
    queue_policy: Assert,
    description: "Sheaf-theoretic consistency verifier ensuring local section gluing on boundaries",
    operational_domain: "Sheaf Verification",
    sdlc_phase: "Algebraic Consistency",
    sre_resilience_tier: "SIL-6 / Sovereign Core",
    evidence_contracts: ["SC-SHEAF-001", "SC-FPP-070"],
    hsm_machine: hsm,
  )
}

fn build_verification_playwright_control_auditor_spec() -> AgentTypeSpec {
  let active_state =
    HierarchicalState(
      name: "Active",
      parent: None,
      entry: ["init_build_verification_playwright_control_auditor_spec"],
      exit: ["stop_build_verification_playwright_control_auditor_spec"],
      transitions: [
        Transition(
          on_signal: "tick",
          guard: None,
          do_actions: ["execute_cycle"],
          target: ToState("Active"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "VerificationPlaywrightControlAuditorHSM",
      signals: make_signals(["tick"]),
      guards: [],
      actions: ["execute_cycle"],
      root_states: [active_state],
      choices: [],
      initial: #([], "Active"),
    )

  AgentTypeSpec(
    kind: VerificationPlaywrightControlAuditor,
    name: "C3I Verification Playwright Control Auditor Agent",
    c3i_system: C3iVerification,
    fractal_layer: 4,
    fractal_tag: "#fractal-l4",
    fpp_component_kind: Active,
    base_id: 0x2180,
    id_span: 64,
    queue_policy: Assert,
    description: "Playwright upstream control surface auditor, headless CDP tester, and visual oracle",
    operational_domain: "Browser Automation",
    sdlc_phase: "End-to-End Testing",
    sre_resilience_tier: "SIL-4 / High Availability",
    evidence_contracts: ["SC-PLAYWRIGHT-001", "SC-FPP-071"],
    hsm_machine: hsm,
  )
}

fn build_verification_zk_km_knowledge_currency_spec() -> AgentTypeSpec {
  let active_state =
    HierarchicalState(
      name: "Active",
      parent: None,
      entry: ["init_build_verification_zk_km_knowledge_currency_spec"],
      exit: ["stop_build_verification_zk_km_knowledge_currency_spec"],
      transitions: [
        Transition(
          on_signal: "tick",
          guard: None,
          do_actions: ["execute_cycle"],
          target: ToState("Active"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let hsm =
    HierarchicalMachine(
      machine_name: "VerificationZkKmKnowledgeCurrencyHSM",
      signals: make_signals(["tick"]),
      guards: [],
      actions: ["execute_cycle"],
      root_states: [active_state],
      choices: [],
      initial: #([], "Active"),
    )

  AgentTypeSpec(
    kind: VerificationZkKmKnowledgeCurrency,
    name: "C3I Verification ZK KM Knowledge Currency Agent",
    c3i_system: C3iVerification,
    fractal_layer: 8,
    fractal_tag: "#fractal-l8",
    fpp_component_kind: Active,
    base_id: 0x21c0,
    id_span: 64,
    queue_policy: Assert,
    description: "ZK anomalies detector, wiki AST validator, and document registry currency sync",
    operational_domain: "Knowledge Integrity",
    sdlc_phase: "Currency Certification",
    sre_resilience_tier: "SIL-5 / Safety Critical",
    evidence_contracts: ["SC-KM-001", "SC-FPP-072"],
    hsm_machine: hsm,
  )
}

pub fn all_agent_types() -> List(AgentTypeSpec) {
  [
    build_guardian_spec(),
    build_flight_controller_spec(),
    build_telemetry_spec(),
    build_prm_db_spec(),
    build_mission_phase_spec(),
    build_sre_sentinel_spec(),
    build_cybernetic_immune_spec(),
    build_cognitive_ooda_spec(),
    build_swarm_mesh_spec(),
    build_ground_gateway_spec(),
    build_living_meta_spec(),
    build_formal_oracle_spec(),
    build_cockpit_telemetry_spec(),
    build_payload_science_spec(),
    build_storage_custodian_spec(),
    build_km_sync_spec(),
    build_hardware_drive_interlock_spec(),
    build_rocha_cut_guard_spec(),
    build_reduction_scheduler_spec(),
    build_substrate_reactor_spec(),
    build_linear_arena_reclaimer_spec(),
    build_lockless_hamt_spec(),
    build_tagged_pointer_guard_spec(),
    build_hierarchical_timer_wheel_spec(),
    build_mcdc_tap_spec(),
    build_crash_wal_spec(),
    build_differential_bisim_spec(),
    build_appup_coordinator_spec(),
    build_slm_bif_spec(),
    build_fast_pattern_filter_spec(),
    build_epidemic_gossip_spec(),
    build_bytecode_synthesizer_spec(),
    build_sdlc_arch_synth_spec(),
    build_sdlc_contract_gen_spec(),
    build_sdlc_static_analysis_spec(),
    build_sdlc_release_packager_spec(),
    build_sdlc_doc_sync_spec(),
    build_sdlc_evolution_governor_spec(),
    build_sre_lyapunov_detector_spec(),
    build_sre_chaos_injector_spec(),
    build_sre_freshness_monitor_spec(),
    build_sre_cpu_budget_governor_spec(),
    build_verification_checklist_auditor_spec(),
    build_verification_math_gate_certifier_spec(),
    build_verification_nine_modality_executor_spec(),
    build_verification_browser_matrix_tester_spec(),
    build_verification_tcm_protector_spec(),
    build_verification_zero_muda_enforcer_spec(),
    build_sdlc_graph_workflow_orchestrator_spec(),
    build_sdlc_session_memory_replay_spec(),
    build_sdlc_a2a_multi_agent_delegation_spec(),
    build_sdlc_tool_registry_mcp_bridge_spec(),
    build_sdlc_ontology_infranodus_synthesizer_spec(),
    build_sdlc_design_system_figma_bridge_spec(),
    build_sdlc_gospel_ortac_specification_spec(),
    build_sdlc_algebraic_atlas_router_spec(),
    build_sre_runner_lifecycle_hook_supervisor_spec(),
    build_sre_plugin_policy_guardrail_spec(),
    build_sre_open_telemetry_span_tracer_spec(),
    build_sre_sa_plan_task_leaser_spec(),
    build_sre_rete_fail_closed_admission_spec(),
    build_sre_forecast_predictive_preflight_spec(),
    build_sre_stpa_safety_controller_spec(),
    build_sre_database_actor_wal_serializer_spec(),
    build_verification_adk_eval_benchmark_spec(),
    build_verification_simulation_environment_spec(),
    build_verification_lean_formal_proof_oracle_spec(),
    build_verification_pinned_otp_differential_spec(),
    build_verification_mutation_adequacy_killer_spec(),
    build_verification_sheaf_gluing_harmonizer_spec(),
    build_verification_playwright_control_auditor_spec(),
    build_verification_zk_km_knowledge_currency_spec(),
  ]
}

pub fn find_agent_type_spec(kind: AgentKind) -> Result(AgentTypeSpec, Nil) {
  let all = all_agent_types()
  list.find(all, fn(spec) { spec.kind == kind })
}

pub fn sdlc_agents() -> List(AgentTypeSpec) {
  list.filter(all_agent_types(), fn(s) { s.c3i_system == C3iSdlc })
}

pub fn sre_agents() -> List(AgentTypeSpec) {
  list.filter(all_agent_types(), fn(s) { s.c3i_system == C3iSre })
}

pub fn verification_agents() -> List(AgentTypeSpec) {
  list.filter(all_agent_types(), fn(s) { s.c3i_system == C3iVerification })
}

pub fn filter_by_c3i_system(
  specs: List(AgentTypeSpec),
  sys: C3iSystem,
) -> List(AgentTypeSpec) {
  list.filter(specs, fn(s) { s.c3i_system == sys })
}

/// Proves that all 16 agent base-ID windows [base_id, base_id + id_span) are
/// pairwise disjoint. Fails closed if any overlap is detected (DMC Contract).
pub fn verify_agent_base_id_disjointness(specs: List(AgentTypeSpec)) -> Bool {
  let intervals =
    list.map(specs, fn(s) { #(s.name, s.base_id, s.base_id + s.id_span) })

  check_pairwise_intervals(intervals)
}

fn check_pairwise_intervals(intervals: List(#(String, Int, Int))) -> Bool {
  case intervals {
    [] -> True
    [_] -> True
    [#(_name1, low1, high1), ..rest] -> {
      let overlaps =
        list.any(rest, fn(pair) {
          let #(_name2, low2, high2) = pair
          // Overlap condition: max(low1, low2) < min(high1, high2)
          let max_low = int.max(low1, low2)
          let min_high = int.min(high1, high2)
          max_low < min_high
        })
      case overlaps {
        True -> False
        False -> check_pairwise_intervals(rest)
      }
    }
  }
}

// =============================================================================
// JSON Serialization
// =============================================================================

pub fn encode_agent_type_spec_json(spec: AgentTypeSpec) -> json.Json {
  json.object([
    #("kind", json.string(agent_kind_to_string(spec.kind))),
    #("name", json.string(spec.name)),
    #("c3i_system", json.string(c3i_system_to_string(spec.c3i_system))),
    #("fractal_layer", json.int(spec.fractal_layer)),
    #("fractal_tag", json.string(spec.fractal_tag)),
    #("base_id", json.int(spec.base_id)),
    #("id_span", json.int(spec.id_span)),
    #("description", json.string(spec.description)),
    #("operational_domain", json.string(spec.operational_domain)),
    #("sdlc_phase", json.string(spec.sdlc_phase)),
    #("sre_resilience_tier", json.string(spec.sre_resilience_tier)),
    #(
      "evidence_contracts",
      json.array(spec.evidence_contracts, of: json.string),
    ),
  ])
}

pub fn encode_agent_catalog_json(specs: List(AgentTypeSpec)) -> String {
  let sdlc_count = list.count(specs, fn(s) { s.c3i_system == C3iSdlc })
  let sre_count = list.count(specs, fn(s) { s.c3i_system == C3iSre })
  let ver_count = list.count(specs, fn(s) { s.c3i_system == C3iVerification })

  json.object([
    #("status", json.string("ok")),
    #("total_agent_types", json.int(list.length(specs))),
    #("sdlc_agents_count", json.int(sdlc_count)),
    #("sre_agents_count", json.int(sre_count)),
    #("verification_agents_count", json.int(ver_count)),
    #("contract", json.string("SC-FPP-AGENT-TAXONOMY-001")),
    #("agents", json.array(specs, of: encode_agent_type_spec_json)),
  ])
  |> json.to_string
}
