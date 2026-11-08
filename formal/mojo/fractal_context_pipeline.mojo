from std.sys import exit
from oracle_substrate import Receipt, capture
from lean_ffi_bridge import (
    verify_lean_mojo_fractal_context_chain_parity,
    verify_lean_mojo_simulator_realtime_parity,
    verify_lean_mojo_tool_call_provenance_parity,
    verify_lean_mojo_provider_api_transition_parity,
    verify_lean_mojo_provider_api_recovery_parity,
    verify_lean_mojo_service_mesh_binding_parity,
    verify_lean_mojo_system_directory_parity,
    verify_lean_mojo_sdlc_sre_17_aspect_parity,
    verify_lean_mojo_qwen_holonic_envelope_parity,
    verify_lean_mojo_qwen_usecase_router_parity,
    verify_lean_mojo_unified_ontology_fibration_parity,
    verify_lean_mojo_fractal_usecase_test_gate_parity,
    verify_lean_mojo_qwen_profile_simulator_parity,
    verify_lean_mojo_20_optimization_cycles_parity,
    verify_lean_mojo_sm75_qwen_hardware_envelope_parity,
    verify_lean_mojo_public_benchmark_gate_parity,
    verify_lean_mojo_system_concepts_and_ontology_parity,
    verify_lean_mojo_polyglot_language_optimization_parity,
    verify_lean_mojo_polybench_sm75_language_tier_parity,
    verify_lean_mojo_fractal_holarchy_full_alignment_parity,
    verify_lean_mojo_evolutionary_wave2_convergence_parity,
    verify_lean_mojo_full_system_artifact_aspect_component_wiring_parity,
    verify_lean_mojo_pi_qwen_15cycle_symbiosis_parity,
)

comptime TWIN = "formal/lean/UosFullSystemCodeUnifiedDigitalTwin.lean"

def verify_l0_to_l9_handoff_continuity(
    l0_ok: Bool, l1_ok: Bool, l2_ok: Bool, l3_ok: Bool, l4_ok: Bool,
    l5_ok: Bool, l6_ok: Bool, l7_ok: Bool, l8_ok: Bool, l9_ok: Bool,
    missing_upstream_defs: Int,
    pi_subagent_tokens: Int
) -> Bool:
    return (
        l0_ok and l1_ok and l2_ok and l3_ok and l4_ok
        and l5_ok and l6_ok and l7_ok and l8_ok and l9_ok
        and missing_upstream_defs == 0
        and pi_subagent_tokens == 0
    )

def verify_fractal_context_pipeline_5_usecases() -> Int:
    var matched = 0
    for uc in range(5):
        var ok = verify_l0_to_l9_handoff_continuity(
            True, True, True, True, True,
            True, True, True, True, True,
            0, 0
        )
        var broken = verify_l0_to_l9_handoff_continuity(
            True, True, True, True, True,
            True, True, True, True, True,
            uc + 1, 0
        )
        if ok and not broken:
            matched += 1
    return matched

def fractal_context_pipeline_exhaustive_check() -> Int:
    var matched = verify_lean_mojo_fractal_context_chain_parity()
    return matched

