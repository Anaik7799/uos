# formal/mojo/lean_ffi_bridge.mojo
# ============================================================================
# SHARED MOJO <-> LEAN 4 C-ABI IN-PROCESS FFI BRIDGE (~49.5 ns/call)
# ============================================================================
# Reference:
#   - https://lean-lang.org/doc/reference/latest/Run-Time-Code/Foreign-Function-Interface/
#   - https://gist.github.com/ydewit/7ab62be1bd0fea5bd53b48d23914dd6b
#   - formal/lean/UosLeanRuntimeGuard.lean (14 @[export] C-ABI functions)

from std.ffi import OwnedDLHandle

comptime LEAN_GUARD_SO = "/home/an/NAS-setup/uos/var/zlp/libuos_lean_guard.so"

def select_failover_mojo(
    is_supervisor: UInt8,
    claude_ok: UInt8,
    codex_ok: UInt8,
    qwen_ok: UInt8,
    sup_ok: UInt8,
) -> UInt8:
    if is_supervisor == 1:
        if sup_ok == 1:
            return 4
        elif claude_ok == 1:
            return 1
        elif codex_ok == 1:
            return 2
        elif qwen_ok == 1:
            return 3
        else:
            return 0
    else:
        if claude_ok == 1:
            return 1
        elif codex_ok == 1:
            return 2
        elif qwen_ok == 1:
            return 3
        else:
            return 0

def verify_lean_c_abi_14_exports() -> Bool:
    try:
        var handle = OwnedDLHandle(LEAN_GUARD_SO)
        var check_intent = handle.get_function[UInt8]("uos_lean_check_intent")
        var route_cascade = handle.get_function[UInt8]("uos_lean_route_cascade")
        var verify_14stage = handle.get_function[UInt8]("uos_lean_verify_14stage_telemetry")
        var solve_atlas = handle.get_function[UInt32]("uos_lean_solve_atlas_budget")
        var classify_shannon = handle.get_function[UInt8]("uos_lean_classify_shannon_archetype")
        var should_fold = handle.get_function[UInt8]("uos_lean_should_fold_context")
        var classify_metabolic = handle.get_function[UInt8]("uos_lean_classify_metabolic_regime")
        var eval_immune = handle.get_function[UInt8]("uos_lean_eval_immune_breaker")
        var eval_lyapunov = handle.get_function[UInt8]("uos_lean_eval_lyapunov_stable")
        var verify_holon170 = handle.get_function[UInt8]("uos_lean_verify_170_holon_lattice")
        var verify_otel = handle.get_function[UInt8]("uos_lean_verify_otel_span_kpi")
        var eval_sla = handle.get_function[UInt8]("uos_lean_eval_context_kpi_sla")
        var select_failover = handle.get_function[UInt8]("uos_lean_select_failover_agent")
        var verify_fsys = handle.get_function[UInt8]("uos_lean_verify_full_system_twin")
        var cedar_auth = handle.get_function[UInt8]("uos_lean_cedar_authorize_mcp")
        var cedar_symcc = handle.get_function[UInt8]("uos_lean_cedar_symcc_verify")
        var cedar_dag = handle.get_function[UInt8]("uos_lean_cedar_dag_enforcer_check")
        var palamedes_gen = handle.get_function[UInt8]("uos_lean_palamedes_synthesize_gen")

        var ok1 = check_intent(UInt8(1), UInt8(1), UInt32(93), UInt32(95), UInt32(5446), UInt32(8192), UInt8(1))
        var veto94 = check_intent(UInt8(1), UInt8(1), UInt32(94), UInt32(95), UInt32(5446), UInt32(8192), UInt8(1))
        var tier0 = route_cascade(UInt32(920), ok1, UInt8(1))
        var stage14 = verify_14stage(UInt32(7), UInt32(7), UInt64(0), UInt32(5446), UInt8(1))
        var atlas0 = solve_atlas(UInt8(0))
        var arch0 = classify_shannon(UInt32(6200), UInt32(120), UInt32(7200), UInt32(80))
        var fold1 = should_fold(UInt32(28000), UInt32(50), UInt32(10))
        var fold0 = should_fold(UInt32(12000), UInt32(50), UInt32(10))
        var met3 = classify_metabolic(UInt32(7500))
        var imm2 = eval_immune(UInt8(2), UInt32(0), UInt32(94))
        var lyap1 = eval_lyapunov(UInt32(600), UInt32(0), UInt32(0), UInt32(0), UInt32(0))
        var hol1 = verify_holon170(UInt32(170), UInt8(1), UInt8(1), UInt32(8580), UInt32(71), UInt32(0))
        var otel1 = verify_otel(UInt8(1), UInt8(1), UInt8(3), UInt8(9), UInt8(1), UInt32(120), UInt32(72), UInt32(500))
        var sla1 = eval_sla(UInt32(9590), UInt32(6039), UInt32(49), UInt32(16), UInt32(12))
        var fail_qwen = select_failover(UInt8(0), UInt8(0), UInt8(0), UInt8(1), UInt8(1))
        var fsys1 = verify_fsys(UInt32(12), UInt32(11), UInt32(40), UInt32(18), UInt32(93))
        var c_allow = cedar_auth(UInt8(1), UInt8(0), UInt8(1), UInt32(93))
        var c_forbid = cedar_auth(UInt8(1), UInt8(1), UInt8(1), UInt32(93))
        var c_defdeny = cedar_auth(UInt8(0), UInt8(0), UInt8(1), UInt32(93))
        var sym_disj = cedar_symcc(UInt8(1), UInt8(1), UInt8(0), UInt8(0), UInt8(1))
        var dag_ok = cedar_dag(UInt8(1), UInt8(0), UInt8(1), UInt8(0), UInt8(1), UInt8(0), UInt8(1))
        var dag_rep = cedar_dag(UInt8(1), UInt8(0), UInt8(1), UInt8(0), UInt8(0), UInt8(0), UInt8(1))
        var pal_ok = palamedes_gen(UInt8(0), UInt8(1), UInt8(1))

        return (
            ok1 == 1 and veto94 == 0 and tier0 == 0 and stage14 == 1
            and atlas0 == 0x0C1D0120 and arch0 == 0 and fold1 == 1 and fold0 == 0
            and met3 == 3 and imm2 == 0x22 and lyap1 == 1 and hol1 == 1
            and otel1 == 1 and sla1 == 1 and fail_qwen == 3 and fsys1 == 1
            and c_allow == 1 and c_forbid == 0 and c_defdeny == 0 and sym_disj == 9
            and dag_ok == 3 and dag_rep == 2 and pal_ok == 7
        )
    except:
        return False

