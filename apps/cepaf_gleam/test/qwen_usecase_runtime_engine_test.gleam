import cepaf_gleam/harness/agent_ecology.{
  EmptyPayload, MaxRetriesExceeded, PolyBenchPacketState,
  advance_polybench_packet, diagnose_polybench_sm75_failure_mode,
  eval_fractal_usecase_test_gate, evaluate_cross_plane_bridge_vectors_28_to_41,
  evaluate_cross_plane_bridge_vectors_28_to_42,
  expected_ontology_uc_id, expected_qwen_model_assignment_code,
  expected_qwen_usecase_profile_code, route_optimal_qwen_usecase,
  simulate_sm75_qwen_hardware_envelope,
  verify_evolutionary_wave2_convergence_gate,
  verify_fractal_holarchy_full_alignment_gate,
  verify_full_system_artifact_aspect_component_wiring_gate,
  verify_nvme_interlock_serial, verify_pi_qwen_15cycle_symbiosis_gate,
  verify_polybench_sm75_language_tier_gate,
  verify_polyglot_language_optimization_gate, verify_public_benchmark_gate,
  verify_qwen_holonic_execution_envelope,
  verify_system_concepts_and_ontology_gate,
  verify_unified_ontology_usecase_fibration,
}
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn qwen_8pillar_holonic_envelope_admits_all_10_layers_test() {
  // Exact bijection: fpp_actor_id = 4 * layer + 3 (Intelligence domain holon per layer L0..L9)
  should.be_true(verify_qwen_holonic_execution_envelope(0, 3, 1, True, True, True))
  should.be_true(verify_qwen_holonic_execution_envelope(1, 7, 1, True, True, True))
  should.be_true(verify_qwen_holonic_execution_envelope(2, 11, 1, True, True, True))
  should.be_true(verify_qwen_holonic_execution_envelope(3, 15, 1, True, True, True))
  should.be_true(verify_qwen_holonic_execution_envelope(4, 19, 1, True, True, True))
  should.be_true(verify_qwen_holonic_execution_envelope(5, 23, 1, True, True, True))
  should.be_true(verify_qwen_holonic_execution_envelope(6, 27, 1, True, True, True))
  should.be_true(verify_qwen_holonic_execution_envelope(7, 31, 1, True, True, True))
  should.be_true(verify_qwen_holonic_execution_envelope(8, 35, 1, True, True, True))
  should.be_true(verify_qwen_holonic_execution_envelope(9, 39, 1, True, True, True))
}

pub fn qwen_8pillar_holonic_envelope_vetoes_spoofing_and_outages_test() {
  // Cross-layer actor spoofing (actor 23 belongs to L5, not L6)
  should.be_false(verify_qwen_holonic_execution_envelope(6, 23, 1, True, True, True))
  // Out-of-range layer (10) or actor (40) or caste (5)
  should.be_false(verify_qwen_holonic_execution_envelope(10, 39, 1, True, True, True))
  should.be_false(verify_qwen_holonic_execution_envelope(6, 40, 1, True, True, True))
  should.be_false(verify_qwen_holonic_execution_envelope(6, 27, 5, True, True, True))
  // Degraded pillars fail closed
  should.be_false(verify_qwen_holonic_execution_envelope(6, 27, 1, False, True, True))
  should.be_false(verify_qwen_holonic_execution_envelope(6, 27, 1, True, False, True))
  should.be_false(verify_qwen_holonic_execution_envelope(6, 27, 1, True, True, False))
}

