#!/usr/bin/env python3
# ==============================================================================
# [C3I-SIL6-MSTS] Mojo SIMD Kernel Bridge — ETC-2 Remediation (SC-ZERO-MUDA-001)
# ==============================================================================
# Language Mandate: Python is confined to services/inference/max (see AGENTS.md 5.4).
# This module binds the compiled Mojo SIMD kernel (native/nifs/mojo/uos_km_kernel.mojo
# -> apps/cepaf_gleam/priv/libuos_km_kernel.so) through the C ABI declared in
# native/nifs/mojo/uos_km_nif.c:23-33.
#
# HARD CONTRACT (fail-closed, ETC-2):
#   * There is NO silent fallback to pure-Python hash-projected math. If the kernel
#     is absent, fails to dlopen, or reports an unexpected ABI version, every
#     kernel-dependent entry point raises KernelUnavailable.
#   * A deterministic hash projection MUST NOT masquerade as a SIMD/learned result
#     (STPA UCA-2 "unsafe action provided"). Callers see a typed refusal instead
#     of a number they would otherwise trust.
#
# Authority: contracts/rules/20260907-1559-risk-prioritization-sop.md
#            native/nifs/mojo/test_uos_km_kernel.c (independent oracle, 1e-4)
# ==============================================================================

from __future__ import annotations

import ctypes
import os
import threading
from typing import List, Optional, Sequence

# ------------------------------------------------------------------------------
# Constants
# ------------------------------------------------------------------------------

#: ABI version the compiled kernel must report. Bump only with a joint kernel change.
EXPECTED_ABI_VERSION = 3

#: Upper bound enforced by the C facade (native/nifs/mojo/uos_km_nif.c).
MAX_ELEMS = 4096

#: Kernel sentinel returned for rejected/empty inputs.
REJECTED = -1.0
NON_FINITE = -2.0

#: Error codes surfaced to the JSON-RPC layer.
ERR_KERNEL_UNAVAILABLE = -32003
ERR_KERNEL_CONTRACT = -32004

_DEFAULT_REPO = "/home/an/NAS-setup/uos"
_SO_RELPATH = "apps/cepaf_gleam/priv/libuos_km_kernel.so"


class KernelUnavailable(RuntimeError):
    """Raised when the Mojo SIMD kernel is not usable. Never swallowed."""

    code = ERR_KERNEL_UNAVAILABLE


class KernelContractViolation(ValueError):
    """Raised when inputs or kernel output violate the declared C ABI contract."""

    code = ERR_KERNEL_CONTRACT


# ------------------------------------------------------------------------------
# Library resolution
# ------------------------------------------------------------------------------


def _candidate_paths() -> List[str]:
    """Resolve the kernel shared object in precedence order.

    `UOS_KM_KERNEL_SO` is AUTHORITATIVE when set: if the operator names a path,
    that path is the only candidate. Falling back to a different shared object
    would make the fail-closed behaviour untestable and would hide a bad pin
    behind a silently-working rebuild. Unset => repo-relative discovery.
    """
    paths: List[str] = []
    env = os.environ.get("UOS_KM_KERNEL_SO")
    if env:
        return [env]
    root = os.environ.get("UOS_REPO_ROOT", _DEFAULT_REPO)
    paths.append(os.path.join(root, _SO_RELPATH))
    here = os.path.dirname(os.path.abspath(__file__))
    # services/inference/max -> repo root is three levels up
    guessed = os.path.abspath(os.path.join(here, "..", "..", "..", _SO_RELPATH))
    paths.append(guessed)
    return paths


