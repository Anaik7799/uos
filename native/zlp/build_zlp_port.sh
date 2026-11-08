#!/usr/bin/env bash
# ==============================================================================
# native/zlp/build_zlp_port.sh
# Reproducible UOS-ZLP-v3 Builder (Lean 4.35.0 + Zig 0.16.0 Zen 5 AVX-512)
# Emits untracked runtime binary to <workspace>/var/zlp/uos_zlp_v3_port so zero
# build artifacts pollute tracked Jujutsu directories.
# ==============================================================================
set -euo pipefail

ZLP_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
WS_ROOT="$(CDPATH= cd -- "$ZLP_DIR/../.." && pwd)"
CANONICAL_ROOT="${UOS_CANONICAL_ROOT:-/home/an/NAS-setup/uos}"

if [[ -d "$WS_ROOT/toolchains/lean-4.35.0" ]]; then
  TOOLCHAIN_ROOT="$WS_ROOT"
elif [[ -d "$CANONICAL_ROOT/toolchains/lean-4.35.0" ]]; then
  TOOLCHAIN_ROOT="$CANONICAL_ROOT"
else
  echo "ERROR: Lean 4.35.0 toolchain not found in $WS_ROOT or $CANONICAL_ROOT" >&2
  exit 2
fi

# shellcheck source=/dev/null
source "$TOOLCHAIN_ROOT/tools/lib/uos-toolchain.sh"
uos_env

LEAN_ROOT="$TOOLCHAIN_ROOT/toolchains/lean-4.35.0"
LEAN_BIN="$LEAN_ROOT/bin/lean"
LEAN_INC="$LEAN_ROOT/include"
LEAN_LIB="$LEAN_ROOT/lib/lean"
ZIG_BIN="$(uos_tool_path zig)"

LEAN_SRC="$WS_ROOT/formal/lean/UosZlpHyperplane.lean"
SHIM_SRC="$ZLP_DIR/lean_shim_v3.c"
ZIG_SRC="$ZLP_DIR/uos_zlp_port.zig"
OUT_DIR="${UOS_ZLP_OUT_DIR:-$WS_ROOT/var/zlp}"
OUT_BIN="$OUT_DIR/uos_zlp_v3_port"

TMP_BASE="${TMPDIR:-$OUT_DIR/.tmp}"
mkdir -p "$TMP_BASE"
BUILD_TMP="$(mktemp -d "$TMP_BASE/uos-zlp-v3-build.XXXXXX")"
trap 'rm -rf -- "$BUILD_TMP"' EXIT

echo "[1/3] Mechanically verifying 20 Lean 4.33.0 theorems (0 sorryAx) & generating C IR..."
cp "$LEAN_SRC" "$BUILD_TMP/UosZlpHyperplane.lean"
cat >> "$BUILD_TMP/UosZlpHyperplane.lean" <<'EOF'
#print axioms UosZlpHyperplane.T01_wire_header_roundtrip
#print axioms UosZlpHyperplane.T02_wire_decode_enforces_cap
#print axioms UosZlpHyperplane.T03_perceus_zero_malloc_for_all_n
#print axioms UosZlpHyperplane.T04_replay_always_rejected
#print axioms UosZlpHyperplane.T05_out_of_order_unseen_accepted
#print axioms UosZlpHyperplane.T06_lyapunov_exact_zero_at_equilibrium
#print axioms UosZlpHyperplane.T07_lyapunov_exact_pos_def
#print axioms UosZlpHyperplane.T08_lyapunov_exponential_contraction
#print axioms UosZlpHyperplane.T09_credit_queue_never_overflows
#print axioms UosZlpHyperplane.T10_zlp_cannot_escalate_authority
#print axioms UosZlpHyperplane.T11_zlp_veto_blocks_effect
#print axioms UosZlpHyperplane.T12_meshJoin_semilattice
#print axioms UosZlpHyperplane.T13_two_lane_ooo_correlation_sound
#print axioms UosZlpHyperplane.T14_zenoh_key_blocks_a2a_and_nul
#print axioms UosZlpHyperplane.T15_ets_subscription_replay_idempotent
#print axioms UosZlpHyperplane.T16_pku_bracket_always_relocks
#print axioms UosZlpHyperplane.T17_scale_budget_gate_sound
#print axioms UosZlpHyperplane.T18_risk_priority_zero_when_unready
#print axioms UosZlpHyperplane.T19_km_fresh_reopen_eliminates_staleness
#print axioms UosZlpHyperplane.T20_graceful_drain_reaches_zero
EOF

"$LEAN_BIN" "$BUILD_TMP/UosZlpHyperplane.lean" > "$BUILD_TMP/axioms.log" 2>&1
if grep -q "sorryAx" "$BUILD_TMP/axioms.log"; then
  echo "FATAL: sorryAx detected in UosZlpHyperplane.lean!" >&2
  cat "$BUILD_TMP/axioms.log" >&2
  exit 1
fi
(cd "$(dirname "$LEAN_SRC")" && "$LEAN_BIN" -c "$BUILD_TMP/UosZlpHyperplane.c" UosZlpHyperplane.lean)

echo "[2/3] Compiling Zig 0.16.0 Zen 5 AVX-512 Two-Lane epoll port object..."
(cd "$BUILD_TMP" && "$ZIG_BIN" build-obj -OReleaseFast -mcpu=native -fPIC -lc "$ZIG_SRC")

echo "[3/3] Linking native supervised OTP port executable -> $OUT_BIN..."
mkdir -p "$OUT_DIR"
"$ZIG_BIN" cc -O3 -march=native -pthread \
  -I"$LEAN_INC" \
  "$BUILD_TMP/UosZlpHyperplane.c" \
  "$SHIM_SRC" \
  "$BUILD_TMP/uos_zlp_port.o" \
  -L"$LEAN_LIB" -lleanshared -Wl,-rpath,"$LEAN_LIB" \
  -o "$OUT_BIN"

chmod +x "$OUT_BIN"
echo "BUILD_OK binary=$OUT_BIN sha256=$(sha256sum "$OUT_BIN" | cut -d' ' -f1)"
