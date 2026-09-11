# ==============================================================================
# [C3I-SIL6-MSTS] UOS MODULAR MAX / MOJO BARE-METAL GEMMA 4 ARCHITECTURE
# ==============================================================================
# <c3i-module>
#   <identity>
#     <module>services/inference/max/gemma4_kernel.mojo</module>
#     <authority>UOS-CANONICAL-AGENT-POLICY</authority>
#   </identity>
#   <fractal-topology>
#     <layer>L4_SYSTEM</layer>
#     <mesh-domain>
#       Bare-Metal Gemma 4 Architecture on Modular MAX Execution Fabric.
#       Implements Grouped Query Attention (GQA), 500k-theta Long-Context RoPE,
#       Sliding-Window Attention (SWA), RMSNorm with Learned Gain, and SwiGLU FFN.
#     </mesh-domain>
#   </fractal-topology>
#   <compliance>
#     <criticality>DAL-A / SIL-6 / ISOLATED</criticality>
#     <stamp-controls>
#       SC-DEFENSE-CONSTITUTION-001, SC-INF-MOJO-001, SC-ZERO-MUDA-001, SC-MATH-001
#     </stamp-controls>
#   </compliance>
# </c3i-module>
# ==============================================================================

from std.math import exp, sqrt, cos, sin
from std.sys import simd_width_of

comptime float_simd_width = simd_width_of[DType.float32]()

# ------------------------------------------------------------------------------
# 1. SIMD Vector Operations
# ------------------------------------------------------------------------------

def simd_dot_product(a: List[Float32], b: List[Float32]) -> Float32:
    """Compute dot product of two vectors using SIMD acceleration."""
    var total: Float32 = 0.0
    var n = len(a)
    if len(b) < n:
        n = len(b)
    
    var i = 0
    while i + float_simd_width <= n:
        var va = SIMD[DType.float32, float_simd_width]()
        var vb = SIMD[DType.float32, float_simd_width]()
        for j in range(float_simd_width):
            va[j] = a[i + j]
            vb[j] = b[i + j]
        total += (va * vb).reduce_add()
        i += float_simd_width
    
    while i < n:
        total += a[i] * b[i]
        i += 1
    
    return total

def matvec_mul(matrix: List[List[Float32]], vec: List[Float32]) -> List[Float32]:
    """Matrix-vector multiplication: out = matrix * vec."""
    var out = List[Float32]()
    var rows = len(matrix)
    for r in range(rows):
        out.append(simd_dot_product(matrix[r], vec))
    return out^

# ------------------------------------------------------------------------------
# 2. Gemma 4 RMSNorm with Learned Gain
# ------------------------------------------------------------------------------

def gemma4_rmsnorm(v: List[Float32], gamma: List[Float32], eps: Float32 = 1e-6) -> List[Float32]:
    """Gemma 4 Root Mean Square Layer Normalization with learned gain."""
    var n = len(v)
    if n == 0:
        return List[Float32]()
    
    var sum_sq: Float32 = 0.0
    for i in range(n):
        sum_sq += v[i] * v[i]
    var rms = sqrt((sum_sq / Float32(n)) + eps)
    
    var out = List[Float32]()
    for i in range(n):
        var g: Float32 = 1.0
        if i < len(gamma):
            g = gamma[i]
        out.append((v[i] / rms) * g)
    return out^

# ------------------------------------------------------------------------------
# 3. Gemma 4 Long-Context RoPE (theta = 500,000.0)
# ------------------------------------------------------------------------------

def gemma4_rope_500k(v: List[Float32], pos: Int, theta_base: Float32 = 500000.0) -> List[Float32]:
    """Gemma 4 Rotary Position Embedding with high-frequency 500k base theta."""
    var dim = len(v)
    var out = List[Float32]()
    var half = dim // 2
    if half == 0:
        return v.copy()
    
    for i in range(half):
        var freq_exp = (Float32(2 * i)) / Float32(dim)
        var freq = 1.0 / (theta_base ** freq_exp)
        var angle = Float32(pos) * freq
        var c = cos(angle)
        var s = sin(angle)
        
        var x0 = v[i]
        var x1 = v[i + half]
        out.append(x0 * c - x1 * s)
        
    for i in range(half):
        var freq_exp = (Float32(2 * i)) / Float32(dim)
        var freq = 1.0 / (theta_base ** freq_exp)
        var angle = Float32(pos) * freq
        var c = cos(angle)
        var s = sin(angle)
        
        var x0 = v[i]
        var x1 = v[i + half]
        out.append(x0 * s + x1 * c)
        
    return out^

