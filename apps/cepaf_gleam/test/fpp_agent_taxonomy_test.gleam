//// =============================================================================
//// [UOS-C3I-AGENT-TEST] C3I SDLC, SRE & Verification Aerospace Agent Test Suite
//// =============================================================================
//// Comprehensive formal tests for the 72 C3I Sovereign Aerospace Agent Types:
//// 1. All 72 canonical agent types exist across SDLC (16), SRE (16), and Verification (16)
//// 2. DMC Base-ID window disjointness proof across all 72 agent types [0x1000..0x1C00)
//// 3. Full HSM initialization and active path verification
//// 4. Hierarchical signal dispatch with LCA transition sequencing
//// 5. Telemetry sampling and TCM 13D vector conservation
//// 6. DAL-A hardware safety interlock rejection on OS NVMe 25503L801736
//// 7. Typed JSON catalog and instance encoding with C3I pillar breakdowns
//// =============================================================================

import cepaf_gleam/fpp/agent_factory.{
  AgentNominal, dispatch_signal, emit_telemetry, encode_agent_instance_json,
  execute_agent_intent, heartbeat, instantiate_agent,
}
import cepaf_gleam/fpp/agent_taxonomy.{
  AvionicsTelemetry, CognitiveOodaIntent, ConstitutionalGuardian, CrashWalReplay,
  DeterministicFlightController, DeterministicReductionScheduler,
  HardwareDriveInterlock, LocklessHamtStorage, MissionPhaseHsm,
  SdlcArchitectureSynthesizer, SdlcContractCodeGenerator,
  SdlcGraphWorkflowOrchestrator, SdlcPromptTemplateInjector,
  SreChaosFaultInjector, SreLyapunovTrendDetector,
  SreRunnerLifecycleHookSupervisor, SreSentinel, SreTimeTravelStateRollback,
  SubstrateReactor, VerificationAdkEvalBenchmark, VerificationChecklistAuditor,
  VerificationMasterChecklistGatekeeper, VerificationZeroMudaPurityEnforcer,
  all_agent_types, encode_agent_catalog_json, find_agent_type_spec, sdlc_agents,
  sre_agents, verification_agents, verify_agent_base_id_disjointness,
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

pub fn all_96_agent_types_exist_test() {
  let specs = all_agent_types()
  list.length(specs)
  |> should.equal(96)

  // Verify 32 SDLC Agents
  list.length(sdlc_agents())
  |> should.equal(32)

  // Verify 32 SRE Agents
  list.length(sre_agents())
  |> should.equal(32)

  // Verify 32 Verification Agents
  list.length(verification_agents())
  |> should.equal(32)

  // Check sample representatives from each pillar
  find_agent_type_spec(ConstitutionalGuardian)
  |> should.be_ok

  find_agent_type_spec(DeterministicFlightController)
  |> should.be_ok

  find_agent_type_spec(SreSentinel)
  |> should.be_ok

  find_agent_type_spec(MissionPhaseHsm)
  |> should.be_ok

  find_agent_type_spec(HardwareDriveInterlock)
  |> should.be_ok

  find_agent_type_spec(DeterministicReductionScheduler)
  |> should.be_ok

  find_agent_type_spec(SdlcArchitectureSynthesizer)
  |> should.be_ok

  find_agent_type_spec(SdlcContractCodeGenerator)
  |> should.be_ok

  find_agent_type_spec(SreLyapunovTrendDetector)
  |> should.be_ok

  find_agent_type_spec(SreChaosFaultInjector)
  |> should.be_ok

  find_agent_type_spec(VerificationChecklistAuditor)
  |> should.be_ok

  find_agent_type_spec(SdlcGraphWorkflowOrchestrator)
  |> should.be_ok

  find_agent_type_spec(SreRunnerLifecycleHookSupervisor)
  |> should.be_ok

  find_agent_type_spec(VerificationAdkEvalBenchmark)
  |> should.be_ok

  find_agent_type_spec(SdlcPromptTemplateInjector)
  |> should.be_ok

  find_agent_type_spec(SreTimeTravelStateRollback)
  |> should.be_ok

  find_agent_type_spec(VerificationMasterChecklistGatekeeper)
  |> should.be_ok

  find_agent_type_spec(VerificationZeroMudaPurityEnforcer)
  |> should.be_ok
}

pub fn base_id_window_disjointness_dmc_test() {
  let specs = all_agent_types()
  // Prove that all 96 agent base-ID intervals [B_i, B_i + 64) are pairwise disjoint
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

  // 5. Hardware Drive Interlock
  let assert Ok(interlock) =
    instantiate_agent(HardwareDriveInterlock, "nvme-lock-01")
  interlock.hsm_state.active_path
  |> should.equal(["Guarding"])

  // 6. Reduction Scheduler
  let assert Ok(sched) =
    instantiate_agent(DeterministicReductionScheduler, "sched-01")
  sched.hsm_state.active_path
  |> should.equal(["Executing"])

  // 7. Substrate Reactor
  let assert Ok(reactor) = instantiate_agent(SubstrateReactor, "reactor-01")
  reactor.hsm_state.active_path
  |> should.equal(["Polling"])

  // 8. Lockless HAMT Storage
  let assert Ok(hamt) = instantiate_agent(LocklessHamtStorage, "hamt-01")
  hamt.hsm_state.active_path
  |> should.equal(["Serving"])

  // 9. Crash WAL Replay
  let assert Ok(wal) = instantiate_agent(CrashWalReplay, "wal-01")
  wal.hsm_state.active_path
  |> should.equal(["Appending"])

  // 10. SDLC Architecture Synthesizer
  let assert Ok(arch) =
    instantiate_agent(SdlcArchitectureSynthesizer, "arch-01")
  arch.hsm_state.active_path
  |> should.equal(["Modeling"])

  // 11. SRE Lyapunov Trend Detector
  let assert Ok(lyap) = instantiate_agent(SreLyapunovTrendDetector, "lyap-01")
  lyap.hsm_state.active_path
  |> should.equal(["WindowSampling"])

  // 12. Verification Checklist Auditor
  let assert Ok(chk) = instantiate_agent(VerificationChecklistAuditor, "chk-01")
  chk.hsm_state.active_path
  |> should.equal(["ScanningChecklist"])
}

pub fn agent_hsm_signal_dispatch_and_lca_transition_test() {
  let assert Ok(flight_ctrl) =
    instantiate_agent(DeterministicFlightController, "flight-ctrl-01")

  // Disarmed -> Armed
  let assert Ok(armed_ctrl) = dispatch_signal(flight_ctrl, "arm_controller")
  armed_ctrl.hsm_state.active_path
  |> should.equal(["FlightState", "Armed"])

  // Armed -> TrajectoryActive
  let assert Ok(inflight_ctrl) =
    dispatch_signal(armed_ctrl, "engage_trajectory")
  inflight_ctrl.hsm_state.active_path
  |> should.equal(["FlightState", "TrajectoryActive"])

  // TrajectoryActive -> EmergencyHalt
  let assert Ok(safe_ctrl) = dispatch_signal(inflight_ctrl, "emergency_stop")
  safe_ctrl.hsm_state.active_path
  |> should.equal(["EmergencyHalt"])

  // Reduction Scheduler: Executing -> Yielded
  let assert Ok(sched) =
    instantiate_agent(DeterministicReductionScheduler, "sched-01")
  let assert Ok(yielded_sched) = dispatch_signal(sched, "reduction_exhausted")
  yielded_sched.hsm_state.active_path
  |> should.equal(["Yielded"])

  // Yielded -> Executing
  let assert Ok(resumed_sched) =
    dispatch_signal(yielded_sched, "timeslice_granted")
  resumed_sched.hsm_state.active_path
  |> should.equal(["Executing"])

  // Crash WAL: Appending -> Replaying
  let assert Ok(wal) = instantiate_agent(CrashWalReplay, "wal-01")
  let assert Ok(replaying_wal) =
    dispatch_signal(wal, "reboot_recovery_requested")
  replaying_wal.hsm_state.active_path
  |> should.equal(["Replaying"])

  // Replaying -> Appending
  let assert Ok(appended_wal) = dispatch_signal(replaying_wal, "replay_done")
  appended_wal.hsm_state.active_path
  |> should.equal(["Appending"])

  // SDLC Arch: Modeling -> Decomposing -> Synthesized
  let assert Ok(arch) =
    instantiate_agent(SdlcArchitectureSynthesizer, "arch-01")
  let assert Ok(decomp) = dispatch_signal(arch, "start_decomposition")
  decomp.hsm_state.active_path
  |> should.equal(["Decomposing"])
  let assert Ok(synth) = dispatch_signal(decomp, "verify_invariants")
  synth.hsm_state.active_path
  |> should.equal(["Synthesized"])

  // SRE Lyapunov: WindowSampling -> EvaluatingLambda -> TrendStable
  let assert Ok(lyap) = instantiate_agent(SreLyapunovTrendDetector, "lyap-01")
  let assert Ok(eval_lyap) = dispatch_signal(lyap, "sample_tick")
  eval_lyap.hsm_state.active_path
  |> should.equal(["EvaluatingLambda"])
  let assert Ok(stable_lyap) = dispatch_signal(eval_lyap, "lambda_computed")
  stable_lyap.hsm_state.active_path
  |> should.equal(["TrendStable"])

  // Verification Checklist: ScanningChecklist -> DomainEvaluated -> Checklist18Green
  let assert Ok(chk) = instantiate_agent(VerificationChecklistAuditor, "chk-01")
  let assert Ok(eval_chk) = dispatch_signal(chk, "audit_check")
  eval_chk.hsm_state.active_path
  |> should.equal(["DomainEvaluated"])
  let assert Ok(green_chk) = dispatch_signal(eval_chk, "all_domains_pass")
  green_chk.hsm_state.active_path
  |> should.equal(["Checklist18Green"])
}

pub fn agent_telemetry_and_heartbeat_lifecycle_test() {
  let assert Ok(agent) =
    instantiate_agent(AvionicsTelemetry, "telemetry-engine-01")

  // Heartbeat increments
  let a1 = heartbeat(agent)
  let a2 = heartbeat(a1)
  a2.heartbeat_count |> should.equal(2)

  // Emit telemetry samples
  let a3 = emit_telemetry(a2, "bus_voltage_v", 28.4)
  let a4 = emit_telemetry(a3, "bus_current_a", 1.85)

  list.length(a4.telemetry_samples)
  |> should.equal(2)

  // Verify TCM 13D vector conservation
  verify_tcm_13d_conservation(agent.tcm_vector, a4.tcm_vector)
  |> should.equal(True)
}

pub fn dal_a_hardware_drive_interlock_rejection_test() {
  let assert Ok(guardian) =
    instantiate_agent(ConstitutionalGuardian, "guardian-01")

  // Intent targeting root OS drive 25503L801736 must fail closed
  let denied_serial = hard_denied_system_os_serial
  let illegal_intent_result =
    execute_agent_intent(
      guardian,
      DispatchFlightCommand(0x10, ["format_partition"]),
      denied_serial,
    )

  case illegal_intent_result {
    IntentRejected(intent_id: _, status_code: _, reason: reason) -> {
      string.contains(reason, denied_serial)
      |> should.equal(True)
      string.contains(reason, "hardware-locked")
      |> should.equal(True)
    }
    IntentAuthorized(..) ->
      panic as "FATAL: Root OS NVMe 25503L801736 was NOT rejected by intent gatekeeper!"
  }

  // Intent targeting safe secondary payload drive must succeed
  let safe_intent_result =
    execute_agent_intent(
      guardian,
      DispatchFlightCommand(0x20, ["sample_telemetry"]),
      "PAYLOAD-DRIVE-NVME-002",
    )

  case safe_intent_result {
    IntentAuthorized(action_summary: summary, ..) -> {
      string.contains(summary, "DispatchFlightCommand")
      |> should.equal(True)
    }
    IntentRejected(..) ->
      panic as "Allowed payload drive intent was unexpectedly rejected"
  }
}

pub fn agent_json_catalog_serialization_test() {
  let specs = all_agent_types()
  let catalog_json = encode_agent_catalog_json(specs)

  string.contains(catalog_json, "\"total_agent_types\":96")
  |> should.equal(True)

  string.contains(catalog_json, "\"sdlc_agents_count\":32")
  |> should.equal(True)

  string.contains(catalog_json, "\"sre_agents_count\":32")
  |> should.equal(True)

  string.contains(catalog_json, "\"verification_agents_count\":32")
  |> should.equal(True)

  string.contains(catalog_json, "\"SC-FPP-AGENT-TAXONOMY-001\"")
  |> should.equal(True)

  string.contains(
    catalog_json,
    "C3I Verification Constitutional Guardian Agent",
  )
  |> should.equal(True)

  string.contains(
    catalog_json,
    "C3I Verification Hardware Drive Safety Interlock Agent",
  )
  |> should.equal(True)

  string.contains(
    catalog_json,
    "C3I SRE Deterministic Reduction Scheduler Agent",
  )
  |> should.equal(True)

  string.contains(
    catalog_json,
    "C3I SDLC Dynamic Agent Bytecode Synthesizer Agent",
  )
  |> should.equal(True)

  string.contains(catalog_json, "C3I SDLC Architecture Synthesizer Agent")
  |> should.equal(True)

  string.contains(catalog_json, "C3I SRE Lyapunov Trend Detector Agent")
  |> should.equal(True)

  string.contains(catalog_json, "C3I Verification Checklist Auditor Agent")
  |> should.equal(True)

  // Verify single agent instance JSON serialization
  let assert Ok(agent) =
    instantiate_agent(ConstitutionalGuardian, "guardian-01")
  let instance_json = encode_agent_instance_json(agent)

  string.contains(instance_json, "\"guardian-01\"")
  |> should.equal(True)

  string.contains(instance_json, "\"NOMINAL\"")
  |> should.equal(True)
}