def verify_lean_mojo_failover_32_states() -> Int:
    try:
        var handle = OwnedDLHandle(LEAN_GUARD_SO)
        var select_failover = handle.get_function[UInt8]("uos_lean_select_failover_agent")
        var matched: Int = 0
        for mask in range(32):
            var is_sup = UInt8((mask >> 4) & 1)
            var cl_ok = UInt8((mask >> 3) & 1)
            var cx_ok = UInt8((mask >> 2) & 1)
            var qw_ok = UInt8((mask >> 1) & 1)
            var sp_ok = UInt8(mask & 1)
            var lean_res = select_failover(is_sup, cl_ok, cx_ok, qw_ok, sp_ok)
            var mojo_res = select_failover_mojo(is_sup, cl_ok, cx_ok, qw_ok, sp_ok)
            if lean_res == mojo_res:
                matched += 1
        return matched
    except:
        return -1

def cedar_authorize_mojo(any_permit: UInt8, any_forbid: UInt8, nvme_safe: UInt8, ev_id: UInt32) -> UInt8:
    if any_forbid == 1:
        return 0
    elif any_permit == 1 and nvme_safe == 1 and ev_id <= 93:
        return 1
    else:
        return 0

def cedar_symcc_mojo(well_typed: UInt8, a0: UInt8, a1: UInt8, b0: UInt8, b1: UInt8) -> UInt8:
    var b_never_err: UInt8 = 1 if well_typed == 1 else 0
    var b_implies: UInt8 = 2 if (a0 == 0 or b0 == 1) and (a1 == 0 or b1 == 1) else 0
    var b_equiv: UInt8 = 4 if (a0 == b0) and (a1 == b1) else 0
    var b_disjoint: UInt8 = 8 if not (a0 == 1 and b0 == 1) and not (a1 == 1 and b1 == 1) else 0
    var b_deny_all: UInt8 = 16 if a0 == 0 and a1 == 0 else 0
    return b_never_err + b_implies + b_equiv + b_disjoint + b_deny_all

def verify_lean_mojo_cedar_symcc_parity() -> Int:
    try:
        var handle = OwnedDLHandle(LEAN_GUARD_SO)
        var cedar_auth = handle.get_function[UInt8]("uos_lean_cedar_authorize_mcp")
        var cedar_symcc = handle.get_function[UInt8]("uos_lean_cedar_symcc_verify")
        var matched: Int = 0
        for mask in range(16):
            var a0 = UInt8((mask >> 3) & 1)
            var a1 = UInt8((mask >> 2) & 1)
            var b0 = UInt8((mask >> 1) & 1)
            var b1 = UInt8(mask & 1)
            if cedar_symcc(UInt8(1), a0, a1, b0, b1) == cedar_symcc_mojo(UInt8(1), a0, a1, b0, b1):
                matched += 1
        for amask in range(8):
            var p = UInt8((amask >> 2) & 1)
            var f = UInt8((amask >> 1) & 1)
            var nv = UInt8(amask & 1)
            if cedar_auth(p, f, nv, UInt32(93)) == cedar_authorize_mojo(p, f, nv, UInt32(93)):
                matched += 1
        return matched
    except:
        return -1