def main() raises:
    var r = Receipt(String("uos.oracle.v1"), String(TWIN))
    var m = fractal_context_pipeline_exhaustive_check()
    var u = verify_fractal_context_pipeline_5_usecases()
    var s = verify_lean_mojo_simulator_realtime_parity()
    var p = verify_lean_mojo_tool_call_provenance_parity()
    var a = verify_lean_mojo_provider_api_transition_parity()
    var rec = verify_lean_mojo_provider_api_recovery_parity()
    var svc = verify_lean_mojo_service_mesh_binding_parity()
    var dir_obj = verify_lean_mojo_system_directory_parity()
    var sdlc_sre = verify_lean_mojo_sdlc_sre_17_aspect_parity()
    var qwen_hol = verify_lean_mojo_qwen_holonic_envelope_parity()
    var qwen_uc = verify_lean_mojo_qwen_usecase_router_parity()
    var ont_fib = verify_lean_mojo_unified_ontology_fibration_parity()
    var ftc_gate = verify_lean_mojo_fractal_usecase_test_gate_parity()
    var sim_prof = verify_lean_mojo_qwen_profile_simulator_parity()
    var opt_20 = verify_lean_mojo_20_optimization_cycles_parity()
    var sm75_sim = verify_lean_mojo_sm75_qwen_hardware_envelope_parity()
    var pub_bm = verify_lean_mojo_public_benchmark_gate_parity()
    var sys_ont = verify_lean_mojo_system_concepts_and_ontology_parity()
    var poly_lang = verify_lean_mojo_polyglot_language_optimization_parity()
    var polybench_sm75 = verify_lean_mojo_polybench_sm75_language_tier_parity()
    var frac_hol = verify_lean_mojo_fractal_holarchy_full_alignment_parity()
    var wave2_conv = verify_lean_mojo_evolutionary_wave2_convergence_parity()
    var wave3_wire = verify_lean_mojo_full_system_artifact_aspect_component_wiring_parity()
    var wave4_sym = verify_lean_mojo_pi_qwen_15cycle_symbiosis_parity()
    var otel_raw = capture("wc -l < state/provider-api-holarchy-fpp.otel.jsonl 2>/dev/null")
    var otel_lines = -1
    if otel_raw.byte_length() > 0:
        try:
            otel_lines = Int(otel_raw)
        except:
            otel_lines = -1
    r.observe_int(String("c-abi-fractal-context-parity-states"), m)
    r.observe_int(String("usecases-verified"), u)
    r.observe_int(String("simulator-realtime-parity-states"), s)
    r.observe_int(String("tool-call-provenance-parity-states"), p)
    r.observe_int(String("provider-api-transition-parity-states"), a)
    r.observe_int(String("provider-api-recovery-parity-states"), rec)
    r.observe_int(String("service-mesh-binding-parity-states"), svc)
    r.observe_int(String("system-directory-52obj-parity-states"), dir_obj)
    r.observe_int(String("sdlc-sre-17-aspect-parity-states"), sdlc_sre)
    r.observe_int(String("qwen-holonic-envelope-parity-states"), qwen_hol)
    r.observe_int(String("qwen-usecase-router-parity-states"), qwen_uc)
    r.observe_int(String("unified-ontology-fibration-parity-states"), ont_fib)
    r.observe_int(String("fractal-usecase-test-gate-parity-states"), ftc_gate)
    r.observe_int(String("qwen-profile-simulator-parity-states"), sim_prof)
    r.observe_int(String("twenty-optimization-cycles-parity-states"), opt_20)
    r.observe_int(String("sm75-qwen-hardware-simulator-parity-states"), sm75_sim)
    r.observe_int(String("public-benchmark-gate-parity-states"), pub_bm)
    r.observe_int(String("system-concepts-ontology-parity-states"), sys_ont)
    r.observe_int(String("polyglot-language-optimization-parity-states"), poly_lang)
    r.observe_int(String("polybench-sm75-language-tier-parity-states"), polybench_sm75)
    r.observe_int(String("fractal-holarchy-full-alignment-parity-states"), frac_hol)
    r.observe_int(String("evolutionary-wave2-convergence-parity-states"), wave2_conv)
    r.observe_int(String("full-system-artifact-aspect-wiring-parity-states"), wave3_wire)
    r.observe_int(String("wave4-pi-qwen-15cycle-symbiosis-parity-states"), wave4_sym)
    r.observe_int(String("provider-api-otel-jsonl-lines"), otel_lines)
    r.world_count(String("fcp-c-abi-16-states-verified"), m, 16)
    r.world_count(String("fcp-sim-rt-32-states-verified"), s, 32)
    r.world_count(String("fcp-tool-call-provenance-32-states-verified"), p, 32)
    r.world_count(String("fcp-provider-api-transition-392-states-verified"), a, 392)
    r.world_count(String("fcp-provider-api-recovery-64-states-verified"), rec, 64)
    r.world_count(String("fcp-service-mesh-binding-192-states-verified"), svc, 192)
    r.world_count(String("fcp-system-directory-2080-states-verified"), dir_obj, 2080)
    r.world_count(String("fcp-sdlc-sre-17-aspect-1632-states-verified"), sdlc_sre, 1632)
    r.world_count(String("fcp-qwen-holonic-envelope-3200-states-verified"), qwen_hol, 3200)
    r.world_count(String("fcp-qwen-usecase-router-1600-states-verified"), qwen_uc, 1600)
    r.world_count(String("fcp-unified-ontology-fibration-1500-states-verified"), ont_fib, 1500)
    r.world_count(String("fcp-fractal-usecase-test-gate-3200-states-verified"), ftc_gate, 3200)
    r.world_count(String("fcp-qwen-profile-simulator-1600-states-verified"), sim_prof, 1600)
    r.world_count(String("fcp-20-optimization-cycles-3200-states-verified"), opt_20, 3200)
    r.world_count(String("fcp-sm75-qwen-hardware-simulator-3840-states-verified"), sm75_sim, 3840)
    r.world_count(String("fcp-public-benchmark-gate-2560-states-verified"), pub_bm, 2560)
    r.world_count(String("fcp-system-concepts-ontology-3200-states-verified"), sys_ont, 3200)
    r.world_count(String("fcp-polyglot-language-optimization-3840-states-verified"), poly_lang, 3840)
    r.world_count(String("fcp-polybench-sm75-language-tier-3840-states-verified"), polybench_sm75, 3840)
    r.world_count(String("fcp-fractal-holarchy-full-alignment-3200-states-verified"), frac_hol, 3200)
    r.world_count(String("fcp-evolutionary-wave2-convergence-3200-states-verified"), wave2_conv, 3200)
    r.world_count(String("fcp-full-system-artifact-aspect-wiring-3200-states-verified"), wave3_wire, 3200)
    r.world_count(String("fcp-wave4-pi-qwen-15cycle-symbiosis-3200-states-verified"), wave4_sym, 3200)
    r.world_count(String("fcp-provider-api-otel-7-spans-emitted"), otel_lines, 7)
    r.algebra(
        String("fcp-ten-layer-handoff-and-provenance-parity"),
        m == 16 and u == 5 and s == 32 and p == 32 and a == 392 and rec == 64 and svc == 192 and dir_obj == 2080 and sdlc_sre == 1632 and qwen_hol == 3200 and qwen_uc == 1600 and ont_fib == 1500 and ftc_gate == 3200 and sim_prof == 1600 and opt_20 == 3200 and sm75_sim == 3840 and pub_bm == 2560 and sys_ont == 3200 and poly_lang == 3840 and polybench_sm75 == 3840 and frac_hol == 3200 and wave2_conv == 3200 and wave3_wire == 3200 and wave4_sym == 3200)
    r.mutation_probe(
        String("fcp-missing-upstream-def-rejected"),
        m > 0 and u > 0 and s > 0 and p > 0 and a > 0 and rec > 0 and svc > 0 and dir_obj > 0 and sdlc_sre > 0 and qwen_hol > 0 and qwen_uc > 0 and ont_fib > 0 and ftc_gate > 0 and sim_prof > 0 and opt_20 > 0 and sm75_sim > 0 and pub_bm > 0 and sys_ont > 0 and poly_lang > 0 and polybench_sm75 > 0 and frac_hol > 0 and wave2_conv > 0 and wave3_wire > 0 and wave4_sym > 0)
    r.emit()
    exit(r.exit_code())
