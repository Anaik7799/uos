# ==============================================================================
# UOS KM PROVENANCE METRICS KERNEL (Mojo 1.0, C ABI)
# ==============================================================================
# <c3i-module>
#   <identity>
#     <module>native/nifs/mojo/uos_km_kernel.mojo</module>
#     <authority>UOS-CANONICAL-AGENT-POLICY</authority>
#     <contract>SC-PROVENANCE-001</contract>
#   </identity>
#   <fractal-topology>
#     <layer>L3_TRANSACTION</layer>
#     <mesh-domain>Bounded native kernel behind a C-ABI dispatch facade</mesh-domain>
#   </fractal-topology>
#   <compliance>
#     <criticality>bounded, deterministic, non-blocking</criticality>
#     <stamp-controls>SC-PROVENANCE-001, SC-ZERO-MUDA-001, SC-JIDOKA-001</stamp-controls>
#   </compliance>
# </c3i-module>
# ==============================================================================
#
# Computes the numeric core of the KM provenance metric set over the
# artifact x dimension coverage matrix produced by the OCaml provenance gate.
#
# Boundedness contract (every entry point):
#   * no allocation, no I/O, no locks, no unbounded loops;
#   * every loop is bounded by a caller-supplied length that is range-checked;
#   * a rejected argument yields a sentinel return, never a trap;
#   * pure: identical arguments always yield identical results.
#
# The caller (C NIF facade) owns all memory. This kernel only reads through the
# supplied pointers and never retains them.
#
# Sentinels: -1.0 rejected argument, -2.0 non-finite input.
# ==============================================================================

from std.math import log, sqrt

comptime MAX_ELEMS: Int = 1 << 22          # 4Mi elements, hard upper bound
comptime REJECTED: Float32 = -1.0
comptime NON_FINITE: Float32 = -2.0
comptime WIDTH: Int = 8                    # fixed SIMD lane count


# ------------------------------------------------------------------------------
# Internal helpers
# ------------------------------------------------------------------------------

def _bounded(n: Int) -> Bool:
    """A length is admissible when it is positive and within the hard bound."""
    return n > 0 and n <= MAX_ELEMS


def _finite(x: Float32) -> Bool:
    """Reject NaN and both infinities without relying on libm classification."""
    if x != x:
        return False
    var big: Float32 = 3.0e38
    return x <= big and x >= -big


# ------------------------------------------------------------------------------
# 1. Weighted conformance score
# ------------------------------------------------------------------------------
# score = sum(feature[i] * weight[i]) / sum(weight[i])
#
# The OCaml gate emits one feature row per artifact: each lane is a 0.0/1.0
# conformance indicator for one checklist dimension. The weight vector encodes
# the dimension's fractal significance. The result is a normalised score in
# [0,1] provided every feature lane is itself in [0,1].

@export
def uos_km_conformance_score(
    features: Pointer[Float32, ImmutAnyOrigin],
    weights: Pointer[Float32, ImmutAnyOrigin],
    n: Int,
) abi("C") -> Float32:
    if not _bounded(n):
        return REJECTED

    var acc = SIMD[DType.float32, WIDTH](0.0)
    var wacc = SIMD[DType.float32, WIDTH](0.0)
    var i = 0
    var limit = n - (n % WIDTH)

    while i < limit:
        var f = (features + i).load[width=WIDTH]()
        var w = (weights + i).load[width=WIDTH]()
        acc = acc + f * w
        wacc = wacc + w
        i += WIDTH

    var total = acc.reduce_add()
    var wtotal = wacc.reduce_add()

    while i < n:
        total += features[i] * weights[i]
        wtotal += weights[i]
        i += 1

    if not _finite(total) or not _finite(wtotal):
        return NON_FINITE
    if wtotal <= 0.0:
        return REJECTED
    return total / wtotal


# ------------------------------------------------------------------------------
# 2. Column reduction over the artifact x dimension matrix
# ------------------------------------------------------------------------------
# Reduces a row-major rows x cols matrix to a per-dimension mean, written into
# the caller-owned `dest` buffer. Returns the number of columns reduced, or a
# negative sentinel cast to Float32 on rejection.