def verify_lean_mojo_dag_and_palamedes_parity() -> Int:
    try:
        var handle = OwnedDLHandle(LEAN_GUARD_SO)
        var cedar_dag = handle.get_function[UInt8]("uos_lean_cedar_dag_enforcer_check")
        var palamedes_gen = handle.get_function[UInt8]("uos_lean_palamedes_synthesize_gen")
        var matched: Int = 0
        for mask in range(64):
            var e01 = UInt8((mask >> 0) & 1)
            var e10 = UInt8((mask >> 1) & 1)
            var e12 = UInt8((mask >> 2) & 1)
            var e21 = UInt8((mask >> 3) & 1)
            var e02 = UInt8((mask >> 4) & 1)
            var e20 = UInt8((mask >> 5) & 1)
            var c_res = cedar_dag(e01, e10, e12, e21, e02, e20, UInt8(1))
            var raw_acyclic = (
                not (e01 == 1 and e10 == 1)
                and not (e12 == 1 and e21 == 1)
                and not (e02 == 1 and e20 == 1)
                and not (e01 == 1 and e12 == 1 and e20 == 1)
                and not (e02 == 1 and e21 == 1 and e10 == 1)
            )
            var raw_trans = (
                (not (e01 == 1 and e12 == 1) or e02 == 1)
                and (not (e10 == 1 and e02 == 1) or e12 == 1)
                and (not (e12 == 1 and e20 == 1) or e10 == 1)
                and (not (e21 == 1 and e10 == 1) or e20 == 1)
                and (not (e02 == 1 and e21 == 1) or e01 == 1)
                and (not (e20 == 1 and e01 == 1) or e21 == 1)
            )
            var expected: UInt8 = 3 if (raw_acyclic and raw_trans) else 2
            if c_res == expected:
                matched += 1
        for pmask in range(8):
            var p0 = UInt8((pmask >> 2) & 1)
            var p1 = UInt8((pmask >> 1) & 1)
            var q = UInt8(pmask & 1)
            var p_res = palamedes_gen(p0, p1, q)
            var b_sup: UInt8 = 1
            var b_red: UInt8 = 2 if (p0 == 0 or p1 == 0) else 0
            var b_mm: UInt8 = 4 if ((p0 == 1 or p1 == 1) and not (p0 == 1 and p1 == 1)) else 0
            if p_res == (b_sup + b_red + b_mm):
                matched += 1
        return matched
    except:
        return -1

def verify_lean_mojo_fractal_context_chain_parity() -> Int:
    try:
        var handle = OwnedDLHandle(LEAN_GUARD_SO)
        var verify_chain = handle.get_function[UInt8]("uos_lean_verify_fractal_context_chain")
        var matched: Int = 0
        for mask in range(16):
            var cov: UInt32 = 1023 if ((mask >> 3) & 1) == 1 else 1022
            var miss: UInt32 = 0 if ((mask >> 2) & 1) == 0 else 1
            var links: UInt8 = 9 if ((mask >> 1) & 1) == 1 else 8
            var pi_tok: UInt32 = 0 if (mask & 1) == 0 else 1
            var c_res = verify_chain(cov, miss, links, pi_tok)
            var expected: UInt8 = 1 if (cov == 1023 and miss == 0 and links == 9 and pi_tok == 0) else 0
            if c_res == expected:
                matched += 1
        return matched
    except:
        return -1

def verify_lean_mojo_simulator_realtime_parity() -> Int:
    try:
        var handle = OwnedDLHandle(LEAN_GUARD_SO)
        var verify_sim = handle.get_function[UInt8]("uos_lean_verify_simulator_realtime_parity")
        var matched: Int = 0
        for mask in range(32):
            var sim_ag: UInt8 = 1
            var rt_ag: UInt8 = 1 if ((mask >> 4) & 1) == 1 else 2
            var sim_cd: UInt8 = 1
            var rt_cd: UInt8 = 1 if ((mask >> 3) & 1) == 1 else 0
            var sim_dg: UInt8 = 1
            var rt_dg: UInt8 = 1 if ((mask >> 2) & 1) == 1 else 0
            var sim_ls: UInt8 = 1
            var rt_ls: UInt8 = 1 if ((mask >> 1) & 1) == 1 else 0
            var ctx_ok: UInt8 = 1 if (mask & 1) == 1 else 0
            var c_res = verify_sim(sim_ag, rt_ag, sim_cd, rt_cd, sim_dg, rt_dg, sim_ls, rt_ls, ctx_ok, ctx_ok)
            var expected: UInt8 = 1 if (rt_ag == 1 and rt_cd == 1 and rt_dg == 1 and rt_ls == 1 and ctx_ok == 1) else 0
            if c_res == expected:
                matched += 1
        return matched
    except:
        return -1
