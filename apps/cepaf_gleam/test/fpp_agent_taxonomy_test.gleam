//// =============================================================================
//// [UOS-FPP-AGENT-TEST] NASA JPL F Prime Aerospace Agent Taxonomy Test Suite
//// =============================================================================
//// Comprehensive formal tests for the 16 FPP Aerospace Agent Types:
//// 1. All 16 canonical agent types exist and span fractal layers L0-L9
//// 2. DMC Base-ID window disjointness proof across all 16 agent types
//// 3. Full HSM initialization and active path verification
//// 4. Hierarchical signal dispatch with LCA transition sequencing
//// 5. Telemetry sampling and TCM 13D vector conservation
//// 6. DAL-A hardware safety interlock rejection on OS NVMe 25503L801736
//// 7. Typed JSON catalog and instance encoding
//// =============================================================================

import cepaf_gleam/fpp/agent_factory.{
  AgentNominal, dispatch_signal, emit_telemetry, encode_agent_instance_json,
  execute_agent_intent, heartbeat, instantiate_agent,
}
import cepaf_gleam/fpp/agent_taxonomy.{
  AvionicsTelemetry, CognitiveOodaIntent, ConstitutionalGuardian,
  DeterministicFlightController, LivingMetaEvolution, MissionPhaseHsm,
  StorageCustodian, all_agent_types, encode_agent_catalog_json,
  find_agent_type_spec, verify_agent_base_id_disjointness,
}
import cepaf_gleam/fpp/dmc_tcm.{
  hard_denied_system_os_serial, verify_tcm_13d_conservation,
}
import cepaf_gleam/fpp/intent.{
  DispatchFlightCommand, IntentAuthorized, IntentRejected,
}
import gleam/list
import gleam/string
import gleeunit/should

pub fn all_16_agent_types_exist_test() {
  let specs = all_agent_types()
  list.length(specs)
  |> should.equal(16)

  // Verify key types are present
  find_agent_type_spec(ConstitutionalGuardian)
  |> should.be_ok

  find_agent_type_spec(DeterministicFlightController)
  |> should.be_ok

  find_agent_type_spec(MissionPhaseHsm)
  |> should.be_ok

  find_agent_type_spec(CognitiveOodaIntent)
  |> should.be_ok

  find_agent_type_spec(LivingMetaEvolution)
  |> should.be_ok

  find_agent_type_spec(StorageCustodian)
  |> should.be_ok
}

pub fn base_id_window_disjointness_dmc_test() {
  let specs = all_agent_types()
  // Prove that all 16 agent base-ID intervals [B_i, B_i + 64) are pairwise disjoint
  verify_agent_base_id_disjointness(specs)
  |> should.equal(True)
}

pub fn agent_instantiation_and_hsm_init_test() {
  // 1. Constitutional Guardian
  let assert Ok(guardian) =
    instantiate_agent(ConstitutionalGuardian, "guardian-01")
  guardian.id |> should.equal("guardian-01")
  guardian.status |> should.equal(AgentNominal)
  guardian.hsm_state.active_path
  |> should.equal(["Operational", "Standby"])

  // 2. Flight Controller
  let assert Ok(flight_ctrl) =
    instantiate_agent(DeterministicFlightController, "flight-ctrl-01")
  flight_ctrl.hsm_state.active_path
  |> should.equal(["FlightState", "Disarmed"])

  // 3. Mission Phase HSM
  let assert Ok(mission) = instantiate_agent(MissionPhaseHsm, "mission-01")
  mission.hsm_state.active_path
  |> should.equal(["MissionLifecycle", "PreLaunch"])

  // 4. Cognitive OODA Agent
  let assert Ok(ooda) = instantiate_agent(CognitiveOodaIntent, "ooda-01")
  ooda.hsm_state.active_path
  |> should.equal(["Observe"])
}

