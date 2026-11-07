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
    rmsnorm_tensor, swiglu_activation,
    simd_rotary_position_embedding, simd_scaled_dot_product_attention,
    simd_temporal_convolution_1d,
    matvec_mul, simd_dequantize_q8_0, simd_dot_product_q8_0,
    simd_dequantize_q4_0, gemma_embedding_lookup,
    gemma_swiglu_mlp, gemma_transformer_layer,
    simd_dequantize_q4_k_block, simd_dequantize_q6_k_block,
    qwen2_transformer_layer,
    turing_sm75_m16n8k8_matvec_tile,
    speculative_draft_verify_step,
    grammar_constrained_logit_mask,
    grammar_constrained_greedy_select,
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

    # 13. Deep Transformer & Neural Attention Tests
    var v_const = List[Float32]()
    var g_ones = List[Float32]()
    for _ in range(4):
        v_const.append(2.0)
        g_ones.append(1.0)
    var rms_out = rmsnorm_tensor(v_const, g_ones, 0.0)
    failures += check("rmsnorm uniform[0]", rms_out[0], 1.0, 1e-5)
    failures += check("rmsnorm len", Float32(len(rms_out)), 4.0, 0.0)

    failures += check("swiglu(0, 10)", swiglu_activation(0.0, 10.0), 0.0, 1e-5)
    failures += check("swiglu(1, 2)", swiglu_activation(1.0, 2.0), 1.4621172, 1e-4)

    # At pos 0, RoPE is identity (phi=0 => cos=1, sin=0)
    var rope_p0 = simd_rotary_position_embedding(v_const, 10000.0, 0)
    failures += check("rope pos 0 identity[0]", rope_p0[0], 2.0, 1e-5)
    failures += check("rope pos 0 identity[1]", rope_p0[1], 2.0, 1e-5)

    # Scaled Dot-Product Attention: single key/val equals query => softmax weight 1.0 => output equals value
    var att_keys = List[List[Float32]]()
    var att_vals = List[List[Float32]]()
    att_keys.append(v_const.copy())
    att_vals.append(v_const.copy())
    var att_out = simd_scaled_dot_product_attention(v_const, att_keys, att_vals, 4.0)
    failures += check("attention single-key[0]", att_out[0], 2.0, 1e-5)
    failures += check("attention single-key[3]", att_out[3], 2.0, 1e-5)

    # Causal 1D Convolution: sig=[1,2,3,4], kern=[0.5, 0.25]
    var sig = List[Float32]()
    sig.append(1.0); sig.append(2.0); sig.append(3.0); sig.append(4.0)
    var kern = List[Float32]()
    kern.append(0.5); kern.append(0.25)
    var conv_out = simd_temporal_convolution_1d(sig, kern)
    failures += check("conv1d[0]", conv_out[0], 0.5, 1e-5)
    failures += check("conv1d[1]", conv_out[1], 1.25, 1e-5)
    failures += check("conv1d[2]", conv_out[2], 2.0, 1e-5)
    failures += check("conv1d[3]", conv_out[3], 2.75, 1e-5)

    # 14. Gemma Architecture Transformer Layer & SIMD Dequantization Tests
    var q8_scales = List[Float32]()
    q8_scales.append(0.5)
    var q8_quants = List[Int8]()
    for _ in range(32):
        q8_quants.append(Int8(4))
    var deq8 = simd_dequantize_q8_0(q8_scales, q8_quants)
    failures += check("q8_0 dequant len", Float32(len(deq8)), 32.0, 0.0)
    failures += check("q8_0 dequant[0]", deq8[0], 2.0, 1e-5)

    var ones32 = List[Float32]()
    for _ in range(32):
        ones32.append(1.0)
    # 32 * 4 * 1.0 * 0.5 = 64.0
    failures += check("q8_0 dot product", simd_dot_product_q8_0(q8_scales, q8_quants, ones32), 64.0, 1e-4)

    var q4_scales = List[Float32]()
    q4_scales.append(0.25)
    var q4_packed = List[UInt8]()
    for _ in range(16):
        q4_packed.append(UInt8(0xAA)) # 10 - 8 = 2, 10 - 8 = 2
    var deq4 = simd_dequantize_q4_0(q4_scales, q4_packed)
    failures += check("q4_0 dequant len", Float32(len(deq4)), 32.0, 0.0)
    failures += check("q4_0 dequant[0]", deq4[0], 0.5, 1e-5)
    failures += check("q4_0 dequant[1]", deq4[1], 0.5, 1e-5)

    var vocab = List[List[Float32]]()
    var tok0 = List[Float32]()
    tok0.append(2.0); tok0.append(3.0)
    vocab.append(tok0.copy())
    # embed lookup token 0 with d_model=4 => scale = sqrt(4)=2 => [4.0, 6.0]
    var emb = gemma_embedding_lookup(vocab, 0, 4.0)
    failures += check("gemma embed len", Float32(len(emb)), 2.0, 0.0)
    failures += check("gemma embed[0]", emb[0], 4.0, 1e-5)
    failures += check("gemma embed[1]", emb[1], 6.0, 1e-5)

    # Full Gemma Transformer block forward pass
    var eye4 = List[List[Float32]]()
    for i in range(4):
        var row = List[Float32]()
        for j in range(4):
            if i == j:
                row.append(1.0)
            else:
                row.append(0.0)
        eye4.append(row.copy())
    var gemma_out = gemma_transformer_layer(
        v_const, g_ones, eye4, eye4, eye4, eye4, g_ones, eye4, eye4, eye4, 0, 4.0
    )
    failures += check("gemma layer out len", Float32(len(gemma_out)), 4.0, 0.0)
    failures += check("gemma layer out[0]", gemma_out[0], 3.731058, 1e-3)

    # 15. GGUF K-Quant Super-Block Dequantization Tests (Q4_K & Q6_K)
    var q4k_scales = List[UInt8]()
    for _ in range(12):
        q4k_scales.append(UInt8(1))
    var q4k_quants = List[UInt8]()
    for _ in range(128):
        q4k_quants.append(UInt8(0x22)) # 4-bit val = 2
    var deq4k = simd_dequantize_q4_k_block(1.0, 0.0, q4k_scales, q4k_quants)
    failures += check("q4_k dequant len", Float32(len(deq4k)), 256.0, 0.0)
    failures += check("q4_k dequant[0]", deq4k[0], 2.0, 1e-4)

    var q6k_scales = List[Int8]()
    for _ in range(16):
        q6k_scales.append(Int8(1))
    var q6k_ql = List[UInt8]()
    for _ in range(128):
        q6k_ql.append(UInt8(0x00)) # low 4 bits = 0
    var q6k_qh = List[UInt8]()
    for _ in range(64):
        q6k_qh.append(UInt8(0x55)) # 01010101b -> each 2-bit = 1 -> high 2 bits = 1 -> (1<<4) = 16 -> 16 - 32 = -16
    var deq6k = simd_dequantize_q6_k_block(1.0, q6k_scales, q6k_ql, q6k_qh)
    failures += check("q6_k dequant len", Float32(len(deq6k)), 256.0, 0.0)
    failures += check("q6_k dequant[0]", deq6k[0], -16.0, 1e-4)

    # 16. Qwen2 Single Transformer Block Layer Test
    var qwen_out = qwen2_transformer_layer(
        v_const, eye4, eye4, eye4, eye4, g_ones, eye4, eye4, eye4, g_ones, 0, 4.0
    )
    failures += check("qwen2 layer out len", Float32(len(qwen_out)), 4.0, 0.0)
    failures += check("qwen2 layer out[0]", qwen_out[0], 3.731058, 1e-3)

    # 17. Turing sm_75 Tensor Core m16n8k8 Tiled MatVec Test
    var m16_weights = List[List[Float32]]()
    var k8_act = List[Float32]()
    for k in range(8):
        k8_act.append(Float32(k + 1)) # sum 1..8 = 36
    for _ in range(16):
        var row8 = List[Float32]()
        for _ in range(8):
            row8.append(2.0)
        m16_weights.append(row8.copy())
    var tc_out = turing_sm75_m16n8k8_matvec_tile(m16_weights, k8_act)
    failures += check("turing sm75 m16n8k8 len", Float32(len(tc_out)), 16.0, 0.0)
    failures += check("turing sm75 m16n8k8[0]", tc_out[0], 72.0, 1e-4)

    # 18. Speculative Draft Model Verification Pipeline Test
    var draft_toks = List[Int]()
    draft_toks.append(101); draft_toks.append(102); draft_toks.append(103)
    var draft_p = List[Float32]()
    draft_p.append(0.5); draft_p.append(0.8); draft_p.append(0.5)
    var target_p = List[Float32]()
    target_p.append(0.6); target_p.append(0.2); target_p.append(0.9)
    var u_samples = List[Float32]()
    u_samples.append(0.9); u_samples.append(0.5); u_samples.append(0.1)
    # Token 0 accepted (0.9 <= min(1, 0.6/0.5)=1.0), Token 1 rejected (0.5 > 0.2/0.8=0.25) -> emits [101, 999]
    var spec_out = speculative_draft_verify_step(draft_toks, draft_p, target_p, u_samples, 999)
    failures += check("speculative verify len", Float32(len(spec_out)), 2.0, 0.0)
    failures += check("speculative verify[0]", Float32(spec_out[0]), 101.0, 0.0)
    failures += check("speculative verify[1] bonus", Float32(spec_out[1]), 999.0, 0.0)

    # 19. Pure Mojo Grammar-Guided Constrained Decoding Test
    var raw_logits = List[Float32]()
    raw_logits.append(12.5); raw_logits.append(4.2); raw_logits.append(8.9)
    var gram_mask = List[Bool]()
    gram_mask.append(False); gram_mask.append(True); gram_mask.append(True)
    var masked_logits = grammar_constrained_logit_mask(raw_logits, gram_mask)
    var best_tok = grammar_constrained_greedy_select(raw_logits, gram_mask)
    failures += check("grammar masked disallowed[0]", masked_logits[0], -1000000000.0, 1.0)
    failures += check("grammar greedy select token 2", Float32(best_tok), 2.0, 0.0)

    print("")
    if failures == 0:
        print("MAX_KERNEL SELFTEST: ALL CHECKS PASSED")
    else:
        print("MAX_KERNEL SELFTEST: FAILURES =", failures)
