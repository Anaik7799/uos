#!/usr/bin/env python3
# ==============================================================================
# ETC-2 Remediation Acceptance Tests — Mojo SIMD Kernel Bridge
# ==============================================================================
# Parity oracle: native/nifs/mojo/test_uos_km_kernel.c (tolerance 1e-4).
# Every assertion here has a twin in that C oracle so the Python binding and the
# Erlang NIF binding cannot drift apart without one of them failing.
#
# Run: python3 services/inference/max/test_mojo_kernel_bridge.py
# Exit 0 = all pass. Any failure prints FAIL and exits 1.
# ==============================================================================

from __future__ import annotations

import os
import sys
import traceback

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import mojo_kernel_bridge as kb

TOL = 1e-4
_passed = 0
_failed = 0


def check(name: str, cond: bool, detail: str = "") -> None:
    global _passed, _failed
    if cond:
        _passed += 1
        print(f"  [PASS] {name}" + (f"  ({detail})" if detail else ""))
    else:
        _failed += 1
        print(f"  [FAIL] {name}  {detail}")


def near(a: float, b: float, tol: float = TOL) -> bool:
    return abs(a - b) <= tol


def main() -> int:
    print("=== ETC-2 Mojo SIMD Kernel Bridge Acceptance ===")

    st = kb.kernel_status()
    print(f"  kernel: {st['kernel_path']} abi={st['kernel_abi_version']}")
    check("kernel_available", st["kernel_status"] == "available", str(st["kernel_reason"] or ""))
    if st["kernel_status"] != "available":
        print("\nKernel unavailable — bridge correctly refuses to fake results.")
        return 1

    # 1. ABI parity with the C oracle's eq("abi_version", ..., 3)
    check("abi_version_is_3", kb.abi_version() == 3, f"got {kb.abi_version()}")

    # 2. cosine: identical vectors => 1.0
    check("cosine_identical", near(kb.cosine_similarity([1.0, 2.0, 3.0, 4.0], [1.0, 2.0, 3.0, 4.0]), 1.0))
    # 3. cosine: orthogonal => 0.0
    check("cosine_orthogonal", near(kb.cosine_similarity([1.0, 0.0], [0.0, 1.0]), 0.0))
    # 4. cosine: opposed => -1.0 (legal, must NOT be mistaken for a rejection)
    check("cosine_opposed", near(kb.cosine_similarity([1.0, 1.0], [-1.0, -1.0]), -1.0))
    # 5. cosine: zero vector => 0.0 (documented zero-norm case)
    check("cosine_zero_vector", near(kb.cosine_similarity([0.0, 0.0, 0.0], [1.0, 2.0, 3.0]), 0.0))
    # 6. cosine: non-multiple-of-SIMD-width length exercises the tail loop
    check("cosine_tail_lane", near(kb.cosine_similarity([2.0] * 13, [2.0] * 13), 1.0), "n=13")
    # 7. cosine: dimension mismatch is a contract violation, not a number
    try:
        kb.cosine_similarity([1.0, 2.0], [1.0])
        check("cosine_dim_mismatch_raises", False)
    except kb.KernelContractViolation:
        check("cosine_dim_mismatch_raises", True)
    # 8. cosine: empty vector is refused before reaching the kernel
    try:
        kb.cosine_similarity([], [])
        check("cosine_empty_raises", False)
    except kb.KernelContractViolation:
        check("cosine_empty_raises", True)

    # 9-10. conformance_score extremes (C oracle: all-conformant 1.0, none 0.0)
    check("conformance_all", near(kb.conformance_score([1.0] * 13, [2.0] * 13), 1.0))
    check("conformance_none", near(kb.conformance_score([0.0] * 13, [2.0] * 13), 0.0))
    # 11. conformance: mismatched lengths
    try:
        kb.conformance_score([1.0, 0.0], [1.0])
        check("conformance_dim_mismatch_raises", False)
    except kb.KernelContractViolation:
        check("conformance_dim_mismatch_raises", True)

    # 12-13. Shannon entropy: uniform 2-bin = 1.0 bit; single-bin = 0.0 bits
    check("entropy_uniform_2", near(kb.shannon_entropy_bits([0.5, 0.5]), 1.0))
    check("entropy_single", near(kb.shannon_entropy_bits([1.0]), 0.0))
    # 14. entropy via the count-normalising convenience wrapper
    check("entropy_normalized_counts", near(kb.normalized_entropy([1.0, 1.0]), 1.0))

    # 15-18. FMEA band ladder — mirrors tools/risk-prioritization RPN bands
    check("fmea_band_1024", kb.fmea_band(4, 5, 3) == 4, f"got {kb.fmea_band(4, 5, 3)}")
    check("fmea_band_768", kb.fmea_band(4, 4, 4) == 4, f"got {kb.fmea_band(4, 4, 4)}")
    check("fmea_band_432", kb.fmea_band(3, 3, 3) == 3, f"got {kb.fmea_band(3, 3, 3)}")
    check("fmea_band_108", kb.fmea_band(2, 2, 2) == 2, f"got {kb.fmea_band(2, 2, 2)}")
    check("fmea_band_48", kb.fmea_band(2, 1, 1) == 1, f"got {kb.fmea_band(2, 1, 1)}")
    # 19. RPN arithmetic guarded to 1..10 factors
    check("fmea_rpn_product", kb.fmea_rpn(4, 5, 3) == 60, f"got {kb.fmea_rpn(4, 5, 3)}")
    try:
        kb.fmea_rpn(11, 1, 1)
        check("fmea_rpn_out_of_range_raises", False)
    except kb.KernelContractViolation:
        check("fmea_rpn_out_of_range_raises", True)

    # 20. drift distance: sqrt(8) for (1,1) vs (3,3) — matches ctypes smoke probe
    check("drift_distance", near(kb.drift_distance([1.0, 1.0], [3.0, 3.0]), 2.828427, 1e-3))

    # 21. matrix column means: 3x4 row-major {1..12} => {(1+5+9)/3, (2+6+10)/3,
    # (3+7+11)/3, (4+8+12)/3} = {5, 6, 7, 8}. The common misreading of
    # {2.5, 6.5, 10.5, 14.5} is the ROW means of a 4x3 layout, not the column means.
    m = [[1.0, 2.0, 3.0, 4.0], [5.0, 6.0, 7.0, 8.0], [9.0, 10.0, 11.0, 12.0]]
    cm = kb.matrix_column_means(m)
    check(
        "matrix_column_means",
        len(cm) == 4 and all(near(g, w) for g, w in zip(cm, [5.0, 6.0, 7.0, 8.0])),
        str(cm),
    )
    # 21b. ragged matrices are refused, not silently truncated
    try:
        kb.matrix_column_means([[1.0, 2.0], [3.0]])
        check("matrix_ragged_raises", False)
    except kb.KernelContractViolation:
        check("matrix_ragged_raises", True)

    # 22-24. forecasting primitives are finite and slope sign-correct
    ramp = [1.0, 2.0, 3.0, 4.0, 5.0]
    check("ewma_finite", abs(kb.ewma(ramp, 0.5) - 4.0) < 1.0, f"got {kb.ewma(ramp, 0.5):.4f}")
    check("linear_slope_positive", kb.linear_slope(ramp) > 0.0, f"got {kb.linear_slope(ramp):.4f}")
    check(
        "trend_residual_small_on_linear",
        abs(kb.trend_residual(ramp)) < 1e-3,
        f"got {kb.trend_residual(ramp):.6f}",
    )

    # 25. MAX_ELEMS guard mirrors the C facade's 4096 bound
    try:
        kb.cosine_similarity([1.0] * 4097, [1.0] * 4097)
        check("max_elems_guard", False)
    except kb.KernelContractViolation:
        check("max_elems_guard", True)

    print(f"\n=== {_passed} passed, {_failed} failed ===")
    return 0 if _failed == 0 else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:  # noqa: BLE001 - test harness must report, not swallow
        traceback.print_exc()
        sys.exit(1)