pub fn qwen_10_usecases_map_to_5_optimization_profiles_test() {
  // Profile 1: P0_Deterministic_Grammar (UC00, UC04, UC05)
  should.equal(route_optimal_qwen_usecase(0, 0, True, True, True, True), 1)
  should.equal(route_optimal_qwen_usecase(4, 4, True, True, True, True), 1)
  should.equal(route_optimal_qwen_usecase(5, 5, True, True, True, True), 1)

  // Profile 2: P1_ZeroTemp_CodeGen (UC01, UC02, UC03)
  should.equal(route_optimal_qwen_usecase(1, 1, True, True, True, True), 2)
  should.equal(route_optimal_qwen_usecase(2, 2, True, True, True, True), 2)
  should.equal(route_optimal_qwen_usecase(3, 3, True, True, True, True), 2)

  // Profile 3: P2_LongContext_16k_Compacted (UC06, UC08)
  should.equal(route_optimal_qwen_usecase(6, 6, True, True, True, True), 3)
  should.equal(route_optimal_qwen_usecase(8, 8, True, True, True, True), 3)

  // Profile 4: P3_Parallel_DualSlot_Batch (UC07)
  should.equal(route_optimal_qwen_usecase(7, 7, True, True, True, True), 4)

  // Profile 5: P4_LowLatency_SSE_Stream (UC09)
  should.equal(route_optimal_qwen_usecase(9, 9, True, True, True, True), 5)
}

pub fn qwen_10_usecases_map_to_real_uos_model_assignments_test() {
  // 1 = Qwen+AGY (UC00: Pi Compaction, UC04: Fractal RCA/Sa-plan, UC08: KM Triad & SC-JOURNAL-v3)
  should.equal(expected_qwen_model_assignment_code(0), 1)
  should.equal(expected_qwen_model_assignment_code(4), 1)
  should.equal(expected_qwen_model_assignment_code(8), 1)

  // 2 = Qwen+Claude (UC01: sm_75 CUDA/PTX Shim & Mojo Tensor Core Kernel)
  should.equal(expected_qwen_model_assignment_code(1), 2)

  // 3 = Qwen+Codex (UC02: Lean 4 Digital Twin & C-ABI, UC05: uos-harness 104-Route MCP & Zenoh)
  should.equal(expected_qwen_model_assignment_code(2), 3)
  should.equal(expected_qwen_model_assignment_code(5), 3)

  // 4 = Qwen+TriAgent (UC03: Differential Mojo Oracles, UC06: Gleam/OTP & 392-State Provider API, UC07: 17-Aspect Dual-Slot Swarm)
  should.equal(expected_qwen_model_assignment_code(3), 4)
  should.equal(expected_qwen_model_assignment_code(6), 4)
  should.equal(expected_qwen_model_assignment_code(7), 4)

  // 5 = QwenAutonomous (UC09: 100% Autonomous pi-local+qwen CLI & Real-Time SSE Cockpit)
  should.equal(expected_qwen_model_assignment_code(9), 5)
  should.equal(expected_qwen_model_assignment_code(10), 0)
}

pub fn qwen_usecase_router_fails_closed_on_violation_test() {
  // Layer mismatch (UC06 on L5)
  should.equal(route_optimal_qwen_usecase(6, 5, True, True, True, True), 0)
  // Out-of-bounds usecase (UC10)
  should.equal(route_optimal_qwen_usecase(10, 10, True, True, True, True), 0)
  should.equal(expected_qwen_usecase_profile_code(10), 0)
  // Uncompacted >16k overflow
  should.equal(route_optimal_qwen_usecase(6, 6, False, True, True, True), 0)
  // Backend outage
  should.equal(route_optimal_qwen_usecase(6, 6, True, False, True, True), 0)
  // Holonic envelope failure
  should.equal(route_optimal_qwen_usecase(6, 6, True, True, False, True), 0)
  // KV prefix cache unavailable
  should.equal(route_optimal_qwen_usecase(6, 6, True, True, True, False), 0)
}

pub fn nvme_storage_interlock_vetoes_os_serial_test() {
  should.be_false(verify_nvme_interlock_serial("25503L801736"))
  should.be_false(verify_nvme_interlock_serial(""))
  should.be_true(verify_nvme_interlock_serial("WSL2_SOVEREIGN_VHDX"))
}