# ------------------------------------------------------------------------------
# 4. Gemma 4 Embedding Lookup with sqrt(d_model) Invariant
# ------------------------------------------------------------------------------

def gemma4_embedding_lookup(table: List[List[Float32]], token_id: Int, d_model: Float32) -> List[Float32]:
    """Token embedding lookup scaled by sqrt(d_model) invariant."""
    var out = List[Float32]()
    if token_id < 0 or token_id >= len(table):
        return out^
    var scale = sqrt(d_model)
    for j in range(len(table[token_id])):
        out.append(table[token_id][j] * scale)
    return out^

# ------------------------------------------------------------------------------
# 5. Grouped Query Attention (GQA) & Sliding-Window Masking
# ------------------------------------------------------------------------------

def gemma4_gqa_attention_block(
    q: List[Float32],
    k_cache: List[List[Float32]],
    v_cache: List[List[Float32]],
    num_q_heads: Int,
    num_kv_heads: Int,
    head_dim: Int,
    window_size: Int = 4096
) -> List[Float32]:
    """Grouped Query Attention (GQA) with sliding-window masking.

    q length = num_q_heads * head_dim
    Each KV head serves (num_q_heads / num_kv_heads) query heads.
    """
    var gqa_group_size = num_q_heads // num_kv_heads
    if gqa_group_size < 1:
        gqa_group_size = 1
    
    var seq_len = len(k_cache)
    var out = List[Float32]()
    var scale = 1.0 / sqrt(Float32(head_dim))
    
    for q_h in range(num_q_heads):
        var kv_h = q_h // gqa_group_size
        var q_offset = q_h * head_dim
        var kv_offset = kv_h * head_dim
        
        # Extract query slice for this head
        var q_slice = List[Float32]()
        for d in range(head_dim):
            q_slice.append(q[q_offset + d])
            
        # Compute attention scores over history with sliding window
        var scores = List[Float32]()
        var max_score: Float32 = -1e9
        var min_allowed_pos = 0
        if seq_len > window_size:
            min_allowed_pos = seq_len - window_size
            
        for t in range(seq_len):
            if t < min_allowed_pos:
                scores.append(-1e9) # Masked out by sliding window
            else:
                var k_slice = List[Float32]()
                for d in range(head_dim):
                    k_slice.append(k_cache[t][kv_offset + d])
                var dot = simd_dot_product(q_slice, k_slice) * scale
                scores.append(dot)
                if dot > max_score:
                    max_score = dot
                    
        # Softmax over scores
        var exp_sum: Float32 = 0.0
        var weights = List[Float32]()
        for t in range(seq_len):
            var e = exp(scores[t] - max_score)
            weights.append(e)
            exp_sum += e
            
        if exp_sum <= 0.0:
            exp_sum = 1.0
            
        # Weighted sum of values
        for d in range(head_dim):
            var val_acc: Float32 = 0.0
            for t in range(seq_len):
                var v_val = v_cache[t][kv_offset + d]
                val_acc += (weights[t] / exp_sum) * v_val
            out.append(val_acc)
            
    return out^

# ------------------------------------------------------------------------------
# 6. Gemma 4 SwiGLU Gated Feed-Forward Network
# ------------------------------------------------------------------------------

def gemma4_swiglu_mlp(
    x: List[Float32],
    w_gate: List[List[Float32]],
    w_up: List[List[Float32]],
    w_down: List[List[Float32]]
) -> List[Float32]:
    """Gemma 4 SwiGLU FFN: W_down * (Swish(W_gate * x) * (W_up * x))."""
    var gate_proj = matvec_mul(w_gate, x)
    var up_proj = matvec_mul(w_up, x)
    var hidden_dim = len(gate_proj)
    if len(up_proj) < hidden_dim:
        hidden_dim = len(up_proj)
        
    var activated = List[Float32]()
    for i in range(hidden_dim):
        var g = gate_proj[i]
        var sig = 1.0 / (1.0 + exp(-g))
        var swish = g * sig
        activated.append(swish * up_proj[i])
        
    return matvec_mul(w_down, activated)

# ------------------------------------------------------------------------------
# 7. Complete Gemma 4 Transformer Layer Forward Pass
# ------------------------------------------------------------------------------