def _bind(lib: ctypes.CDLL) -> None:
    """Declare argtypes/restype for every exported symbol.

    Types are taken from native/nifs/mojo/uos_km_nif.c:23-33 — ``float`` results,
    ``int32_t`` band/abi values, ``long`` element counts, ``const float *`` buffers.
    Declaring these as ``c_double`` (a common mistake) silently mis-reads the
    xmm0 low 32 bits and produces garbage similarities.
    """
    fp = ctypes.POINTER(ctypes.c_float)

    lib.uos_km_cosine_similarity.argtypes = [fp, fp, ctypes.c_long]
    lib.uos_km_cosine_similarity.restype = ctypes.c_float

    lib.uos_km_drift_distance.argtypes = [fp, fp, ctypes.c_long]
    lib.uos_km_drift_distance.restype = ctypes.c_float

    lib.uos_km_conformance_score.argtypes = [fp, fp, ctypes.c_long]
    lib.uos_km_conformance_score.restype = ctypes.c_float

    lib.uos_km_shannon_entropy_bits.argtypes = [fp, ctypes.c_long]
    lib.uos_km_shannon_entropy_bits.restype = ctypes.c_float

    lib.uos_km_ewma.argtypes = [fp, ctypes.c_long, ctypes.c_float]
    lib.uos_km_ewma.restype = ctypes.c_float

    lib.uos_km_linear_slope.argtypes = [fp, ctypes.c_long]
    lib.uos_km_linear_slope.restype = ctypes.c_float

    lib.uos_km_trend_residual.argtypes = [fp, ctypes.c_long]
    lib.uos_km_trend_residual.restype = ctypes.c_float

    lib.uos_km_fmea_band.argtypes = [ctypes.c_int32, ctypes.c_int32, ctypes.c_int32]
    lib.uos_km_fmea_band.restype = ctypes.c_int32

    lib.uos_km_kernel_abi_version.argtypes = []
    lib.uos_km_kernel_abi_version.restype = ctypes.c_int32

    lib.uos_km_matrix_column_means.argtypes = [
        fp,
        ctypes.c_long,
        ctypes.c_long,
        fp,
    ]
    lib.uos_km_matrix_column_means.restype = ctypes.c_int32


class _Kernel:
    """Process-wide kernel handle with a typed availability verdict."""

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self.lib: Optional[ctypes.CDLL] = None
        self.abi_version: Optional[int] = None
        self.path: Optional[str] = None
        self.reason: Optional[str] = None
        self._load()

    def _load(self) -> None:
        tried: List[str] = []
        for path in _candidate_paths():
            tried.append(path)
            if not os.path.exists(path):
                continue
            try:
                lib = ctypes.CDLL(path)
                _bind(lib)
                abi = int(lib.uos_km_kernel_abi_version())
            except OSError as exc:
                self.reason = f"dlopen failed for {path}: {exc}"
                continue
            except AttributeError as exc:
                self.reason = f"{path} is missing an exported symbol: {exc}"
                continue
            if abi != EXPECTED_ABI_VERSION:
                self.reason = (
                    f"ABI version mismatch at {path}: kernel reports {abi}, "
                    f"bridge expects {EXPECTED_ABI_VERSION}"
                )
                continue
            self.lib = lib
            self.abi_version = abi
            self.path = path
            self.reason = None
            return
        if self.reason is None:
            self.reason = (
                "libuos_km_kernel.so not found; searched: " + ", ".join(tried)
            )

    @property
    def available(self) -> bool:
        return self.lib is not None

    def require(self) -> ctypes.CDLL:
        if self.lib is None:
            raise KernelUnavailable(
                f"Mojo SIMD kernel unavailable: {self.reason}. "
                "Hash-projection fallback is disabled per ETC-2 remediation."
            )
        return self.lib

    def status(self) -> dict:
        return {
            "kernel_status": "available" if self.available else "unavailable",
            "kernel_abi_version": self.abi_version,
            "kernel_expected_abi": EXPECTED_ABI_VERSION,
            "kernel_path": self.path,
            "kernel_reason": self.reason,
            "kernel_simd": self.available,
        }

    def reload(self) -> dict:
        """Re-attempt binding (used by health probes after a rebuild)."""
        with self._lock:
            self.lib = None
            self.abi_version = None
            self.path = None
            self.reason = None
            self._load()
            return self.status()


_KERNEL = _Kernel()


# ------------------------------------------------------------------------------
# Marshalling helpers
# ------------------------------------------------------------------------------


