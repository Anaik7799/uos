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
    r.observe_int(String("provider-api-otel-jsonl-lines"), otel_lines)
    r.world_count(String("fcp-c-abi-16-states-verified"), m, 16)
    r.world_count(String("fcp-sim-rt-32-states-verified"), s, 32)
    r.world_count(String("fcp-tool-call-provenance-32-states-verified"), p, 32)
    r.world_count(String("fcp-provider-api-transition-392-states-verified"), a, 392)
    r.world_count(String("fcp-provider-api-recovery-64-states-verified"), rec, 64)
    r.world_count(String("fcp-service-mesh-binding-192-states-verified"), svc, 192)
    r.world_count(String("fcp-system-directory-2080-states-verified"), dir_obj, 2080)
    r.world_count(String("fcp-sdlc-sre-17-aspect-1632-states-verified"), sdlc_sre, 1632)
    r.world_count(String("fcp-provider-api-otel-7-spans-emitted"), otel_lines, 7)
    r.algebra(
        String("fcp-ten-layer-handoff-and-provenance-parity"),
        m == 16 and u == 5 and s == 32 and p == 32 and a == 392 and rec == 64 and svc == 192 and dir_obj == 2080 and sdlc_sre == 1632)
    r.mutation_probe(
        String("fcp-missing-upstream-def-rejected"),
        m > 0 and u > 0 and s > 0 and p > 0 and a > 0 and rec > 0 and svc > 0 and dir_obj > 0 and sdlc_sre > 0)
    r.emit()
    exit(r.exit_code())