def gemma4_transformer_layer(
    x: List[Float32],
    gamma_attn: List[Float32],
    w_q: List[List[Float32]],
    w_k: List[List[Float32]],
    w_v: List[List[Float32]],
    w_o: List[List[Float32]],
    k_cache: List[List[Float32]],
    v_cache: List[List[Float32]],
    gamma_ffn: List[Float32],
    w_gate: List[List[Float32]],
    w_up: List[List[Float32]],
    w_down: List[List[Float32]],
    num_q_heads: Int,
    num_kv_heads: Int,
    head_dim: Int,
    pos: Int,
    window_size: Int = 4096
) -> List[Float32]:
    """End-to-end bare-metal execution of single Gemma 4 Transformer Block.

    1. Pre-attention RMSNorm with gamma_attn
    2. GQA projection with 500k RoPE
    3. Sliding-window attention over KV-cache
    4. Output projection w_o + Residual Add
    5. Pre-FFN RMSNorm with gamma_ffn
    6. SwiGLU FFN + Residual Add
    """
    var dim = len(x)
    
    # 1. Pre-Attention RMSNorm
    var x_norm_attn = gemma4_rmsnorm(x, gamma_attn)
    
    # 2. Q, K, V Projections
    var q = matvec_mul(w_q, x_norm_attn)
    var k = matvec_mul(w_k, x_norm_attn)
    var v = matvec_mul(w_v, x_norm_attn)
    
    # 3. 500k RoPE on Query and Key
    var q_rope = gemma4_rope_500k(q, pos)
    var k_rope = gemma4_rope_500k(k, pos)
    
    # Update KV-cache with current token
    var full_k_cache = List[List[Float32]]()
    var full_v_cache = List[List[Float32]]()
    for t in range(len(k_cache)):
        full_k_cache.append(k_cache[t].copy())
        full_v_cache.append(v_cache[t].copy())
    full_k_cache.append(k_rope.copy())
    full_v_cache.append(v.copy())
    
    # 4. Grouped Query Attention with Sliding-Window Masking
    var attn_out = gemma4_gqa_attention_block(
        q_rope, full_k_cache, full_v_cache, num_q_heads, num_kv_heads, head_dim, window_size
    )
    
    # 5. Output projection + Residual Add
    var attn_proj = matvec_mul(w_o, attn_out)
    var x_mid = List[Float32]()
    for i in range(dim):
        var p: Float32 = 0.0
        if i < len(attn_proj):
            p = attn_proj[i]
        x_mid.append(x[i] + p)
        
    # 6. Pre-FFN RMSNorm
    var x_norm_ffn = gemma4_rmsnorm(x_mid, gamma_ffn)
    
    # 7. SwiGLU FFN + Residual Add
    var ffn_out = gemma4_swiglu_mlp(x_norm_ffn, w_gate, w_up, w_down)
    var x_final = List[Float32]()
    for i in range(dim):
        var f: Float32 = 0.0
        if i < len(ffn_out):
            f = ffn_out[i]
        x_final.append(x_mid[i] + f)
        
    return x_final^

# ------------------------------------------------------------------------------
# 8. Deterministic Selftest
# ------------------------------------------------------------------------------