pub fn agent_hsm_signal_dispatch_and_lca_transition_test() {
  let assert Ok(flight_ctrl) =
    instantiate_agent(DeterministicFlightController, "flight-ctrl-01")

  // Disarmed -> Armed
  let assert Ok(armed_ctrl) = dispatch_signal(flight_ctrl, "arm_controller")
  armed_ctrl.hsm_state.active_path
  |> should.equal(["FlightState", "Armed"])

  // Armed -> TrajectoryActive
  let assert Ok(active_ctrl) =
    dispatch_signal(armed_ctrl, "engage_trajectory")
  active_ctrl.hsm_state.active_path
  |> should.equal(["FlightState", "TrajectoryActive"])

  // TrajectoryActive -> EmergencyHalt (Cross-hierarchy transition)
  let assert Ok(halted_ctrl) = dispatch_signal(active_ctrl, "emergency_stop")
  halted_ctrl.hsm_state.active_path
  |> should.equal(["EmergencyHalt"])

  // EmergencyHalt -> FlightState (Cascades to initial substate Disarmed)
  let assert Ok(resumed_ctrl) = dispatch_signal(halted_ctrl, "reboot")
  resumed_ctrl.hsm_state.active_path
  |> should.equal(["FlightState", "Disarmed"])
}

pub fn agent_telemetry_and_tcm_conservation_test() {
  let assert Ok(agent) = instantiate_agent(AvionicsTelemetry, "telem-01")

  let agent_t1 = emit_telemetry(agent, "battery_voltage", 28.4)
  let agent_t2 = emit_telemetry(agent_t1, "bus_current", 3.12)

  list.length(agent_t2.telemetry_samples)
  |> should.equal(2)

  // Verify TCM 13D coordinate conservation between steps
  let tcm_initial = agent.tcm_vector
  let agent_stepped = heartbeat(agent_t2)
  let tcm_stepped = agent_stepped.tcm_vector

  verify_tcm_13d_conservation(tcm_initial, tcm_stepped)
  |> should.equal(True)

  agent_stepped.heartbeat_count
  |> should.equal(1)
}

pub fn agent_hardware_safety_interlock_rejection_test() {
  let assert Ok(custodian) =
    instantiate_agent(StorageCustodian, "custodian-01")

  // 1. Authorized command on safe NVMe storage
  let safe_verdict =
    execute_agent_intent(
      custodian,
      DispatchFlightCommand(0x101, []),
      "SAFE_DATA_NVME_02",
    )
  case safe_verdict {
    IntentAuthorized(_, _, _, _) -> Nil
    _ -> should.fail()
  }

  // 2. Denied command targeting root OS NVMe 25503L801736
  let denied_verdict =
    execute_agent_intent(
      custodian,
      DispatchFlightCommand(0x101, []),
      hard_denied_system_os_serial,
    )
  case denied_verdict {
    IntentRejected(intent_id, status_code, reason) -> {
      status_code |> should.equal(403)
      string.contains(intent_id, "INT-custodian-01") |> should.equal(True)
      string.contains(reason, hard_denied_system_os_serial)
      |> should.equal(True)
    }
    _ -> should.fail()
  }
}

pub fn agent_catalog_json_serialization_test() {
  let specs = all_agent_types()
  let json_str = encode_agent_catalog_json(specs)

  string.contains(json_str, "ConstitutionalGuardian") |> should.equal(True)
  string.contains(json_str, "DeterministicFlightController")
  |> should.equal(True)
  string.contains(json_str, "SC-FPP-AGENT-TAXONOMY-001") |> should.equal(True)

  let assert Ok(agent) =
    instantiate_agent(CognitiveOodaIntent, "cognitive-01")
  let instance_json = encode_agent_instance_json(agent)
  string.contains(instance_json, "cognitive-01") |> should.equal(True)
  string.contains(instance_json, "SC-FPP-AGENT-FACTORY-001")
  |> should.equal(True)
}
