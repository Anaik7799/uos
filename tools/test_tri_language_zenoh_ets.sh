#!/usr/bin/env bash
# ==============================================================================
# [C3I-SIL6-MSTS] UOS UNIFIED TRI-LANGUAGE ZENOH & ETS TEST PROTOCOL
# ==============================================================================
# Verifies bidirectional state sharing and consensus across:
#   1. Gleam (BEAM / OTP 29 Supervisor & ETS c3i_cache)
#   2. OCaml (Hermes Bounded Analysis & Evidence Engine)
#   3. Mojo/Python (Modular MAX SIMD Cognitive Inference Tier)
# via Zenoh pub/sub mesh (8080/7447) and BEAM ETS (port 4100).
# STAMP: SC-GLM-UI-001, SC-ZMOF-001, SC-CHECKLIST-001, CHK-07-DRIVE
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UOS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "======================================================================"
echo "[UOS-TRI-LANGUAGE] Starting Cross-Language Zenoh & ETS Verification"
echo "======================================================================"

# 1. Verify Zenoh router accessibility
echo "[STEP 1/4] Checking Zenoh Router (port 8080)..."
if ! curl -s -f "http://127.0.0.1:8080/c3i/a2a/**" > /dev/null; then
    echo "ERROR: Zenoh router is not responding on http://127.0.0.1:8080" >&2
    exit 1
fi
echo "✓ Zenoh router is active and responding."

# 2. Run Gleam BEAM ETS & Zenoh Bridge Test Suite
echo "[STEP 2/4] Executing Gleam EUnit test suite (tri_language_zenoh_ets_test)..."
cd "${UOS_ROOT}/apps/cepaf_gleam"
erl -pa build/dev/erlang/*/ebin -noshell -eval "
    case eunit:test(tri_language_zenoh_ets_test, [verbose]) of
        ok -> halt(0);
        _ -> halt(1)
    end.
"
echo "✓ Gleam tests passed."

# 3. Run OCaml Hermes State Runner
echo "[STEP 3/4] Compiling and executing OCaml Hermes state runner..."
cd "${UOS_ROOT}"
ocamlfind ocamlopt -package unix -linkpkg "${UOS_ROOT}/tools/tri_language_state_runner.ml" -o "${UOS_ROOT}/tools/tri_language_state_runner.exe"
"${UOS_ROOT}/tools/tri_language_state_runner.exe"
rm -f "${UOS_ROOT}/tools/tri_language_state_runner.exe" "${UOS_ROOT}/tools/tri_language_state_runner.cmi" "${UOS_ROOT}/tools/tri_language_state_runner.cmx" "${UOS_ROOT}/tools/tri_language_state_runner.o"
echo "✓ OCaml state runner passed."

# 4. Run Modular MAX / Mojo State Runner
echo "[STEP 4/4] Executing Mojo/MAX state runner (services/inference/max/tri_language_state_runner.py)..."
cd "${UOS_ROOT}"
MODULAR_HOME=/home/an/.modular "${UOS_ROOT}/services/inference/max/.pixi/envs/default/bin/python" \
    "${UOS_ROOT}/services/inference/max/tri_language_state_runner.py"
echo "✓ Mojo/MAX state runner passed."

# 5. Final Convergence Assertion on Wisp REST API
echo "======================================================================"
echo "[VERIFICATION] Querying /api/v1/state/tri_language for convergence..."
RESPONSE=$(curl -s "http://127.0.0.1:4100/api/v1/state/tri_language")
echo "${RESPONSE}"

if echo "${RESPONSE}" | grep -q '"is_converged":true'; then
    echo "======================================================================"
    echo "✓ [SUCCESS] ALL 3 TIER STATES CONVERGED OVER ZENOH & ETS!"
    echo "  - Gleam:  $(echo "${RESPONSE}" | grep -o '"gleam_state":"[^"]*"' | cut -d: -f2)"
    echo "  - OCaml:  $(echo "${RESPONSE}" | grep -o '"ocaml_state":"[^"]*"' | cut -d: -f2)"
    echo "  - Mojo:   $(echo "${RESPONSE}" | grep -o '"mojo_state":"[^"]*"' | cut -d: -f2)"
    echo "======================================================================"
    exit 0
else
    echo "ERROR: State convergence check failed!" >&2
    exit 1
fi
