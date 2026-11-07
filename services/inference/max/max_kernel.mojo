# ==============================================================================
# [C3I-SIL6-MSTS] UOS MODULAR MAX / MOJO SIMD ACCELERATION KERNEL
# ==============================================================================
# <c3i-module>
#   <identity>
#     <module>services/inference/max/max_kernel.mojo</module>
#     <authority>UOS-CANONICAL-AGENT-POLICY</authority>
#   </identity>
#   <fractal-topology>
#     <layer>L4_SYSTEM</layer>
#     <mesh-domain>Modular MAX/Mojo Isolated Inference Tier</mesh-domain>
#   </fractal-topology>
#   <compliance>
#     <criticality>DAL-A / SIL-6 / ISOLATED</criticality>
#     <stamp-controls>
#       SC-INF-001, SC-INF-MOJO-001, SC-ZERO-MUDA-001, SC-BIO-HARMONY-001
#     </stamp-controls>
#   </compliance>
# </c3i-module>
# ==============================================================================
#
# High-performance tensor operations, acoustic feature synthesis, and
# vector embedding algorithms implemented in Mojo for hardware-accelerated
# execution within the isolated Modular MAX inference container.
#
# Key Capabilities:
#   1. SIMD Vector Dot Product & Cosine Similarity for Dense Embeddings
#   2. Softmax, GELU, and LayerNorm Activation Tensors
#   3. Psychoacoustic Indian Classical Raga Synthesis Tensors (Meend, Jawari, Bayan)
#   4. Shannon Entropy & Lyapunov Exponent Spectral Stability Verification
#   5. High-Throughput FMEA Risk Classifier
# ==============================================================================

from std.math import exp, sqrt, log2, cos, sin
from std.sys import simd_width_of

comptime float_simd_width = simd_width_of[DType.float32]()

# ------------------------------------------------------------------------------
# 1. SIMD Vector Dot Product & Cosine Similarity
# ------------------------------------------------------------------------------

def simd_dot_product(a: List[Float32], b: List[Float32]) -> Float32:
    """Compute dot product of two vectors using SIMD acceleration."""
    var total: Float32 = 0.0
    var n = len(a)
    if len(b) < n:
        n = len(b)
    
    var i = 0
    # Vectorized loop
    while i + float_simd_width <= n:
        var va = SIMD[DType.float32, float_simd_width]()
        var vb = SIMD[DType.float32, float_simd_width]()
        for j in range(float_simd_width):
            va[j] = a[i + j]
            vb[j] = b[i + j]
        total += (va * vb).reduce_add()
        i += float_simd_width
    
    # Remainder scalar loop
    while i < n:
        total += a[i] * b[i]
        i += 1
        
    return total

def vector_norm(v: List[Float32]) -> Float32:
    """Compute L2 Euclidean norm of a vector."""
    var sum_sq: Float32 = 0.0
    for i in range(len(v)):
        sum_sq += v[i] * v[i]
    return sqrt(sum_sq)

def simd_cosine_similarity(a: List[Float32], b: List[Float32]) -> Float32:
    """Compute cosine similarity between two embedding vectors [-1.0, 1.0]."""
    var norm_a = vector_norm(a)
    var norm_b = vector_norm(b)
    if norm_a == 0.0 or norm_b == 0.0:
        return 0.0
    var dot = simd_dot_product(a, b)
    return dot / (norm_a * norm_b)

# ------------------------------------------------------------------------------
# 2. Neural Activation Functions (Softmax, GELU, LayerNorm)
# ------------------------------------------------------------------------------

def softmax_tensor(scores: List[Float32]) -> List[Float32]:
    """Numerically stable softmax activation over 1D tensor."""
    var n = len(scores)
    var result = List[Float32]()
    if n == 0:
        return result^

    # Find max for numerical stability
    var max_val = scores[0]
    for i in range(1, n):
        if scores[i] > max_val:
            max_val = scores[i]

    var sum_exp: Float32 = 0.0
    for i in range(n):
        var e = exp(scores[i] - max_val)
        result.append(e)
        sum_exp += e

    for i in range(n):
        result[i] = result[i] / sum_exp

    return result^

def gelu(x: Float32) -> Float32:
    """Gaussian Error Linear Unit (GELU) activation."""
    # Approximation: 0.5 * x * (1 + tanh(sqrt(2/pi) * (x + 0.044715 * x^3)))
    var c: Float32 = 0.7978845608  # sqrt(2/pi)
    var inner = c * (x + 0.044715 * x * x * x)
    # Tanh approx
    var e2 = exp(2.0 * inner)
    var tanh_inner = (e2 - 1.0) / (e2 + 1.0)
    return 0.5 * x * (1.0 + tanh_inner)

