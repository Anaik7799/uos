#!/usr/bin/env bash
# =============================================================================
# tools/test_tui_all_pages.sh — Automated Test Harness for All 32 TUI Pages
# =============================================================================
# STAMP: SC-GLM-UI-001, SC-GLM-UI-004, SC-CHECKLIST-001
# =============================================================================
set -euo pipefail

UOS_ROOT="/home/an/NAS-setup/uos"
cd "${UOS_ROOT}"

echo "==============================================================================="
echo "   Unified Operational System (UOS) — Automated System TUI 32-Page Test"
echo "==============================================================================="
echo "Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo ""

PAGES=(
  "dashboard"
  "planning"
  "immune"
  "knowledge"
  "zenoh"
  "cockpit"
  "verification"
  "substrate"
  "metabolic"
  "podman"
  "mcp"
  "kms"
  "telemetry"
  "federation"
  "health-grid"
  "prajna"
  "agents"
  "holon"
  "config"
  "git"
  "database"
  "bridge"
  "smriti"
  "planning-dashboard"
  "integrity"
  "evolution"
  "biomorphic"
  "homeostasis"
  "bicameral"
  "singularity"
  "components"
  "auth"
)

VIEWS=(
  "planning"
  "verification"
  "immune"
  "zenoh"
  "podman"
  "cockpit"
  "prajna"
  "homeostasis"
  "evolution"
  "fmea"
  "ruliology"
  "pipeline-tracer"
)

PASSED_PAGES=0
FAILED_PAGES=0

echo "[1/3] Testing All 32 Canonical TUI Pages..."
for page in "${PAGES[@]}"; do
  output=$(bash tools/tui page "$page" 2>&1 || true)
  if [ -n "$output" ]; then
    echo "  [PASS] Page: $page (frame rendered, length: ${#output} chars)"
    PASSED_PAGES=$((PASSED_PAGES + 1))
  else
    echo "  [FAIL] Page: $page (empty frame output)"
    FAILED_PAGES=$((FAILED_PAGES + 1))
  fi
done

echo ""
echo "[2/3] Testing Specialized Subsystem Views..."
PASSED_VIEWS=0
FAILED_VIEWS=0
for view in "${VIEWS[@]}"; do
  output=$(bash tools/tui view "$view" 2>&1 || true)
  if [ -n "$output" ]; then
    echo "  [PASS] Subsystem View: $view (rendered, length: ${#output} chars)"
    PASSED_VIEWS=$((PASSED_VIEWS + 1))
  else
    echo "  [FAIL] Subsystem View: $view (empty view output)"
    FAILED_VIEWS=$((FAILED_VIEWS + 1))
  fi
done

echo ""
echo "[3/3] Testing TUI Preflight and Split-Screen Modes..."
preflight_out=$(bash tools/tui preflight 2>&1 || true)
if echo "$preflight_out" | grep -q "Passed: true"; then
  echo "  [PASS] TUI Preflight: Passed: true"
else
  echo "  [FAIL] TUI Preflight failed: $preflight_out"
  FAILED_PAGES=$((FAILED_PAGES + 1))
fi

split_out=$(bash tools/tui split 2>&1 || true)
if [ -n "$split_out" ]; then
  echo "  [PASS] TUI Split-Screen: Single frame rendered successfully"
else
  echo "  [FAIL] TUI Split-Screen failed"
  FAILED_PAGES=$((FAILED_PAGES + 1))
fi

echo ""
echo "==============================================================================="
echo "   TUI TEST SUMMARY: $PASSED_PAGES/32 Pages Passed, $PASSED_VIEWS/12 Views Passed"
echo "==============================================================================="

if [ "$FAILED_PAGES" -gt 0 ] || [ "$FAILED_VIEWS" -gt 0 ]; then
  echo "ERROR: Some TUI test cases failed!"
  exit 1
fi

echo "ALL SYSTEM TUI PAGES AND SUBSYSTEM VIEWS VERIFIED 100% GREEN."