pub fn unified_ontology_usecase_fibration_bijection_and_guard_test() {
  // Exact 10-to-10 bijection UC00..UC09 <-> UC-1..UC-10
  should.equal(expected_ontology_uc_id(0), 3)
  should.equal(expected_ontology_uc_id(1), 5)
  should.equal(expected_ontology_uc_id(2), 9)
  should.equal(expected_ontology_uc_id(3), 2)
  should.equal(expected_ontology_uc_id(4), 1)
  should.equal(expected_ontology_uc_id(5), 7)
  should.equal(expected_ontology_uc_id(6), 6)
  should.equal(expected_ontology_uc_id(7), 8)
  should.equal(expected_ontology_uc_id(8), 4)
  should.equal(expected_ontology_uc_id(9), 10)
  should.equal(expected_ontology_uc_id(10), 0)

  // Valid cross-ontology coordinates (Export #30)
  should.be_true(verify_unified_ontology_usecase_fibration(0, 3, 0, 3, 2, 1))
  should.be_true(verify_unified_ontology_usecase_fibration(2, 9, 2, 11, 2, 2))
  should.be_true(verify_unified_ontology_usecase_fibration(4, 1, 4, 19, 1, 0))
  should.be_true(verify_unified_ontology_usecase_fibration(6, 6, 6, 27, 2, 2))
  should.be_true(verify_unified_ontology_usecase_fibration(8, 4, 8, 35, 2, 1))
  should.be_true(verify_unified_ontology_usecase_fibration(9, 10, 9, 39, 2, 1))

  // Fail-closed vetoes on ontology UC mismatch, layer drift, actor drift, or paid cascade tier leak
  should.be_false(verify_unified_ontology_usecase_fibration(0, 1, 0, 3, 2, 1))
  should.be_false(verify_unified_ontology_usecase_fibration(6, 6, 5, 27, 2, 2))
  should.be_false(verify_unified_ontology_usecase_fibration(6, 6, 6, 23, 2, 2))
  should.be_false(verify_unified_ontology_usecase_fibration(6, 6, 6, 27, 4, 2))
  should.be_false(verify_unified_ontology_usecase_fibration(6, 6, 6, 27, 2, 5))
}

pub fn fractal_usecase_test_gate_perf_ftc_context_test() {
  // Admits all 10 fractal layers when Performance, 1st-Time Correctness, Context Opt, Ontology & Holonic hold
  should.equal(eval_fractal_usecase_test_gate(0, 0, True, True, True, True, True), 1)
  should.equal(eval_fractal_usecase_test_gate(2, 2, True, True, True, True, True), 2)
  should.equal(eval_fractal_usecase_test_gate(6, 6, True, True, True, True, True), 3)
  should.equal(eval_fractal_usecase_test_gate(7, 7, True, True, True, True, True), 4)
  should.equal(eval_fractal_usecase_test_gate(9, 9, True, True, True, True, True), 5)

  // Vetoes any single-axis degradation (Performance, 1st-Time Correctness, Context Opt, Ontology, Holonic)
  should.equal(eval_fractal_usecase_test_gate(6, 5, True, True, True, True, True), 0)
  should.equal(eval_fractal_usecase_test_gate(6, 6, False, True, True, True, True), 0)
  should.equal(eval_fractal_usecase_test_gate(6, 6, True, False, True, True, True), 0)
  should.equal(eval_fractal_usecase_test_gate(6, 6, True, True, False, True, True), 0)
  should.equal(eval_fractal_usecase_test_gate(6, 6, True, True, True, False, True), 0)
  should.equal(eval_fractal_usecase_test_gate(6, 6, True, True, True, True, False), 0)
}