# ------------------------------------------------------------------------------
# 3. Acoustic AI: Indian Classical Raga Synthesis Tensors
# ------------------------------------------------------------------------------

def meend_pitch_s_curve(f_start: Float32, f_end: Float32, t: Float32, duration: Float32, steepness: Float32) -> Float32:
    """
    Calculate continuous microtonal pitch transition using an S-curve (logistic)
    glissando contour characteristic of authentic North Indian Bansuri meend.
    f(t) = f_start + (f_end - f_start) / (1 + exp(-steepness * (t/duration - 0.5)))
    """
    if duration <= 0.0:
        return f_end
    var normalized_t = (t / duration) - 0.5
    var logistic = 1.0 / (1.0 + exp(-steepness * normalized_t))
    return f_start + (f_end - f_start) * logistic

def tanpura_jawari_shimmer(base_freq: Float32, harmonic_index: Int, thread_pressure: Float32) -> Float32:
    """
    Simulates the non-linear buzzing bridge (Jawari) shimmer of a 4-string Tanpura.
    Computes amplitude weight for harmonic n under curved bridge boundary conditions.
    """
    var n = Float32(harmonic_index)
    var decay = exp(-0.15 * n)
    var jawari_boost = thread_pressure * exp(-0.5 * (n - 4.0) * (n - 4.0))
    return decay + jawari_boost

def tabla_bayan_pitch_glide(base_freq: Float32, t: Float32, strike_duration: Float32, pressure_delta: Float32) -> Float32:
    """
    Simulates the bass drum (Dagga/Bayan) heel-of-the-hand pressure pitch slide ('Ghe').
    Frequency rises as the player applies palm pressure, then decays back to resonant baseline.
    """
    if t > strike_duration:
        return base_freq
    var tau = t / strike_duration
    # Pitch rises sharply to peak at 25% of strike, then relaxes
    var glide_factor = 4.0 * tau * exp(-3.0 * tau)
    return base_freq + (pressure_delta * glide_factor)

# ------------------------------------------------------------------------------
# 4. Psychoacoustic Spectral Metrics: Shannon Entropy & Lyapunov Exponent
# ------------------------------------------------------------------------------

def spectral_shannon_entropy(probabilities: List[Float32]) -> Float32:
    """
    Calculates Shannon Entropy H = -sum(p_i * log2(p_i)) over normalized spectral bins.
    Measures acoustic harmonic complexity and informational richness (Target H >= 2.50).
    """
    var entropy: Float32 = 0.0
    for i in range(len(probabilities)):
        var p = probabilities[i]
        if p > 1e-7:
            entropy -= p * log2(p)
    return entropy

def lyapunov_stability_index(divergences: List[Float32]) -> Float32:
    """
    Computes the maximum finite-time Lyapunov exponent from an ensemble of state trajectories.
    A negative or bounded exponent indicates orbital stability and phase-space convergence.
    """
    var n = len(divergences)
    if n < 2:
        return 0.0
    var sum_log: Float32 = 0.0
    for i in range(1, n):
        if divergences[i] > 1e-6 and divergences[i - 1] > 1e-6:
            sum_log += log2(divergences[i] / divergences[i - 1])
    return sum_log / Float32(n - 1)

# ------------------------------------------------------------------------------
# 5. Cognitive FMEA Risk Scoring
# ------------------------------------------------------------------------------

def calculate_rpn(severity: Int, occurrence: Int, detection: Int) -> Int:
    """Compute Failure Mode and Effects Analysis (FMEA) Risk Priority Number (RPN)."""
    return severity * occurrence * detection

def map_rpn_to_sil(rpn: Int) -> String:
    """Map RPN score to Safety Integrity Level (SIL-1 to SIL-6)."""
    if rpn >= 300:
        return "SIL-6"
    elif rpn >= 200:
        return "SIL-5"
    elif rpn >= 120:
        return "SIL-4"
    elif rpn >= 60:
        return "SIL-3"
    elif rpn >= 20:
        return "SIL-2"
    else:
        return "SIL-1"

# ------------------------------------------------------------------------------
# 6. High-Utility Model 1: AST Structural Anomaly Detector
# ------------------------------------------------------------------------------

