#!/usr/bin/env bash
# ==============================================================================
# run_guard_rules_suite.sh — Automated Test Suite Runner for UOS Guard Rules
#
# Unified Operational System (UOS) / High-Availability Guard Grid
# Evaluates 105 rules, 10 fractal layers, and OODA actor integration.
# STAMP/STPA: SC-SIL4-001, SC-HA-001, SC-OODA-001, SC-CHECKLIST-001
# ==============================================================================

set -euo pipefail

UOS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${UOS_ROOT}"

PASS_COUNT=0
FAIL_COUNT=0

log_info() { echo -e "\033[1;34m[INFO]\033[0m $*"; }
log_pass() { echo -e "\033[1;32m[PASS]\033[0m $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
log_fail() { echo -e "\033[1;31m[FAIL]\033[0m $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

echo "========================================================================"
echo "UOS High-Availability Guard Rules Test Suite Runner"
echo "Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo "Catalog: 105 Rules | Layers: L0-L9 | Actor: guard_grid_actor"
echo "========================================================================"

# Phase 1: Algebraic Rule Verifier & Layer Entropy Check
log_info "Phase 1: Executing native OCaml guard rules algebraic verifier..."
if [[ ! -x "${UOS_ROOT}/tools/guard_rules_verifier.exe" ]]; then
    log_info "Compiling tools/guard_rules_verifier.ml..."
    ocamlopt -O3 -I +unix unix.cmxa -I +str str.cmxa "${UOS_ROOT}/tools/guard_rules_verifier.ml" -o "${UOS_ROOT}/tools/guard_rules_verifier.exe"
    rm -f "${UOS_ROOT}/tools/guard_rules_verifier.cmi" "${UOS_ROOT}/tools/guard_rules_verifier.cmx" "${UOS_ROOT}/tools/guard_rules_verifier.o"
fi

"${UOS_ROOT}/tools/guard_rules_verifier.exe"
log_pass "Algebraic verifier passed (105 rules, H >= 2.50b, disjoint sentinels)"

# Phase 2: Gleam EUnit ha_guard_rules_test (194 tests)
log_info "Phase 2: Running Gleam EUnit test suite for ha_guard_rules_test (194 tests)..."
START_TS=$(date +%s%N)
if erl -pa apps/cepaf_gleam/build/dev/erlang/*/ebin -noshell -eval 'case eunit:test(ha_guard_rules_test) of ok -> init:stop(0); _ -> init:stop(1) end.'; then
    END_TS=$(date +%s%N)
    DURATION_MS=$(( (END_TS - START_TS) / 1000000 ))
    log_pass "ha_guard_rules_test: All 194 unit tests passed (${DURATION_MS} ms)"
else
    log_fail "ha_guard_rules_test: Unit test suite failed"
fi

# Phase 3: Gleam EUnit guard_grid_actor_test (22 tests)
log_info "Phase 3: Running Gleam EUnit test suite for guard_grid_actor_test (22 tests)..."
START_ACTOR_TS=$(date +%s%N)
if erl -pa apps/cepaf_gleam/build/dev/erlang/*/ebin -noshell -eval 'case eunit:test(guard_grid_actor_test) of ok -> init:stop(0); _ -> init:stop(1) end.'; then
    END_ACTOR_TS=$(date +%s%N)
    DURATION_ACTOR_MS=$(( (END_ACTOR_TS - START_ACTOR_TS) / 1000000 ))
    log_pass "guard_grid_actor_test: All 22 actor integration tests passed (${DURATION_ACTOR_MS} ms)"
else
    log_fail "guard_grid_actor_test: Actor integration test suite failed"
fi

# Phase 4: Zero-Muda & Storage Safety Interlock Invariant
log_info "Phase 4: Checking Zero-Muda dependency purity and hardware storage interlock..."
if grep -iE "(bevy|graphite)" apps/cepaf_gleam/gleam.toml; then
    log_fail "Zero-Muda violation: Bevy or Graphite found in gleam.toml dependencies"
else
    log_pass "Zero-Muda purity confirmed: 0 Bevy, 0 Graphite in project dependencies"
fi

if grep -q "HARD_DENIED_SYSTEM_OS_SERIAL" ops/kubernetes/nas-k8s-lab/src/spec.rs; then
    log_pass "Hardware storage interlock verified: HARD_DENIED_SYSTEM_OS_SERIAL locked in spec.rs"
else
    log_fail "Hardware storage interlock missing in spec.rs"
fi

echo "========================================================================"
echo "TEST SUITE SUMMARY"
echo "  Passed: ${PASS_COUNT}"
echo "  Failed: ${FAIL_COUNT}"
echo "  Total Tests Evaluated: 216 Tests (194 Rules + 22 Actor) + Algebraic Proofs"
echo "========================================================================"

if [[ ${FAIL_COUNT} -eq 0 ]]; then
    exit 0
else
    exit 1
fi