pub fn sm75_qwen_hardware_simulator_and_public_benchmark_gate_test() {
  // Admitted SM75 configs 0..7
  should.equal(simulate_sm75_qwen_hardware_envelope(0, 2424, 84, 28, 2, 1), 1)
  should.equal(simulate_sm75_qwen_hardware_envelope(6, 7493, 79, 68, 2, 0), 1)
  // Rejected OOM / BF16 emulation / threshold violations
  should.equal(simulate_sm75_qwen_hardware_envelope(8, 8333, 79, 68, 2, 0), 0)
  should.equal(simulate_sm75_qwen_hardware_envelope(6, 8333, 79, 68, 2, 0), 0)
  should.equal(simulate_sm75_qwen_hardware_envelope(6, 7493, 65, 68, 2, 0), 0)
  should.equal(simulate_sm75_qwen_hardware_envelope(6, 7493, 79, 180, 2, 0), 0)
  should.equal(simulate_sm75_qwen_hardware_envelope(6, 7493, 79, 68, 8, 0), 0)
  should.equal(simulate_sm75_qwen_hardware_envelope(6, 7493, 79, 68, 2, 3), 0)
  // Public Benchmarks BM-00..BM-07
  should.equal(verify_public_benchmark_gate(0, 100, 640, True, True), 1)
  should.equal(verify_public_benchmark_gate(3, 100, 2, True, True), 1)
  should.equal(verify_public_benchmark_gate(4, 92, 68, True, True), 1)
  should.equal(verify_public_benchmark_gate(5, 79, 20, True, True), 1)
  should.equal(verify_public_benchmark_gate(3, 100, 8, True, True), 0)
  should.equal(verify_public_benchmark_gate(4, 60, 68, True, True), 0)
  should.equal(verify_public_benchmark_gate(5, 79, 20, False, True), 0)
  should.equal(verify_public_benchmark_gate(5, 79, 20, True, False), 0)
}

pub fn system_concepts_ontology_and_polyglot_language_gates_test() {
  // System concepts & 3-layer ontology (Export #36)
  should.equal(verify_system_concepts_and_ontology_gate(0, 399, 100, True, True), 1)
  should.equal(verify_system_concepts_and_ontology_gate(1, 13, 100, True, True), 1)
  should.equal(verify_system_concepts_and_ontology_gate(2, 52, 100, True, True), 1)
  should.equal(verify_system_concepts_and_ontology_gate(6, 3, 100, True, True), 1)
  should.equal(verify_system_concepts_and_ontology_gate(9, 93, 100, True, True), 1)
  // Vetoes EV>93, cardinality mismatch, or missing type separation
  should.equal(verify_system_concepts_and_ontology_gate(9, 94, 100, True, True), 0)
  should.equal(verify_system_concepts_and_ontology_gate(0, 398, 100, True, True), 0)
  should.equal(verify_system_concepts_and_ontology_gate(2, 52, 100, False, True), 0)

  // 12 Polyglot Languages (Export #37: Lean 4, Mojo, MAX/SM75, OCaml, Gleam, Stan, Zig, Rust, Quint, FPP, SQLite/Rete/Ruliad, Nix)
  should.equal(verify_polyglot_language_optimization_gate(0, 116, 100, 1420, True, True), 1)
  should.equal(verify_polyglot_language_optimization_gate(3, 203, 100, 12, True, True), 1)
  should.equal(verify_polyglot_language_optimization_gate(5, 125, 100, 18, True, True), 1)
  should.equal(verify_polyglot_language_optimization_gate(6, 108, 100, 3, True, True), 1)
  // Vetoes Stan artifact drop, latency breach, or Zero-Muda violation
  should.equal(verify_polyglot_language_optimization_gate(5, 110, 100, 18, True, True), 0)
  should.equal(verify_polyglot_language_optimization_gate(3, 203, 100, 75, True, True), 0)
  should.equal(verify_polyglot_language_optimization_gate(4, 1042, 100, 36, False, True), 0)
}