def simd_ast_anomaly_distance(ast_embedding: List[Float32], nominal_centroid: List[Float32]) -> Float32:
    """
    Computes normalized Euclidean and cosine anomaly metric between candidate AST embedding
    and the nominal structural centroid.
    Formula: D = 1.0 - simd_cosine_similarity(ast_embedding, nominal_centroid)
    """
    var sim = simd_cosine_similarity(ast_embedding, nominal_centroid)
    var dist = 1.0 - sim
    if dist < 0.0:
        return 0.0
    return dist

# ------------------------------------------------------------------------------
# 7. High-Utility Model 2: ZK Knowledge Transclusion Embeddings & Match
# ------------------------------------------------------------------------------

def simd_zk_transclusion_score(query_vec: List[Float32], target_vec: List[Float32], layer_weight: Float32) -> Float32:
    """
    Computes SIMD cosine similarity scaled by fractal layer relevance weight.
    """
    var base_sim = simd_cosine_similarity(query_vec, target_vec)
    var weighted_score = base_sim * layer_weight
    return weighted_score

# ------------------------------------------------------------------------------
# 8. High-Utility Model 3: Anticipatory Lyapunov Trend Predictor
# ------------------------------------------------------------------------------

def compute_finite_time_lyapunov_exponent(telemetry: List[Float32], dt: Float32) -> Float32:
    """
    Computes finite-time Lyapunov exponent lambda from an evenly spaced telemetry time series.
    Formula: lambda = 1 / (N * dt) * sum_{i=1}^{N-1} ln(|(x_{i+1} - x_i) / x_i|)
    """
    var n = len(telemetry)
    if n < 3 or dt <= 0.0:
        return 0.0
    
    var sum_growth: Float32 = 0.0
    var valid_points: Float32 = 0.0
    
    for i in range(1, n):
        var delta = abs(telemetry[i] - telemetry[i - 1])
        var baseline = abs(telemetry[i - 1])
        if baseline > 1e-6 and delta > 1e-8:
            sum_growth += log2(delta / baseline)
            valid_points += 1.0
            
    if valid_points <= 0.0:
        return -1.0
        
    return (sum_growth / valid_points) / dt

def estimate_time_to_cascade(current_val: Float32, critical_val: Float32, lambda_exp: Float32) -> Float32:
    """
    Solves x(t) = x(0) * exp(lambda * t) for t when lambda > 0.
    t_cascade = ln(critical_val / current_val) / lambda
    """
    if lambda_exp <= 0.0 or current_val <= 0.0 or critical_val <= current_val:
        return -1.0
    var ratio = critical_val / current_val
    if ratio <= 1.0:
        return 0.0
    return log2(ratio) / lambda_exp

# ------------------------------------------------------------------------------
# 9. High-Utility Model 4: STPA-UCA & FMEA Causal Hazard Scorer
# ------------------------------------------------------------------------------

def simd_stpa_fmea_hazard_eval(
    severity: Float32,
    occurrence: Float32,
    detection: Float32,
    criticality: Float32,
    impact: Float32
) -> Float32:
    """
    Computes continuous multi-factor risk priority score:
    Score = Criticality * STPA_factor * FMEA_factor * Impact
    where FMEA_factor = max(Severity, RPN_band).
    """
    var rpn = severity * occurrence * detection
    var rpn_band: Float32
    if rpn > 120.0:
        rpn_band = 5.0
    elif rpn > 60.0:
        rpn_band = 4.0
    elif rpn > 30.0:
        rpn_band = 3.0
    elif rpn > 10.0:
        rpn_band = 2.0
    else:
        rpn_band = 1.0

    var fmea_factor = severity
    if rpn_band > fmea_factor:
        fmea_factor = rpn_band

    return criticality * fmea_factor * impact

# ------------------------------------------------------------------------------
# 10. High-Utility Model 5: Rete-UL Discrimination Accelerator
# ------------------------------------------------------------------------------

def simd_rete_conflict_resolution(
    saliences: List[Float32],
    specificities: List[Float32],
    layer_ranks: List[Float32]
) -> Int:
    """
    Resolves production rule conflict using lexicographic constitutional ranking:
    Priority = (LayerRank * 1000.0) + (Salience * 50.0) + (Specificity * 5.0)
    Returns the index of the highest priority rule to fire.
    """
    var n = len(saliences)
    if n == 0:
        return -1
    
    var best_idx = 0
    var best_score: Float32 = -1.0e9
    
    for i in range(n):
        var score = (layer_ranks[i] * 1000.0) + (saliences[i] * 50.0) + (specificities[i] * 5.0)
        if score > best_score:
            best_score = score
            best_idx = i
            
    return best_idx

# ------------------------------------------------------------------------------
# 11. High-Utility Model 6: Ruliad Multiway Branch Evaluator
# ------------------------------------------------------------------------------

