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

fn check_pairwise_intervals(
  intervals: List(#(String, Int, Int)),
) -> Bool {
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
