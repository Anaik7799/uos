//// =============================================================================
//// [UOS-FPP-MIQ-TEST] Test Suite for Harness-Bionic FPP MIQ Services & Swarm Mapping
//// =============================================================================

import cepaf_gleam/fpp/agent_taxonomy.{
  AvionicsTelemetry, CognitiveOodaIntent, ConstitutionalGuardian,
  CyberneticImmune, DeterministicFlightController, FormalOracle, GroundGateway,
  LivingMetaEvolution, MissionPhaseHsm, ParameterDatabase, PayloadScience,
  SreSentinel, StorageCustodian, SwarmMesh,
}
import cepaf_gleam/fpp/intent.{DispatchFlightCommand, FlightIntent}
import cepaf_gleam/fpp/miq_services.{
  BayesianCriticRole, ByzantineSentinelRole, ChronoArbiterRole, ConductorRole,
  CryptographicSentinelRole, CyberneticNavigatorRole, FastOodaService,
  FluidicControllerRole, KinematicWeaverRole, KnowledgeConservatorRole,
  NeuralWeaverRole, Output, QuantumArbiterRole, RavenService, RuliadService,
  SensoriumRole, SopContainmentService, StpaService, SwarmHiveMindRole,
  SyncInput, SynthesizerRole, TopologistRole, auto_allocate_miq,
  fpp_fast_ooda_cycle, fpp_raven_synthesize, fpp_ruliad_search_rule_space,
  fpp_stpa_validate, harness_role_to_string, map_harness_role_to_agent_kind,
}
import gleam/list
import gleeunit/should

pub fn harness_role_homomorphism_test() {
  // Test that all 15 Harness-Bionic Swarm Council roles map to UOS Agent Kinds
  map_harness_role_to_agent_kind(SynthesizerRole)
  |> should.equal(GroundGateway)

  map_harness_role_to_agent_kind(CyberneticNavigatorRole)
  |> should.equal(CognitiveOodaIntent)

  map_harness_role_to_agent_kind(KnowledgeConservatorRole)
  |> should.equal(ParameterDatabase)

  map_harness_role_to_agent_kind(BayesianCriticRole)
  |> should.equal(PayloadScience)

  map_harness_role_to_agent_kind(NeuralWeaverRole)
  |> should.equal(LivingMetaEvolution)

  map_harness_role_to_agent_kind(ConductorRole)
  |> should.equal(MissionPhaseHsm)

  map_harness_role_to_agent_kind(TopologistRole)
  |> should.equal(CyberneticImmune)

  map_harness_role_to_agent_kind(SensoriumRole)
  |> should.equal(AvionicsTelemetry)

  map_harness_role_to_agent_kind(ByzantineSentinelRole)
  |> should.equal(ConstitutionalGuardian)

  map_harness_role_to_agent_kind(ChronoArbiterRole)
  |> should.equal(SreSentinel)

  map_harness_role_to_agent_kind(CryptographicSentinelRole)
  |> should.equal(StorageCustodian)

  map_harness_role_to_agent_kind(QuantumArbiterRole)
  |> should.equal(FormalOracle)

  map_harness_role_to_agent_kind(KinematicWeaverRole)
  |> should.equal(DeterministicFlightController)

  map_harness_role_to_agent_kind(FluidicControllerRole)
  |> should.equal(DeterministicFlightController)

  map_harness_role_to_agent_kind(SwarmHiveMindRole)
  |> should.equal(SwarmMesh)

  harness_role_to_string(SynthesizerRole)
  |> should.equal("Synthesizer")
}