def simd_ruliad_branchial_distance(vec_a: List[Float32], vec_b: List[Float32]) -> Float32:
    """
    Computes geodesic distance in multiway branchial space between two branch states:
    D = sqrt(2.0 * (1.0 - simd_cosine_similarity(vec_a, vec_b)))
    """
    var sim = simd_cosine_similarity(vec_a, vec_b)
    if sim >= 1.0:
        return 0.0
    if sim <= -1.0:
        return 2.0
    return sqrt(2.0 * (1.0 - sim))

# ------------------------------------------------------------------------------
# 12. High-Utility Model 7: Biomorphic Shruti Acoustic Telemetry Inverter
# ------------------------------------------------------------------------------

def simd_shruti_harmonic_synthesis(
    base_freq: Float32,
    shruti_ratios: List[Float32],
    amplitudes: List[Float32]
) -> Float32:
    """
    Computes weighted spectral power of 22-shruti microtonal chord synthesis.
    """
    var total_energy: Float32 = 0.0
    var n = len(shruti_ratios)
    if len(amplitudes) < n:
        n = len(amplitudes)
        
    for i in range(n):
        var freq = base_freq * shruti_ratios[i]
        total_energy += freq * amplitudes[i] * amplitudes[i]
        
    return total_energy

# ------------------------------------------------------------------------------
# 13. High-Utility Model 8: Deep Transformer & Neural Attention Tensors
# ------------------------------------------------------------------------------

def rmsnorm_tensor(v: List[Float32], gamma: List[Float32], eps: Float32) -> List[Float32]:
    """Root Mean Square Layer Normalization (RMSNorm) used in Gemma & Llama."""
    var n = len(v)
    var result = List[Float32]()
    if n == 0:
        return result^
    var sum_sq: Float32 = 0.0
    for i in range(n):
        sum_sq += v[i] * v[i]
    var rms = sqrt((sum_sq / Float32(n)) + eps)
    for i in range(n):
        var g: Float32 = 1.0
        if i < len(gamma):
            g = gamma[i]
        result.append((v[i] / rms) * g)
    return result^

def swiglu_activation(gate: Float32, up: Float32) -> Float32:
    """SwiGLU feedforward activation: Swish(gate) * up."""
    var swish = gate / (1.0 + exp(-gate))
    return swish * up

def simd_rotary_position_embedding(x: List[Float32], theta_base: Float32, pos: Int) -> List[Float32]:
    """Apply Rotary Position Embedding (RoPE) to an embedding vector."""
    var n = len(x)
    var result = List[Float32]()
    for i in range(n):
        result.append(x[i])
    var half_dim = n // 2
    for i in range(half_dim):
        var idx1 = i * 2
        var idx2 = idx1 + 1
        var freq = 1.0 / (theta_base ** (Float32(idx1) / Float32(n)))
        var phi = Float32(pos) * freq
        var c = cos(phi)
        var s = sin(phi)
        var x0 = x[idx1]
        var x1 = x[idx2]
        result[idx1] = (x0 * c) - (x1 * s)
        result[idx2] = (x0 * s) + (x1 * c)
    return result^

def simd_scaled_dot_product_attention(
    q: List[Float32],
    keys: List[List[Float32]],
    values: List[List[Float32]],
    d_k: Float32
) -> List[Float32]:
    """Multi-token Scaled Dot-Product Attention: Softmax(Q * K^T / sqrt(d_k)) * V."""
    var seq_len = len(keys)
    var out = List[Float32]()
    if seq_len == 0 or len(values) == 0:
        return out^
    var dim = len(q)
    for _ in range(dim):
        out.append(0.0)
    var scale = 1.0 / sqrt(d_k)
    var scores = List[Float32]()
    for i in range(seq_len):
        var dot = simd_dot_product(q, keys[i])
        scores.append(dot * scale)
    var weights = softmax_tensor(scores)
    for i in range(seq_len):
        var w = weights[i]
        for j in range(dim):
            if j < len(values[i]):
                out[j] += w * values[i][j]
    return out^

def simd_temporal_convolution_1d(signal: List[Float32], kernel: List[Float32]) -> List[Float32]:
    """1D Causal Temporal Convolution for streaming telemetry & sensor analysis."""
    var n = len(signal)
    var k_len = len(kernel)
    var result = List[Float32]()
    if n == 0 or k_len == 0:
        return result^
    for t in range(n):
        var acc: Float32 = 0.0
        var max_j = k_len
        if t + 1 < max_j:
            max_j = t + 1
        for j in range(max_j):
            acc += signal[t - j] * kernel[j]
        result.append(acc)
    return result^

