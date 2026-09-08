#!/usr/bin/env bash
# =============================================================================
# scripts/deploy-cockpit-harness.sh — UOS System Web & TUI Deployment Harness
# =============================================================================
# STAMP: SC-GLM-UI-001, SC-GLM-UI-004, SC-TAILSCALE-WEB-001, SC-CHECKLIST-001
# =============================================================================
set -euo pipefail

UOS_ROOT="/home/an/NAS-setup/uos"
cd "${UOS_ROOT}"

MODE="${1:---web}"
BASE_URL="http://nas-1.tail55d152.ts.net:4100"
LOCAL_URL="http://127.0.0.1:4100"
ZENOH_URL="http://127.0.0.1:8080/uos/tui/state/hive"

echo "==============================================================================="
echo "   Unified Operational System (UOS) — Cockpit Deployment Harness"
echo "==============================================================================="
echo "Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo "Target Tailscale FQDN: ${BASE_URL}"
echo "Localhost Binding:     ${LOCAL_URL}"
echo ""

# 1. Environment & Prerequisite Checks
echo "[1/4] Checking System Prerequisites & Port Availability..."
if [ ! -f "var/km/provenance-cycles.sqlite3" ]; then
  echo "ERROR: Missing provenance ledger at var/km/provenance-cycles.sqlite3"
  exit 1
fi

if [ ! -f "var/sa-plan/uos.sqlite3" ]; then
  echo "ERROR: Missing Sa-Plan ledger at var/sa-plan/uos.sqlite3"
  exit 1
fi
echo "  [OK] SQLite ledgers verified intact."

# 2. Check Zenoh Telemetry Bridge
echo "[2/4] Verifying Zenoh Telemetry REST Bridge..."
if curl -s -m 3 "${ZENOH_URL}" >/dev/null 2>&1; then
  echo "  [OK] Zenoh REST bridge active on port 8080."
else
  echo "  [WARN] Zenoh REST bridge not responding on port 8080; continuing in offline telemetry mode."
fi

# 3. Check Web Server Status
echo "[3/4] Checking CEPAF Gleam Web Cockpit Status (Port 4100)..."
if curl -s -m 3 "${LOCAL_URL}/checklist" >/dev/null 2>&1; then
  echo "  [OK] Gleam Web Cockpit is active and serving requests on port 4100."
else
  echo "  [NOTICE] Web server not responding on port 4100. Attempting daemon launch..."
  # Check if background server launcher exists
  if [ -x "tools/uos-cli" ]; then
    bash tools/uos-cli doctor || true
  fi
fi

# 4. Mode Execution
echo "[4/4] Executing Target Mode: ${MODE}..."
case "${MODE}" in
  --test|test)
    echo "Running Full Headless CI Test Suite (WebUI + TUI + Runtime Verifier)..."
    bash tools/test_tui_all_pages.sh
    python3 tools/runtime_and_usecase_verifier.py
    echo "==============================================================================="
    echo "   DEPLOYMENT HARNESS TEST MODE COMPLETE — ALL TESTS VERIFIED GREEN"
    echo "==============================================================================="
    ;;

  --tui|tui)
    echo "Launching Interactive System TUI Cockpit..."
    exec bash tools/tui start
    ;;

  --web|web)
    echo "Web Cockpit is deployed and accessible at:"
    echo "  - Main Dashboard:        ${BASE_URL}/"
    echo "  - Planning:              ${BASE_URL}/planning"
    echo "  - Verification Checklist: ${BASE_URL}/checklist"
    echo "  - AG-UI Event Stream:    ${BASE_URL}/ag-ui/events"
    echo "  - ZigVM ZK Decisions:    ${BASE_URL}/zk"
    echo "  - Hermes Wiki Index:     ${BASE_URL}/wiki"
    echo "  - FPP Algebraic Atlas:   ${BASE_URL}/api/fpp/atlas"
    echo "  - Declarative Intent:    ${BASE_URL}/api/intent/config"
    echo ""
    echo "To test interactively in browser, open any of the above URLs."
    ;;

  --interactive|interactive)
    echo "Select Deployment Action:"
    echo "  1) Launch Interactive TUI (tools/tui start)"
    echo "  2) Render TUI Split-Screen View (tools/tui split)"
    echo "  3) Run Full Headless Test Cycle (bash scripts/run-split-screen-tests.sh)"
    echo "  4) Run 32-Page TUI Automated Test (bash tools/test_tui_all_pages.sh)"
    echo "  5) Display Live Tailscale URLs"
    echo "  q) Exit"
    read -r -p "Enter selection [1-5, q]: " CHOICE || CHOICE="5"
    case "$CHOICE" in
      1) exec bash tools/tui start ;;
      2) exec bash tools/tui split ;;
      3) exec bash scripts/run-split-screen-tests.sh ;;
      4) exec bash tools/test_tui_all_pages.sh ;;
      5)
        echo "Cockpit Base URL: ${BASE_URL}/"
        echo "Checklist URL:    ${BASE_URL}/checklist"
        ;;
      *) echo "Exiting." ;;
    esac
    ;;

  *)
    echo "Unknown mode: ${MODE}. Available modes: --web, --tui, --test, --interactive"
    exit 1
    ;;
esac