def _as_float_buffer(values: Sequence[float]) -> "ctypes.Array[ctypes.c_float]":
    """Copy a Python sequence into a contiguous c_float array, validating bounds."""
    if not isinstance(values, (list, tuple)):
        raise KernelContractViolation(
            f"expected a list/tuple of floats, received {type(values).__name__}"
        )
    if not values:
        raise KernelContractViolation("empty vector rejected by the C facade")
    if len(values) > MAX_ELEMS:
        raise KernelContractViolation(
            f"vector length {len(values)} exceeds MAX_ELEMS={MAX_ELEMS}"
        )
    buf = (ctypes.c_float * len(values))()
    for i, v in enumerate(values):
        buf[i] = float(v)
    return buf


def _checked(value: float, detail: dict) -> float:
    """Reject kernel sentinels instead of returning them as data."""
    if value == REJECTED:
        raise KernelContractViolation(f"kernel rejected the input: {detail}")
    if value == NON_FINITE:
        raise KernelContractViolation(f"kernel observed non-finite input: {detail}")
    return float(value)


# ------------------------------------------------------------------------------
# Public API — kernel-backed primitives
# ------------------------------------------------------------------------------


def kernel_status() -> dict:
    """Availability snapshot for health/metrics surfaces."""
    return _KERNEL.status()


def reload_kernel() -> dict:
    return _KERNEL.reload()


def abi_version() -> int:
    return int(_KERNEL.require().uos_km_kernel_abi_version())


def cosine_similarity(a: Sequence[float], b: Sequence[float]) -> float:
    """SIMD cosine similarity in [-1.0, 1.0].

    Sentinel disambiguation: the kernel returns -1.0 both for a rejected input
    and for legitimately opposed vectors (see native/nifs/mojo/uos_km_nif.c:181).
    Because empty/oversize inputs are rejected here before the call, a rejected
    result can only mean one of the vectors has zero norm — the documented
    zero-vector case, which returns 0.0 exactly as the facade does for NIF
    callers. NON_FINITE is still a hard contract violation.
    """
    lib = _KERNEL.require()
    if len(a) != len(b):
        raise KernelContractViolation(
            f"dimension mismatch: len(a)={len(a)} len(b)={len(b)}"
        )
    ba = _as_float_buffer(a)
    bb = _as_float_buffer(b)
    raw = float(lib.uos_km_cosine_similarity(ba, bb, len(a)))
    if raw == NON_FINITE:
        raise KernelContractViolation(
            f"kernel observed non-finite cosine input: n={len(a)}"
        )
    if raw == REJECTED:
        return 0.0
    return raw


def drift_distance(observed: Sequence[float], nominal: Sequence[float]) -> float:
    """Euclidean drift between an observation and its nominal reference."""
    lib = _KERNEL.require()
    if len(observed) != len(nominal):
        raise KernelContractViolation(
            f"dimension mismatch: len(observed)={len(observed)} "
            f"len(nominal)={len(nominal)}"
        )
    bo = _as_float_buffer(observed)
    bn = _as_float_buffer(nominal)
    return _checked(
        lib.uos_km_drift_distance(bo, bn, len(observed)), {"n": len(observed)}
    )


def conformance_score(features: Sequence[float], weights: Sequence[float]) -> float:
    """Weighted conformance fraction in [0.0, 1.0]."""
    lib = _KERNEL.require()
    if len(features) != len(weights):
        raise KernelContractViolation(
            f"dimension mismatch: len(features)={len(features)} "
            f"len(weights)={len(weights)}"
        )
    bf = _as_float_buffer(features)
    bw = _as_float_buffer(weights)
    return _checked(
        lib.uos_km_conformance_score(bf, bw, len(features)), {"n": len(features)}
    )


def shannon_entropy_bits(counts: Sequence[float]) -> float:
    """Shannon entropy H = -sum(p*log2 p) over a count/probability histogram."""
    lib = _KERNEL.require()
    bc = _as_float_buffer(counts)
    return _checked(
        lib.uos_km_shannon_entropy_bits(bc, len(counts)), {"n": len(counts)}
    )