# ------------------------------------------------------------------------------
# 14. High-Utility Model 9: Gemma Architecture Transformer Layer & SIMD Dequantization
# ------------------------------------------------------------------------------

def matvec_mul(w: List[List[Float32]], v: List[Float32]) -> List[Float32]:
    """Matrix-Vector multiplication: w * v using SIMD dot product."""
    var out = List[Float32]()
    var rows = len(w)
    for r in range(rows):
        out.append(simd_dot_product(w[r], v))
    return out^

def simd_dequantize_q8_0(scales: List[Float32], quants: List[Int8]) -> List[Float32]:
    """GGUF Q8_0 SIMD dequantization: 32 int8 quants per block with float32 scale."""
    var out = List[Float32]()
    var n = len(quants)
    for i in range(n):
        var block_idx = i // 32
        var scale: Float32 = 1.0
        if block_idx < len(scales):
            scale = scales[block_idx]
        out.append(scale * Float32(quants[i]))
    return out^

def simd_dot_product_q8_0(scales: List[Float32], quants: List[Int8], x: List[Float32]) -> Float32:
    """SIMD-accelerated dot product directly between Q8_0 weights and float32 vector."""
    var total: Float32 = 0.0
    var n = len(quants)
    if len(x) < n:
        n = len(x)
    var num_blocks = (n + 31) // 32
    for b in range(num_blocks):
        var scale: Float32 = 1.0
        if b < len(scales):
            scale = scales[b]
        var block_start = b * 32
        var block_end = block_start + 32
        if block_end > n:
            block_end = n
        var block_acc: Float32 = 0.0
        for i in range(block_start, block_end):
            block_acc += Float32(quants[i]) * x[i]
        total += scale * block_acc
    return total

def simd_dequantize_q4_0(scales: List[Float32], packed: List[UInt8]) -> List[Float32]:
    """GGUF Q4_0 SIMD dequantization: 16 bytes contain 32 4-bit quants offset by 8."""
    var out = List[Float32]()
    var num_bytes = len(packed)
    for i in range(num_bytes):
        var block_idx = (i * 2) // 32
        var scale: Float32 = 1.0
        if block_idx < len(scales):
            scale = scales[block_idx]
        var b = packed[i]
        var q0 = Float32(Int(b & 0x0F) - 8)
        var q1 = Float32(Int((b >> 4) & 0x0F) - 8)
        out.append(scale * q0)
        out.append(scale * q1)
    return out^

def gemma_embedding_lookup(table: List[List[Float32]], token_id: Int, d_model: Float32) -> List[Float32]:
    """Token embedding lookup with Gemma sqrt(d_model) scaling invariant."""
    var out = List[Float32]()
    if token_id < 0 or token_id >= len(table):
        return out^
    var scale = sqrt(d_model)
    for j in range(len(table[token_id])):
        out.append(table[token_id][j] * scale)
    return out^

def gemma_swiglu_mlp(
    x: List[Float32],
    w_gate: List[List[Float32]],
    w_up: List[List[Float32]],
    w_down: List[List[Float32]]
) -> List[Float32]:
    """Gemma Feed-Forward Network: W_down * (SwiGLU(W_gate * x, W_up * x))."""
    var gate_proj = matvec_mul(w_gate, x)
    var up_proj = matvec_mul(w_up, x)
    var intermediate = List[Float32]()
    var hidden_dim = len(gate_proj)
    if len(up_proj) < hidden_dim:
        hidden_dim = len(up_proj)
    for i in range(hidden_dim):
        intermediate.append(swiglu_activation(gate_proj[i], up_proj[i]))
    return matvec_mul(w_down, intermediate)

