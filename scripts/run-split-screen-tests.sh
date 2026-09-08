#!/usr/bin/env bash
# =============================================================================
# scripts/run-split-screen-tests.sh — UOS Split-Screen TUI & UI Test Cycle
# =============================================================================
# STAMP: SC-GLM-UI-001, SC-GLM-TST-002, SC-TAILSCALE-WEB-001
# =============================================================================
set -euo pipefail

UOS_ROOT="/home/an/NAS-setup/uos"
cd "${UOS_ROOT}"

echo "==============================================================================="
echo "   Unified Operational System (UOS) — Split-Screen TUI & UI Test Cycle"
echo "==============================================================================="
echo "Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo "Base Tailscale URL: http://nas-1.tail55d152.ts.net:4100"
echo ""

# 1. Preflight Verification
echo "[1/4] Running TUI Preflight Flight Check..."
bash tools/tui preflight
echo ""

# 2. Render Split-Screen TUI Dashboard (Swarm TAB + Test KPIs)
echo "[2/4] Rendering TUI Split-Screen View (Single Frame)..."
bash tools/tui split
echo ""

# 3. Test All 32 Canonical TUI Pages & 12 Subsystem Views
echo "[3/5] Testing All 32 Canonical TUI Pages & 12 Subsystem Views..."
bash tools/test_tui_all_pages.sh
echo ""

# 4. Execute Comprehensive UI & Intent Regression Test Suite
echo "[4/5] Running Comprehensive UI & Intent Regression Suite (apps/cepaf_gleam)..."
(
  cd apps/cepaf_gleam
  gleam test -- --filter comprehensive_ui_regression_test
  gleam test -- --filter intent_config_test
  gleam test -- --filter intent_validator_test
  gleam test -- --filter intent_reconciler_test
  gleam test -- --filter webui_full_system_test
)
echo ""

# 5. Execute Multi-Surface Runtime Verifier (25 Use Cases)
echo "[5/5] Executing Multi-Surface Runtime and Usecase Verifier (25 Use Cases)..."
python3 tools/runtime_and_usecase_verifier.py
echo ""

echo "==============================================================================="
echo "   SPLIT-SCREEN TUI & UI TEST CYCLE COMPLETE — ALL MODALITIES VERIFIED"
echo "==============================================================================="