pub fn polybench_sm75_gleam_router_repair_and_diagnosis_matrix_test() {
  // PolyBench-SM75 Language 3 (Gleam) Tier 3 Seed: advance_polybench_packet
  let p0 = PolyBenchPacketState(seq: 10, retries: 0, payload: "uos-frame")
  should.equal(
    advance_polybench_packet(p0),
    Ok(PolyBenchPacketState(seq: 11, retries: 1, payload: "uos-frame")),
  )
  let p_empty = PolyBenchPacketState(seq: 10, retries: 0, payload: "")
  should.equal(advance_polybench_packet(p_empty), Error(EmptyPayload))
  let p_max = PolyBenchPacketState(seq: 10, retries: 3, payload: "uos-frame")
  should.equal(advance_polybench_packet(p_max), Error(MaxRetriesExceeded))

  // PolyBench-SM75 6-Language × 4-Tier Gate (Export #38)
  should.equal(verify_polybench_sm75_language_tier_gate(0, 3, 100, 62, 81, 2, True), 1)
  should.equal(verify_polybench_sm75_language_tier_gate(5, 4, 100, 55, 82, 2, True), 1)
  should.equal(verify_polybench_sm75_language_tier_gate(0, 3, 90, 62, 81, 2, True), 0)
  should.equal(verify_polybench_sm75_language_tier_gate(0, 3, 100, 135, 81, 2, True), 0)
  should.equal(verify_polybench_sm75_language_tier_gate(0, 3, 100, 62, 68, 2, True), 0)

  // PolyBench-SM75 3-Rule Diagnosis Matrix
  should.equal(diagnose_polybench_sm75_failure_mode(92, 55, 88, 98), 1)
  should.equal(diagnose_polybench_sm75_failure_mode(92, 88, 60, 98), 2)
  should.equal(diagnose_polybench_sm75_failure_mode(92, 88, 90, 85), 3)
  should.equal(diagnose_polybench_sm75_failure_mode(95, 92, 96, 100), 0)
}

pub fn fractal_holarchy_full_alignment_10_layers_test() {
  // Complete Fractal (L0..L9) & Holarchy (40 FPP Actors, 5 Castes, 170 Janus Holons, 52 Dir, 104 MCP, 13D) Gate (Export #39)
  should.equal(verify_fractal_holarchy_full_alignment_gate(0, 3, 0, 0, 16, 25, 104, 13), 1)
  should.equal(verify_fractal_holarchy_full_alignment_gate(5, 23, 2, 85, 101, 30, 104, 13), 1)
  should.equal(verify_fractal_holarchy_full_alignment_gate(9, 39, 4, 153, 169, 34, 104, 13), 1)
  // Vetoes actor mismatch, caste mismatch, holon slice mismatch, or MCP route count mismatch
  should.equal(verify_fractal_holarchy_full_alignment_gate(0, 2, 0, 0, 16, 25, 104, 13), 0)
  should.equal(verify_fractal_holarchy_full_alignment_gate(5, 23, 3, 85, 101, 30, 104, 13), 0)
  should.equal(verify_fractal_holarchy_full_alignment_gate(6, 27, 3, 102, 117, 31, 104, 13), 0)
  should.equal(verify_fractal_holarchy_full_alignment_gate(9, 39, 4, 153, 169, 34, 101, 13), 0)
}

pub fn evolutionary_wave2_cycles_21_to_25_convergence_test() {
  // Evolutionary Wave 2 Convergence Gate (Cycles 21..25, Export #40)
  should.equal(verify_evolutionary_wave2_convergence_gate(0, 21, 2, 11, 40, 34, 9, True), 1)
  should.equal(verify_evolutionary_wave2_convergence_gate(1, 22, 3, 11, 40, 34, 9, True), 1)
  should.equal(verify_evolutionary_wave2_convergence_gate(2, 23, 4, 11, 40, 34, 9, True), 1)
  should.equal(verify_evolutionary_wave2_convergence_gate(3, 24, 6, 11, 40, 34, 9, True), 1)
  should.equal(verify_evolutionary_wave2_convergence_gate(4, 25, 8, 11, 40, 34, 9, True), 1)
  // Vetoes cycle mismatch, layer mismatch, NIF count mismatch, C-ABI count mismatch, or failed live probe
  should.equal(verify_evolutionary_wave2_convergence_gate(0, 22, 2, 11, 40, 34, 9, True), 0)
  should.equal(verify_evolutionary_wave2_convergence_gate(1, 22, 2, 11, 40, 34, 9, True), 0)
  should.equal(verify_evolutionary_wave2_convergence_gate(2, 23, 4, 10, 40, 34, 9, True), 0)
  should.equal(verify_evolutionary_wave2_convergence_gate(3, 24, 6, 11, 39, 34, 9, True), 0)
  should.equal(verify_evolutionary_wave2_convergence_gate(4, 25, 8, 11, 40, 34, 9, False), 0)
}

