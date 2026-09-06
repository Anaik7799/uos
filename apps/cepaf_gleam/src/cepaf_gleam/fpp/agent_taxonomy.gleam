//// =============================================================================
//// [UOS-FPP-AGENT-TAXONOMY] NASA JPL F Prime / FPP Aerospace Agent Taxonomy
//// =============================================================================
//// Formal specification of all 16 canonical agent types created via the FPP
//// pure BEAM substrate across all fractal layers (L0..L9), components, SDLC,
//// SRE resilience tiers, and evidence systems.
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
    name: "Constitutional Guardian Agent",
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
    name: "Deterministic Flight Controller Agent",
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
    name: "Avionics Telemetry & Packetizer Agent",
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
    name: "Non-Volatile Parameter Database Agent",
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
    name: "Autonomous Mission Phase HSM Agent",
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
    name: "SRE Sentinel & Lyapunov Health Agent",
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
    name: "Cybernetic Immune & FDIR Agent",
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
    name: "Cognitive OODA & Intent Reasoning Agent",
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
    name: "Swarm Mesh & Ecosystem Agent",
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
    name: "Ground Gateway & DTN Agent",
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
    name: "Living Biomorphic Meta-Evolution Agent",
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
    name: "Formal Verification & Gospel Parity Agent",
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
    name: "AG-UI & A2UI Tri-Modal Cockpit Agent",
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
    name: "Autonomous Science & Payload Agent",
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
    name: "Hardware Interlock & Storage Custodian Agent",
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
    name: "Knowledge Triad (#km-triad) Sync Agent",
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
    name: "Hardware Drive Interlock Agent",
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
    name: "Rocha Semiotic Cut Guard Agent",
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
    name: "Deterministic Reduction Scheduler Agent",
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
    name: "Substrate Reactor Agent",
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
    name: "Linear Arena Reclaimer Agent",
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
    name: "Lockless HAMT Storage Agent",
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
    name: "Tagged Pointer Guard Agent",
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
    name: "Hierarchical Timer Wheel Agent",
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
    name: "MC/DC Avionics TAP Agent",
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
    name: "Crash WAL Replay Agent",
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
    name: "Differential Bisimulation Agent",
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
    name: "Appup Hot Reload Coordinator Agent",
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
    name: "SLM BIF Inference Agent",
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
    name: "Fast Pattern Filter Agent",
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
    name: "Epidemic Gossip Agent",
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
    name: "Dynamic Agent Bytecode Synthesizer Agent",
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
  ]
}

pub fn find_agent_type_spec(kind: AgentKind) -> Result(AgentTypeSpec, Nil) {
  let all = all_agent_types()
  list.find(all, fn(spec) { spec.kind == kind })
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
  json.object([
    #("status", json.string("ok")),
    #("total_agent_types", json.int(list.length(specs))),
    #("contract", json.string("SC-FPP-AGENT-TAXONOMY-001")),
    #("agents", json.array(specs, of: encode_agent_type_spec_json)),
  ])
  |> json.to_string
}