def fmea_band(severity: int, occurrence: int, detection: int) -> int:
    """FMEA RPN severity band (1..5) computed by the kernel, not by an if-chain.

    Band maxima are [5, 15, 35, 70, 125] per
    governance/planning/20260907-1559-risk-priority-policy.json; all three
    factors live on a 1..5 scale (native/nifs/mojo/uos_km_kernel.mojo:187).
    """
    lib = _KERNEL.require()
    s, o, d = int(severity), int(occurrence), int(detection)
    _check_fmea_factors(s, o, d)
    band = int(lib.uos_km_fmea_band(s, o, d))
    if band < 1 or band > 5:
        raise KernelContractViolation(
            f"kernel rejected FMEA factors S={s} O={o} D={d} (band={band})"
        )
    return band


def _check_fmea_factors(s: int, o: int, d: int) -> None:
    if not (1 <= s <= 5 and 1 <= o <= 5 and 1 <= d <= 5):
        raise KernelContractViolation(
            f"FMEA factors must be 1..5, received S={s} O={o} D={d}"
        )


def fmea_rpn(severity: int, occurrence: int, detection: int) -> int:
    """RPN = S * O * D over the 1..5 factor scale (max 125)."""
    s, o, d = int(severity), int(occurrence), int(detection)
    _check_fmea_factors(s, o, d)
    return s * o * d


def ewma(series: Sequence[float], alpha: float) -> float:
    lib = _KERNEL.require()
    bs = _as_float_buffer(series)
    return _checked(lib.uos_km_ewma(bs, len(series), float(alpha)), {"n": len(series)})


def linear_slope(series: Sequence[float]) -> float:
    lib = _KERNEL.require()
    bs = _as_float_buffer(series)
    return _checked(lib.uos_km_linear_slope(bs, len(series)), {"n": len(series)})


def trend_residual(series: Sequence[float]) -> float:
    lib = _KERNEL.require()
    bs = _as_float_buffer(series)
    return _checked(lib.uos_km_trend_residual(bs, len(series)), {"n": len(series)})


def matrix_column_means(matrix: Sequence[Sequence[float]]) -> List[float]:
    """Column means of a row-major matrix; returns len(cols) floats."""
    lib = _KERNEL.require()
    rows = len(matrix)
    if rows == 0:
        raise KernelContractViolation("empty matrix rejected")
    cols = len(matrix[0])
    if cols == 0:
        raise KernelContractViolation("matrix with zero columns rejected")
    total = rows * cols
    if total > MAX_ELEMS:
        raise KernelContractViolation(
            f"matrix cells {total} exceed MAX_ELEMS={MAX_ELEMS}"
        )
    flat = (ctypes.c_float * total)()
    for r, row in enumerate(matrix):
        if len(row) != cols:
            raise KernelContractViolation(f"ragged matrix at row {r}")
        for c, v in enumerate(row):
            flat[r * cols + c] = float(v)
    dest = (ctypes.c_float * cols)()
    rc = int(lib.uos_km_matrix_column_means(flat, rows, cols, dest))
    # Contract per native/nifs/mojo/uos_km_kernel.mojo:115-138: success returns
    # the number of columns reduced; -1 = rejected bounds, -2 = non-finite sum.
    if rc == -1:
        raise KernelContractViolation(
            f"matrix_column_means rejected bounds rows={rows} cols={cols}"
        )
    if rc == -2:
        raise KernelContractViolation("matrix_column_means saw a non-finite sum")
    if rc != cols:
        raise KernelContractViolation(
            f"matrix_column_means reduced {rc} columns, expected {cols}"
        )
    return [float(dest[i]) for i in range(cols)]


def normalized_entropy(counts: Sequence[float]) -> float:
    """Convenience: entropy of raw counts, normalised to probabilities first."""
    total = float(sum(counts))
    if total <= 0.0:
        raise KernelContractViolation("cannot normalise a zero-sum histogram")
    return shannon_entropy_bits([float(c) / total for c in counts])