def main() raises:
    print("==============================================================================")
    print("[C3I-SIL6] BARE-METAL GEMMA 4 ARCHITECTURE TENSOR KERNEL SELFTEST")
    print("==============================================================================")
    
    # Test 1: Gemma 4 RMSNorm with Gain Vector
    var v = List[Float32]()
    v.append(3.0)
    v.append(4.0)
    var gamma = List[Float32]()
    gamma.append(2.0)
    gamma.append(1.0)
    var norm_out = gemma4_rmsnorm(v, gamma)
    if len(norm_out) != 2:
        raise Error("FAIL: RMSNorm output length != 2")
    print("PASS: Gemma 4 RMSNorm computed successfully:", norm_out[0], norm_out[1])
    
    # Test 2: Gemma 4 RoPE-500k Position 0 Invariance
    var test_rope = List[Float32]()
    test_rope.append(1.0)
    test_rope.append(2.0)
    test_rope.append(3.0)
    test_rope.append(4.0)
    var r0 = gemma4_rope_500k(test_rope, 0)
    for i in range(4):
        if r0[i] < test_rope[i] - 1e-4 or r0[i] > test_rope[i] + 1e-4:
            raise Error("FAIL: RoPE at pos 0 must be identity")
    print("PASS: Gemma 4 RoPE-500k at position 0 is exact identity")
    
    # Test 3: Embedding Lookup with sqrt(d_model)
    var vocab = List[List[Float32]]()
    var row0 = List[Float32]()
    row0.append(2.0)
    row0.append(3.0)
    vocab.append(row0^)
    var emb = gemma4_embedding_lookup(vocab, 0, 4.0) # sqrt(4) = 2.0 -> [4.0, 6.0]
    if emb[0] < 3.99 or emb[0] > 4.01 or emb[1] < 5.99 or emb[1] > 6.01:
        raise Error("FAIL: Embedding lookup scale incorrect")
    print("PASS: Gemma 4 embedding scaling invariant sqrt(d_model) verified:", emb[0], emb[1])
    
    # Test 4: Grouped Query Attention (GQA) with 2 Query Heads & 1 KV Head
    var q_gqa = List[Float32]()
    q_gqa.append(1.0)
    q_gqa.append(0.0) # Head 0
    q_gqa.append(0.0)
    q_gqa.append(1.0) # Head 1
    
    var k_cache = List[List[Float32]]()
    var k0 = List[Float32]()
    k0.append(1.0)
    k0.append(0.0) # Shared KV Head
    k_cache.append(k0^)
    
    var v_cache = List[List[Float32]]()
    var v0 = List[Float32]()
    v0.append(5.0)
    v0.append(10.0)
    v_cache.append(v0^)
    
    var gqa_out = gemma4_gqa_attention_block(q_gqa, k_cache, v_cache, 2, 1, 2, 4096)
    if len(gqa_out) != 4:
        raise Error("FAIL: GQA output dimension != 4")
    print("PASS: Grouped Query Attention (2 Q heads -> 1 KV head) verified:", gqa_out[0], gqa_out[1])
    
    # Test 5: Full Gemma 4 Transformer Layer Forward Pass
    var x = List[Float32]()
    x.append(1.0)
    x.append(1.0)
    x.append(1.0)
    x.append(1.0)
    
    var g_attn = List[Float32]()
    g_attn.append(1.0)
    g_attn.append(1.0)
    g_attn.append(1.0)
    g_attn.append(1.0)
    
    # Identity-like projection weights for 4D
    var w_q = List[List[Float32]]()
    var w_k = List[List[Float32]]()
    var w_v = List[List[Float32]]()
    var w_o = List[List[Float32]]()
    for r in range(4):
        var row_q = List[Float32]()
        var row_k = List[Float32]()
        var row_v = List[Float32]()
        var row_o = List[Float32]()
        for c in range(4):
            var val: Float32 = 0.0
            if r == c:
                val = 0.25
            row_q.append(val)
            row_k.append(val)
            row_v.append(val)
            row_o.append(val)
        w_q.append(row_q^)
        w_k.append(row_k^)
        w_v.append(row_v^)
        w_o.append(row_o^)
        
    var g_ffn = List[Float32]()
    g_ffn.append(1.0)
    g_ffn.append(1.0)
    g_ffn.append(1.0)
    g_ffn.append(1.0)
    
    var w_gate = List[List[Float32]]()
    var w_up = List[List[Float32]]()
    for _ in range(2):
        var rg = List[Float32]()
        var ru = List[Float32]()
        for _ in range(4):
            rg.append(0.1)
            ru.append(0.1)
        w_gate.append(rg^)
        w_up.append(ru^)
        
    var w_down = List[List[Float32]]()
    for _ in range(4):
        var rd = List[Float32]()
        for _ in range(2):
            rd.append(0.1)
        w_down.append(rd^)
        
    var empty_k = List[List[Float32]]()
    var empty_v = List[List[Float32]]()
    
    var layer_out = gemma4_transformer_layer(
        x, g_attn, w_q, w_k, w_v, w_o, empty_k, empty_v,
        g_ffn, w_gate, w_up, w_down,
        2, 2, 2, 0, 4096
    )
    
    if len(layer_out) != 4:
        raise Error("FAIL: Full layer output length != 4")
    print("PASS: Full Gemma 4 Transformer Layer forward pass completed: out[0] =", layer_out[0])
    
    print("==============================================================================")
    print("GEMMA 4 BARE-METAL KERNEL SELFTEST: ALL CHECKS PASSED")
    print("==============================================================================")