pub fn fpp_stpa_validate_nominal_test() {
  let valid_intent =
    FlightIntent(
      intent_id: "INT-001",
      actor: "CyberneticNavigator",
      verb: DispatchFlightCommand(opcode: 0x100, args: ["nominal"]),
      target_instance: "cmdDisp",
      target_device_serial: "STORAGE_NVME_BACKUP_001",
      precondition_guard: True,
      formal_proof_ref: "formal/lean/Traceability.lean",
    )

  case fpp_stpa_validate(SyncInput(valid_intent)) {
    Output(Ok(constraints)) -> {
      let is_valid = list.length(constraints) >= 4
      is_valid |> should.equal(True)
    }
    _ -> should.fail()
  }
}

pub fn fpp_stpa_validate_blocked_locked_nvme_test() {
  let hostile_intent =
    FlightIntent(
      intent_id: "INT-002-HOSTILE",
      actor: "UnverifiedAgent",
      verb: DispatchFlightCommand(opcode: 0x666, args: ["format"]),
      target_instance: "storageCust",
      target_device_serial: "25503L801736",
      precondition_guard: True,
      formal_proof_ref: "unverified",
    )

  case fpp_stpa_validate(SyncInput(hostile_intent)) {
    Output(Error(reason)) -> {
      should.equal(
        reason,
        "STPA_VIOLATION: CRITICAL: System OS NVMe 25503L801736 is hardware-locked against all mutations (DAL-A Safety Contract)",
      )
    }
    _ -> should.fail()
  }
}

pub fn fpp_fast_ooda_cycle_test() {
  let intent =
    FlightIntent(
      intent_id: "INT-003",
      actor: "CognitiveAgent",
      verb: DispatchFlightCommand(opcode: 0x200, args: []),
      target_instance: "telemetryCollector",
      target_device_serial: "DEV-OK",
      precondition_guard: True,
      formal_proof_ref: "ref-003",
    )

  let port_out =
    fpp_fast_ooda_cycle(SyncInput("telemetry_stream_nominal"), intent)
  case port_out {
    Output(res_intent) -> res_intent.intent_id |> should.equal("INT-003")
    _ -> should.fail()
  }
}

pub fn fpp_raven_and_ruliad_test() {
  let raven_res = fpp_raven_synthesize("navigation_drift")
  let has_raven = raven_res != ""
  has_raven |> should.equal(True)

  let ruliad_res = fpp_ruliad_search_rule_space("cmdDisp")
  let has_ruliad = ruliad_res != ""
  has_ruliad |> should.equal(True)
}

pub fn auto_allocate_miq_nominal_pipeline_test() {
  let valid_intent =
    FlightIntent(
      intent_id: "INT-004",
      actor: "SwarmCoordinator",
      verb: DispatchFlightCommand(opcode: 0x300, args: ["coord"]),
      target_instance: "swarmMesh",
      target_device_serial: "SAFE_STORAGE_01",
      precondition_guard: True,
      formal_proof_ref: "formal/lean/Traceability.lean",
    )

  let services = [
    StpaService,
    FastOodaService,
    RavenService,
    RuliadService,
    SopContainmentService,
  ]

  case auto_allocate_miq(valid_intent, services) {
    Ok(logs) -> {
      let count_ok = list.length(logs) >= 5
      count_ok |> should.equal(True)
    }
    Error(_) -> should.fail()
  }
}

pub fn auto_allocate_miq_blocked_locked_nvme_test() {
  let locked_intent =
    FlightIntent(
      intent_id: "INT-005-BLOCKED",
      actor: "MaliciousAgent",
      verb: DispatchFlightCommand(opcode: 0x999, args: ["wipe"]),
      target_instance: "rootDisk",
      target_device_serial: "25503L801736",
      precondition_guard: True,
      formal_proof_ref: "none",
    )

  case auto_allocate_miq(locked_intent, [StpaService, FastOodaService]) {
    Ok(_) -> should.fail()
    Error(err) -> {
      should.equal(
        err,
        "MIQ_STPA_FAILED: STPA_VIOLATION: CRITICAL: System OS NVMe 25503L801736 is hardware-locked against all mutations (DAL-A Safety Contract)",
      )
    }
  }
}