@export
def uos_km_matrix_column_means(
    matrix: Pointer[Float32, ImmutAnyOrigin],
    rows: Int,
    cols: Int,
    dest: Pointer[Float32, MutAnyOrigin],
) abi("C") -> Int32:
    if not _bounded(rows) or not _bounded(cols):
        return -1
    if rows * cols > MAX_ELEMS:
        return -1

    var c = 0
    while c < cols:
        var col_total: Float32 = 0.0
        var r = 0
        while r < rows:
            col_total += matrix[r * cols + c]
            r += 1
        if not _finite(col_total):
            return -2
        dest[c] = col_total / Float32(rows)
        c += 1
    return Int32(cols)


# ------------------------------------------------------------------------------
# 3. Shannon entropy of the coverage distribution (CHK-09-MATH gate, H >= 2.50)
# ------------------------------------------------------------------------------
# Takes raw non-negative counts, normalises them internally, and returns the
# entropy in bits. An all-zero histogram is rejected rather than reported as 0.

@export
def uos_km_shannon_entropy_bits(
    counts: Pointer[Float32, ImmutAnyOrigin],
    n: Int,
) abi("C") -> Float32:
    if not _bounded(n):
        return REJECTED

    var total: Float32 = 0.0
    var i = 0
    while i < n:
        var v = counts[i]
        if v < 0.0 or not _finite(v):
            return REJECTED
        total += v
        i += 1

    if total <= 0.0:
        return REJECTED

    var ln2: Float32 = 0.6931471805599453
    var h: Float32 = 0.0
    i = 0
    while i < n:
        var p = counts[i] / total
        if p > 0.0:
            h -= p * (log(p) / ln2)
        i += 1

    if not _finite(h):
        return NON_FINITE
    return h


# ------------------------------------------------------------------------------
# 4. FMEA risk classification (RPN -> band), matching the risk-priority policy
# ------------------------------------------------------------------------------
# Band maxima are [5, 15, 35, 70, 125], identical to
# governance/planning/20260907-1559-risk-priority-policy.json. Severity,
# occurrence and detection are each on a 1..5 scale.

@export
def uos_km_fmea_band(severity: Int32, occurrence: Int32, detection: Int32) abi("C") -> Int32:
    if severity < 1 or severity > 5:
        return -1
    if occurrence < 1 or occurrence > 5:
        return -1
    if detection < 1 or detection > 5:
        return -1

    var rpn = Int(severity) * Int(occurrence) * Int(detection)
    if rpn <= 5:
        return 1
    if rpn <= 15:
        return 2
    if rpn <= 35:
        return 3
    if rpn <= 70:
        return 4
    return 5


# ------------------------------------------------------------------------------
# 5. Quarantine drift distance
# ------------------------------------------------------------------------------
# Euclidean distance between an observed surface coverage vector and the
# nominal (fully-marked) centroid. 0.0 means every surface carries the
# provenance marking; larger values mean more drift.

@export
def uos_km_drift_distance(
    observed: Pointer[Float32, ImmutAnyOrigin],
    nominal: Pointer[Float32, ImmutAnyOrigin],
    n: Int,
) abi("C") -> Float32:
    if not _bounded(n):
        return REJECTED

    var acc = SIMD[DType.float32, WIDTH](0.0)
    var i = 0
    var limit = n - (n % WIDTH)

    while i < limit:
        var d = (observed + i).load[width=WIDTH]() - (nominal + i).load[width=WIDTH]()
        acc = acc + d * d
        i += WIDTH

    var total = acc.reduce_add()
    while i < n:
        var d = observed[i] - nominal[i]
        total += d * d
        i += 1

    if not _finite(total):
        return NON_FINITE
    return sqrt(total)


# ------------------------------------------------------------------------------
# 6. Kernel identity
# ------------------------------------------------------------------------------

@export
def uos_km_kernel_abi_version() abi("C") -> Int32:
    return 1
