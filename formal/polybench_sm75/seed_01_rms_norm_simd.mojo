# formal/polybench_sm75/seed_01_rms_norm_simd.mojo
# PolyBench-SM75 Language 1 (Mojo 1.0+): Vectorized RMSNorm SIMD Kernel & Tail Loop
# Verifies unified `def` syntax, `mut` List/Span ownership, `SIMD[DType.float32, 4]`
# horizontal `.reduce_add()`, and tail boundary handling without pre-1.0 `fn`/`let`.

from std.math import sqrt


def rms_norm_simd_4(
    input_vals: List[Float32],
    mut output_vals: List[Float32],
    eps: Float32,
) -> Float32:
    var size = len(input_vals)
    var sum_sq = SIMD[DType.float32, 4](0.0)
    var vec_end = (size // 4) * 4
    var i = 0
    while i < vec_end:
        var chunk = SIMD[DType.float32, 4](
            input_vals[i],
            input_vals[i + 1],
            input_vals[i + 2],
            input_vals[i + 3],
        )
        sum_sq += chunk * chunk
        i += 4
    var tail_sq: Float32 = 0.0
    for t in range(vec_end, size):
        tail_sq += input_vals[t] * input_vals[t]
    var mean_sq = (sum_sq.reduce_add() + tail_sq) / Float32(size)
    var inv_rms = Float32(1.0) / sqrt(mean_sq + eps)
    for j in range(size):
        output_vals[j] = input_vals[j] * inv_rms
    return inv_rms


def compute_sm75_mbu_pct(
    model_weight_mib: Int,
    itl_ms: Int,
    hw_bw_gbs: Int = 448,
) -> Int:
    """Computes effective SM75 GDDR6 Memory Bandwidth Utilization % (integer percentage)."""
    if itl_ms <= 0 or hw_bw_gbs <= 0:
        return 0
    # tokens/sec = 1000 / itl_ms; weight_gb = model_weight_mib / 1024
    # achieved_gbs * 100 = (1000 * model_weight_mib * 100) / (itl_ms * 1024 * hw_bw_gbs)
    var num = 1000 * model_weight_mib * 100
    var den = itl_ms * 1024 * hw_bw_gbs
    return num // den


def main():
    var inp = List[Float32]()
    var out = List[Float32]()
    for k in range(10):
        inp.append(Float32(k + 1))
        out.append(Float32(0.0))
    var inv_rms = rms_norm_simd_4(inp, out, Float32(1e-5))
    var mbu = compute_sm75_mbu_pct(4460, 12, 360)
    if inv_rms > Float32(0.15) and inv_rms < Float32(0.17) and out[9] > Float32(1.5) and mbu >= 75:
        print("POLYBENCH_MOJO_PASS:inv_rms=" + String(inv_rms) + ":mbu_pct=" + String(mbu))
    else:
        print("POLYBENCH_MOJO_FAIL")