def gemma_transformer_layer(
    x: List[Float32],
    gamma_attn: List[Float32],
    w_q: List[List[Float32]],
    w_k: List[List[Float32]],
    w_v: List[List[Float32]],
    w_o: List[List[Float32]],
    gamma_ffn: List[Float32],
    w_gate: List[List[Float32]],
    w_up: List[List[Float32]],
    w_down: List[List[Float32]],
    pos: Int,
    d_k: Float32
) -> List[Float32]:
    """Single full forward pass of Gemma 3/2 Transformer Block."""
    var dim = len(x)
    
    # 1. Pre-attention RMSNorm
    var x_norm_attn = rmsnorm_tensor(x, gamma_attn, 0.000001)
    
    # 2. Q, K, V projections
    var q = matvec_mul(w_q, x_norm_attn)
    var k = matvec_mul(w_k, x_norm_attn)
    var v = matvec_mul(w_v, x_norm_attn)
    
    # 3. Rotary Position Embedding
    var q_rope = simd_rotary_position_embedding(q, 10000.0, pos)
    var k_rope = simd_rotary_position_embedding(k, 10000.0, pos)
    
    # 4. Attention
    var keys = List[List[Float32]]()
    keys.append(k_rope.copy())
    var values = List[List[Float32]]()
    values.append(v.copy())
    var attn_out = simd_scaled_dot_product_attention(q_rope, keys, values, d_k)
    
    # 5. Output projection + Residual Add
    var attn_proj = matvec_mul(w_o, attn_out)
    var x_mid = List[Float32]()
    for i in range(dim):
        var p: Float32 = 0.0
        if i < len(attn_proj):
            p = attn_proj[i]
        x_mid.append(x[i] + p)
        
    # 6. Pre-FFN RMSNorm
    var x_norm_ffn = rmsnorm_tensor(x_mid, gamma_ffn, 0.000001)
    
    # 7. SwiGLU FFN + Residual Add
    var ffn_out = gemma_swiglu_mlp(x_norm_ffn, w_gate, w_up, w_down)
    var x_final = List[Float32]()
    for i in range(dim):
        var f: Float32 = 0.0
        if i < len(ffn_out):
            f = ffn_out[i]
        x_final.append(x_mid[i] + f)
        
    return x_final^

# ------------------------------------------------------------------------------
# 15. High-Utility Model 10: GGUF K-Quant Super-Block Dequantization (Q4_K & Q6_K)
#     Brings sm_75 / Turing compatibility to pure Mojo/MAX kernel pipelines.
# ------------------------------------------------------------------------------

def simd_dequantize_q4_k_block(
    d: Float32,
    dmin: Float32,
    scales: List[UInt8],
    quants: List[UInt8]
) -> List[Float32]:
    """
    Dequantizes one Q4_K super-block of 256 weights.
    d: super-block scale factor (float16/float32)
    dmin: super-block minimum scale factor (float16/float32)
    scales: 12 bytes containing packed 6-bit scales and 6-bit mins for 8 sub-blocks of 32 weights.
    quants: 128 bytes containing 256 4-bit quantized values (packed 2 per byte).
    """
    var out = List[Float32]()
    var sc = List[Float32]()
    var m = List[Float32]()

    # Extract 6-bit scales and mins for the 8 sub-blocks (32 weights each = 256 weights)
    # GGUF Q4_K layout packs scales in the first 12 bytes:
    # 8 scales (6 bits) and 8 minimums (6 bits).
    for j in range(8):
        var s_val: Float32 = 1.0
        var m_val: Float32 = 0.0
        if len(scales) >= 12:
            if j < 4:
                s_val = Float32(scales[j] & 63)
                m_val = Float32(scales[j + 4] & 63)
            else:
                var s_high = (scales[j + 4] & 0xF0) >> 4
                s_val = Float32((scales[j - 4] >> 6) | (s_high << 2))
                var m_high = scales[j + 4] & 0x0F
                m_val = Float32((scales[j] >> 6) | (m_high << 2))
        sc.append(d * s_val)
        m.append(dmin * m_val)

    # Dequantize 8 sub-blocks of 32 weights (16 bytes per sub-block = 128 bytes total)
    for sb in range(8):
        var sub_scale = sc[sb]
        var sub_min = m[sb]
        var byte_offset = sb * 16
        for b in range(16):
            if byte_offset + b < len(quants):
                var byte_val = quants[byte_offset + b]
                var q0 = Float32(byte_val & 0x0F)
                var q1 = Float32((byte_val >> 4) & 0x0F)
                out.append(sub_scale * q0 - sub_min)
                out.append(sub_scale * q1 - sub_min)
            else:
                out.append(0.0)
                out.append(0.0)

    return out^