pub fn full_system_artifact_aspect_component_wiring_test() {
  // Full-System Artifact, Component & 17-Aspect Wiring Gate (L0..L9, Export #41)
  should.equal(
    verify_full_system_artifact_aspect_component_wiring_gate(0, 0, 0, 17, 52, 12, 104, 24),
    1,
  )
  should.equal(
    verify_full_system_artifact_aspect_component_wiring_gate(6, 24, 3, 17, 52, 12, 104, 24),
    1,
  )
  should.equal(
    verify_full_system_artifact_aspect_component_wiring_gate(9, 36, 4, 17, 52, 12, 104, 24),
    1,
  )
  // Vetoes actor base mismatch, caste mismatch, aspect count mismatch, directory mismatch, or bridge count mismatch
  should.equal(
    verify_full_system_artifact_aspect_component_wiring_gate(6, 25, 3, 17, 52, 12, 104, 24),
    0,
  )
  should.equal(
    verify_full_system_artifact_aspect_component_wiring_gate(6, 24, 2, 17, 52, 12, 104, 24),
    0,
  )
  should.equal(
    verify_full_system_artifact_aspect_component_wiring_gate(6, 24, 3, 16, 52, 12, 104, 24),
    0,
  )
  should.equal(
    verify_full_system_artifact_aspect_component_wiring_gate(6, 24, 3, 17, 51, 12, 104, 24),
    0,
  )
  should.equal(
    verify_full_system_artifact_aspect_component_wiring_gate(6, 24, 3, 17, 52, 12, 104, 22),
    0,
  )
}

pub fn cross_plane_24_vector_bridge_parity_test() {
  should.equal(
    evaluate_cross_plane_bridge_vectors_28_to_41(),
    [1, 0, 3, 0, 1, 0, 3, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0],
  )
}

pub fn pi_qwen_15cycle_symbiosis_and_traffic_tuning_test() {
  // Wave-4 15 Evolutionary Cycles (Cycles 26..40, Export #42) + Rules(81)/Skills(29)/Superpowers(15)/SOPs(21)=146
  should.equal(verify_pi_qwen_15cycle_symbiosis_gate(0, 26, 25, 0, 146, 60, 111, 1), 1)
  should.equal(verify_pi_qwen_15cycle_symbiosis_gate(5, 31, 30, 5, 146, 60, 111, 6), 1)
  should.equal(verify_pi_qwen_15cycle_symbiosis_gate(10, 36, 35, 0, 146, 60, 111, 5), 1)
  should.equal(verify_pi_qwen_15cycle_symbiosis_gate(14, 40, 39, 4, 146, 60, 111, 3), 1)
  // Vetoes cycle mismatch, actor mismatch, procedural quad drift, route drift, or traffic class mismatch
  should.equal(verify_pi_qwen_15cycle_symbiosis_gate(0, 27, 25, 0, 146, 60, 111, 1), 0)
  should.equal(verify_pi_qwen_15cycle_symbiosis_gate(0, 26, 25, 0, 145, 60, 111, 1), 0)
  should.equal(verify_pi_qwen_15cycle_symbiosis_gate(0, 26, 25, 0, 146, 53, 111, 1), 0)
  should.equal(verify_pi_qwen_15cycle_symbiosis_gate(15, 41, 40, 5, 146, 60, 111, 4), 0)
  should.equal(
    evaluate_cross_plane_bridge_vectors_28_to_42(),
    [1, 0, 3, 0, 1, 0, 3, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0],
  )
}
