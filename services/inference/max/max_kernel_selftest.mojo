from max_kernel import (
    simd_dot_product, vector_norm, simd_cosine_similarity,
    softmax_tensor, gelu,
    meend_pitch_s_curve, tanpura_jawari_shimmer, tabla_bayan_pitch_glide,
    spectral_shannon_entropy, lyapunov_stability_index,
    calculate_rpn, map_rpn_to_sil,
    simd_ast_anomaly_distance, simd_zk_transclusion_score,
    compute_finite_time_lyapunov_exponent, estimate_time_to_cascade,
    simd_stpa_fmea_hazard_eval, simd_rete_conflict_resolution,
    simd_ruliad_branchial_distance, simd_shruti_harmonic_synthesis,
)
from std.math import sqrt

def check(name: String, got: Float32, want: Float32, tol: Float32) -> Int:
    var d = got - want
    if d < 0.0:
        d = -d
    if d <= tol:
        print("PASS", name, "got", got)
        return 0
    else:
        print("FAIL", name, "got", got, "want", want)
        return 1

def main():
    var failures: Int = 0
    # 20 elements: exercises BOTH the 16-wide SIMD loop and the 4-element remainder
    var a = List[Float32]()
    var ones = List[Float32]()
    for i in range(20):
        a.append(Float32(i + 1))
        ones.append(1.0)
    failures += check("simd_dot_product 20x(1..20)", simd_dot_product(a, ones), 210.0, 1e-3)

    var v34 = List[Float32]()
    v34.append(3.0)
    v34.append(4.0)
    failures += check("vector_norm(3,4)", vector_norm(v34), 5.0, 1e-5)
    failures += check("cosine_similarity(a,a)", simd_cosine_similarity(a, a), 1.0, 1e-4)

    var flat = List[Float32]()
    for _ in range(4):
        flat.append(1.0)
    var sm = softmax_tensor(flat)
    failures += check("softmax uniform[0]", sm[0], 0.25, 1e-5)
    failures += check("softmax len", Float32(len(sm)), 4.0, 0.0)
    failures += check("softmax empty len", Float32(len(softmax_tensor(List[Float32]()))), 0.0, 0.0)

    failures += check("gelu(0)", gelu(0.0), 0.0, 1e-6)
    failures += check("gelu(1)", gelu(1.0), 0.841192, 1e-4)

    failures += check("meend midpoint", meend_pitch_s_curve(100.0, 200.0, 0.5, 1.0, 8.0), 150.0, 1e-3)
    failures += check("meend zero duration", meend_pitch_s_curve(100.0, 200.0, 0.5, 0.0, 8.0), 200.0, 0.0)
    failures += check("jawari n=4 p=0", tanpura_jawari_shimmer(220.0, 4, 0.0), 0.548812, 1e-4)
    failures += check("bayan past strike", tabla_bayan_pitch_glide(90.0, 2.0, 1.0, 30.0), 90.0, 0.0)

    var quarters = List[Float32]()
    for _ in range(4):
        quarters.append(0.25)
    failures += check("shannon entropy 4x0.25", spectral_shannon_entropy(quarters), 2.0, 1e-5)

    var doubling = List[Float32]()
    doubling.append(1.0)
    doubling.append(2.0)
    doubling.append(4.0)
    failures += check("lyapunov doubling", lyapunov_stability_index(doubling), 1.0, 1e-5)

    failures += check("rpn 5*4*3", Float32(calculate_rpn(5, 4, 3)), 60.0, 0.0)
    if map_rpn_to_sil(60) == "SIL-3" and map_rpn_to_sil(300) == "SIL-6" and map_rpn_to_sil(1) == "SIL-1":
        print("PASS map_rpn_to_sil bands")
    else:
        print("FAIL map_rpn_to_sil bands")
        failures += 1

    failures += check("ast anomaly self", simd_ast_anomaly_distance(a, a), 0.0, 1e-4)
    failures += check("zk transclusion self*0.5", simd_zk_transclusion_score(a, a, 0.5), 0.5, 1e-4)

    var telem = List[Float32]()
    telem.append(1.0)
    telem.append(1.1)
    telem.append(1.21)
    var lam = compute_finite_time_lyapunov_exponent(telem, 1.0)
    print("INFO ftle =", lam)
    failures += check("ftle too short", compute_finite_time_lyapunov_exponent(v34, 1.0), 0.0, 0.0)
    failures += check("cascade unreachable", estimate_time_to_cascade(1.0, 0.5, 0.5), -1.0, 0.0)
    failures += check("cascade log2(4)/1", estimate_time_to_cascade(1.0, 4.0, 1.0), 2.0, 1e-5)

    # rpn 5*5*5=125 > 120 -> band 5; fmea max(5,5)=5; 4*5*3 = 60
    failures += check("stpa/fmea hazard", simd_stpa_fmea_hazard_eval(5.0, 5.0, 5.0, 4.0, 3.0), 60.0, 1e-4)

    var sal = List[Float32]()
    var spec = List[Float32]()
    var ranks = List[Float32]()
    sal.append(90.0); spec.append(1.0); ranks.append(0.0)
    sal.append(10.0); spec.append(1.0); ranks.append(9.0)
    failures += check("rete picks layer rank", Float32(simd_rete_conflict_resolution(sal, spec, ranks)), 1.0, 0.0)
    failures += check("rete empty", Float32(simd_rete_conflict_resolution(List[Float32](), List[Float32](), List[Float32]())), -1.0, 0.0)

    failures += check("ruliad self distance", simd_ruliad_branchial_distance(a, a), 0.0, 1e-3)

    var ratios = List[Float32]()
    var amps = List[Float32]()
    ratios.append(1.0); amps.append(1.0)
    ratios.append(1.5); amps.append(2.0)
    # 240*1*1 + 240*1.5*2*2 = 240 + 1440 = 1680
    failures += check("shruti harmonic energy", simd_shruti_harmonic_synthesis(240.0, ratios, amps), 1680.0, 1e-2)

    print("")
    if failures == 0:
        print("MAX_KERNEL SELFTEST: ALL CHECKS PASSED")
    else:
        print("MAX_KERNEL SELFTEST: FAILURES =", failures)