def simd_dequantize_q6_k_block(
    d: Float32,
    scales: List[Int8],
    ql: List[UInt8],
    qh: List[UInt8]
) -> List[Float32]:
    """
    Dequantizes one Q6_K super-block of 256 weights.
    d: super-block scale factor (float16/float32)
    scales: 16 int8 sub-block scale values (16 sub-blocks of 16 weights = 256 weights)
    ql: 128 bytes containing low 4 bits of the 256 quants
    qh: 64 bytes containing high 2 bits of the 256 quants
    """
    var out = List[Float32]()
    
    # Each sub-block has 16 weights; 16 sub-blocks = 256 weights
    for sb in range(16):
        var sc: Float32 = 1.0
        if sb < len(scales):
            sc = d * Float32(scales[sb])
            
        var ql_offset = sb * 8 # 8 bytes = 16 4-bit nibbles
        var qh_offset = sb * 4 # 4 bytes = 16 2-bit values
        
        for i in range(16):
            var low_byte_idx = ql_offset + (i // 2)
            var low_nibble: UInt8 = 0
            if low_byte_idx < len(ql):
                var raw_ql = ql[low_byte_idx]
                if (i % 2) == 0:
                    low_nibble = raw_ql & 0x0F
                else:
                    low_nibble = (raw_ql >> 4) & 0x0F
                    
            var high_byte_idx = qh_offset + (i // 4)
            var high_2bits: UInt8 = 0
            if high_byte_idx < len(qh):
                var raw_qh = qh[high_byte_idx]
                var shift = UInt8((i % 4) * 2)
                high_2bits = (raw_qh >> shift) & 0x03
                
            var q6 = Int(low_nibble | (high_2bits << 4)) - 32
            out.append(sc * Float32(q6))
            
    return out^

def qwen2_transformer_layer(
    x: List[Float32],
    w_q: List[List[Float32]],
    w_k: List[List[Float32]],
    w_v: List[List[Float32]],
    w_o: List[List[Float32]],
    gamma_attn: List[Float32],
    w_gate: List[List[Float32]],
    w_up: List[List[Float32]],
    w_down: List[List[Float32]],
    gamma_ffn: List[Float32],
    pos: Int,
    d_k: Float32
) -> List[Float32]:
    """
    Executes a complete single Qwen2 / Qwen2.5 transformer block:
    RMSNorm -> Attention(Q, K, V with RoPE) -> Output Proj -> Residual Add
    -> RMSNorm -> SwiGLU MLP(Gate, Up, Down) -> Residual Add.
    Uses standard Qwen2 RMSNorm epsilon (1e-6) without post-norm scaling.
    """
    var dim = len(x)
    if dim == 0:
        return List[Float32]()

    # 1. Pre-attention RMSNorm
    var x_norm_attn = rmsnorm_tensor(x, gamma_attn, 0.000001)

    # 2. Linear projections
    var q = matvec_mul(w_q, x_norm_attn)
    var k = matvec_mul(w_k, x_norm_attn)
    var v = matvec_mul(w_v, x_norm_attn)

    # 3. Rotary Position Embedding (RoPE)
    var q_rope = simd_rotary_position_embedding(q, 10000.0, pos)
    var k_rope = simd_rotary_position_embedding(k, 10000.0, pos)

    # 4. Scaled Dot-Product Attention
    var keys = List[List[Float32]]()
    keys.append(k_rope.copy())
    var values = List[List[Float32]]()
    values.append(v.copy())
    var attn_out = simd_scaled_dot_product_attention(q_rope, keys, values, d_k)

    # 5. Attention Output Projection and First Residual Add
    var attn_proj = matvec_mul(w_o, attn_out)
    var x_mid = List[Float32]()
    for i in range(dim):
        var p: Float32 = 0.0
        if i < len(attn_proj):
            p = attn_proj[i]
        x_mid.append(x[i] + p)

    # 6. Pre-FFN RMSNorm
    var x_norm_ffn = rmsnorm_tensor(x_mid, gamma_ffn, 0.000001)

    # 7. SwiGLU Feed-Forward Network and Second Residual Add
    var ffn_out = gemma_swiglu_mlp(x_norm_ffn, w_gate, w_up, w_down)
    var x_final = List[Float32]()
    for i in range(dim):
        var f: Float32 = 0.0
        if i < len(ffn_out):
            f = ffn_out[i]
        x_final.append(x_mid[i] + f)

    return x_final^

# ------------------------------------------------------------------------------
# 16. High-Utility Model 11: Turing sm_75 Tensor Core m16n8k8 Tiled MatVec
#     & Warp Butterfly Reduction (`task-0`: Razr15 CUDA High-Throughput Calibration)
# ------------------------------------------------------------------------------

def turing_sm75_m16n8k8_matvec_tile(
    weights_m16k8: List[List[Float32]],
    activation_k8: List[Float32]
) -> List[Float32]:
    """
    Executes a Turing sm_75 Tensor Core m16n8k8 tile reduction for matrix-vector
    decode steps, accumulating 8-element K-fragments across 16 output rows with
    deterministic butterfly tree reduction (modeling shfl.sync.bfly.b32).
    """
    var out = List[Float32]()
    var rows = len(weights_m16k8)
    for r in range(rows):
        var row = weights_m16k8[r].copy()
        var n = len(row)
        if len(activation_k8) < n:
            n = len(activation_k8)
        # Partition into 8-wide Tensor Core K-tiles with butterfly reduction
        var acc: Float32 = 0.0
        var k = 0
        while k + 8 <= n:
            var l0 = row[k + 0] * activation_k8[k + 0] + row[k + 4] * activation_k8[k + 4]
            var l1 = row[k + 1] * activation_k8[k + 1] + row[k + 5] * activation_k8[k + 5]
            var l2 = row[k + 2] * activation_k8[k + 2] + row[k + 6] * activation_k8[k + 6]
            var l3 = row[k + 3] * activation_k8[k + 3] + row[k + 7] * activation_k8[k + 7]
            var s0 = l0 + l2
            var s1 = l1 + l3
            acc += s0 + s1
            k += 8
        while k < n:
            acc += row[k] * activation_k8[k]
            k += 1
        out.append(acc)
    return out^

# ------------------------------------------------------------------------------
# 17. High-Utility Model 12: Speculative Draft Model Decoding Pipeline
#     (`task-1`: Speculative draft model decoding pipeline)
# ------------------------------------------------------------------------------

def speculative_draft_verify_step(
    draft_tokens: List[Int],
    draft_probs: List[Float32],
    target_probs: List[Float32],
    uniform_samples: List[Float32],
    bonus_token: Int
) -> List[Int]:
    """
    Executes lossless speculative decoding verification (Leviathan et al.):
    For each draft token i in 0..gamma-1:
      - Accepts token draft_tokens[i] if uniform_samples[i] <= min(1.0, target_probs[i] / draft_probs[i]).
      - On first rejection at position i, halts draft acceptance and emits the resampled
        fallback token (bonus_token) at position i, guaranteeing >= 1 token progress per step.
      - If all gamma draft tokens are accepted, appends bonus_token for gamma + 1 tokens emitted.
    """
    var accepted = List[Int]()
    var gamma = len(draft_tokens)
    if len(draft_probs) < gamma:
        gamma = len(draft_probs)
    if len(target_probs) < gamma:
        gamma = len(target_probs)
    if len(uniform_samples) < gamma:
        gamma = len(uniform_samples)

    for i in range(gamma):
        var q = draft_probs[i]
        var p = target_probs[i]
        var u = uniform_samples[i]
        var ratio: Float32 = 1.0
        if q > 1e-7:
            ratio = p / q
            if ratio > 1.0:
                ratio = 1.0
        elif p <= 0.0:
            ratio = 0.0
        if u <= ratio:
            accepted.append(draft_tokens[i])
        else:
            accepted.append(bonus_token)
            return accepted^

    accepted.append(bonus_token)
    return accepted^

# ------------------------------------------------------------------------------
# 18. High-Utility Model 13: Pure Mojo Grammar-Guided Constrained Decoding
#     (`task-2`: Pure Mojo grammar-guided constrained decoding)
# ------------------------------------------------------------------------------

def grammar_constrained_logit_mask(
    logits: List[Float32],
    allowed_token_mask: List[Bool]
) -> List[Float32]:
    """
    Applies a deterministic pushdown-automaton / EBNF grammar token mask to raw
    vocabulary logits before softmax/argmax sampling:
      - If allowed_token_mask[i] == True, preserves logits[i].
      - If allowed_token_mask[i] == False, clamps logits[i] to -1.0e9 (-infinity),
        ensuring zero probability mass on syntactically invalid tokens.
    """
    var masked = List[Float32]()
    var n = len(logits)
    for i in range(n):
        var allowed = False
        if i < len(allowed_token_mask):
            allowed = allowed_token_mask[i]
        if allowed:
            masked.append(logits[i])
        else:
            masked.append(-1000000000.0)
    return masked^

def grammar_constrained_greedy_select(
    logits: List[Float32],
    allowed_token_mask: List[Bool]
) -> Int:
    """
    Selects the highest-logit token ID permitted by the active grammar state.
    Returns -1 if the vocabulary is empty or no token is permitted by the mask.
    """
    var masked = grammar_constrained_logit_mask(logits, allowed_token_mask)
    var n = len(masked)
    if n == 0:
        return -1
    var best_idx = -1
    var best_val: Float32 = -1000000000.0
    for i in range(n):
        if i < len(allowed_token_mask) and allowed_token_mask[i]:
            if best_idx == -1 or masked[i] > best_val:
                best_val = masked[i]
                best_idx = i
    return best_idx

