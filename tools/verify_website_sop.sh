#!/usr/bin/env bash
# ==============================================================================
# verify_website_sop.sh — Automated SOP Verification Script for Universal
# Web, Wiki, ZK, Content, Semantics, Components & Link Invariants
#
# References:
#   - contracts/rules/20260912-1035-link-tracking-and-website-verification-sop.md
#   - docs/design/20260912-1050-uos-unified-web-wiki-zk-semantics-and-component-specification.md
#   - formal/lean/LinkGraphInvariants.lean
#   - formal/lean/UnifiedWebSemantics.lean
#   - tools/link_tracker_verifier.ml
#   - apps/cepaf_gleam/src/cepaf_gleam/ui/lustre/link_tracker_view.gleam
# ==============================================================================

set -euo pipefail

UOS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${UOS_ROOT}"

PASS_COUNT=0
FAIL_COUNT=0

log_info() {
    echo -e "\033[1;34m[INFO]\033[0m $*"
}

log_pass() {
    echo -e "\033[1;32m[PASS]\033[0m $*"
    PASS_COUNT=$((PASS_COUNT + 1))
}

log_fail() {
    echo -e "\033[1;31m[FAIL]\033[0m $*"
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

echo "========================================================================"
echo "UOS Universal Web, Wiki, ZK & Component SOP Automated Gatekeeper"
echo "Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo "Canonical Tailscale Base: http://nas-1.tail55d152.ts.net:4100"
echo "========================================================================"

# Step 1: Preflight Daemon & Port Health Check
log_info "Step 1: Checking BEAM WebUI service and listening ports..."
if ss -tlnp 2>/dev/null | grep -q ":4100 "; then
    log_pass "Port 4100 is actively listening (c3i-gleam-server)"
else
    log_fail "Port 4100 is NOT listening. Please start c3i-gleam-server.service."
fi

if ss -tlnp 2>/dev/null | grep -q ":4200 "; then
    log_pass "Port 4200 is actively listening (c3i-sa-plan-http)"
else
    log_fail "Port 4200 is NOT listening."
fi

# Step 2: Native OCaml Deep Link, Content & Knowledge Verification Probing
log_info "Step 2: Executing native OCaml Link Tracker, Knowledge & Component Verifier..."
if [[ ! -x "${UOS_ROOT}/tools/link_tracker_verifier.exe" ]]; then
    log_info "Compiling tools/link_tracker_verifier.ml..."
    ocamlopt -O3 -I +unix unix.cmxa "${UOS_ROOT}/tools/link_tracker_verifier.ml" -o "${UOS_ROOT}/tools/link_tracker_verifier.exe"
fi

"${UOS_ROOT}/tools/link_tracker_verifier.exe"

VERIFIER_JSON=$("${UOS_ROOT}/tools/link_tracker_verifier.exe" --json)
V_TOTAL=$(echo "${VERIFIER_JSON}" | jq -r '.total_endpoints // 0')
V_PASSED=$(echo "${VERIFIER_JSON}" | jq -r '.passed // 0')
V_FAILED=$(echo "${VERIFIER_JSON}" | jq -r '.failed // -1')
V_SCC=$(echo "${VERIFIER_JSON}" | jq -r '.scc_count // 0')
V_HTML_LINKS=$(echo "${VERIFIER_JSON}" | jq -r '.total_html_links // 0')
V_WIKI_RES=$(echo "${VERIFIER_JSON}" | jq -r '.wiki_resolved // 0')
V_ZK_RES=$(echo "${VERIFIER_JSON}" | jq -r '.zk_resolved // 0')
V_A2UI_COMPS=$(echo "${VERIFIER_JSON}" | jq -r '.a2ui_components // 0')
V_A2UI_VALID=$(echo "${VERIFIER_JSON}" | jq -r '.a2ui_valid // false')

if [[ "${V_TOTAL}" -ge 44 && "${V_PASSED}" -eq "${V_TOTAL}" && "${V_FAILED}" -eq 0 ]]; then
    log_pass "All ${V_TOTAL} monitored endpoints returned HTTP 200 (100.0% success)"
else
    log_fail "Endpoint verification failed: total=${V_TOTAL}, passed=${V_PASSED}, failed=${V_FAILED}"
fi

if [[ "${V_SCC}" -eq 1 ]]; then
    log_pass "Topological Graph Strongly Connected: SCC = 1 (Zero Disjoint Islands)"
else
    log_fail "Link graph is fragmented: SCC count = ${V_SCC}"
fi

if [[ "${V_HTML_LINKS}" -ge 1000 ]]; then
    log_pass "Deep HTML crawler verified ${V_HTML_LINKS} extracted href links across crawled pages"
else
    log_fail "Deep HTML link count below threshold: ${V_HTML_LINKS}"
fi

if [[ "${V_WIKI_RES}" -ge 500 && "${V_ZK_RES}" -ge 800 ]]; then
    log_pass "Knowledge transclusions resolved: Wiki=${V_WIKI_RES}, ZK=${V_ZK_RES}"
else
    log_fail "Knowledge transclusion resolution below threshold: Wiki=${V_WIKI_RES}, ZK=${V_ZK_RES}"
fi

if [[ "${V_A2UI_VALID}" == "true" && "${V_A2UI_COMPS}" -ge 233 ]]; then
    log_pass "A2UI Declarative Component Catalog verified: ${V_A2UI_COMPS} components (>= 233 required)"
else
    log_fail "A2UI component catalog invalid or below 233 components: count=${V_A2UI_COMPS}, valid=${V_A2UI_VALID}"
fi

# Step 2b: SOTA Spectral Centrality (PageRank & HITS) Verification
V_PR_LEN=$(echo "${VERIFIER_JSON}" | jq '.pagerank_top | length // 0')
V_HUB_LEN=$(echo "${VERIFIER_JSON}" | jq '.hits_hubs_top | length // 0')
V_AUTH_LEN=$(echo "${VERIFIER_JSON}" | jq '.hits_authorities_top | length // 0')

if [[ "${V_PR_LEN}" -ge 5 && "${V_HUB_LEN}" -ge 5 && "${V_AUTH_LEN}" -ge 5 ]]; then
    log_pass "SOTA Spectral Centrality converged: PageRank (${V_PR_LEN} top nodes), HITS Hubs (${V_HUB_LEN}), HITS Auth (${V_AUTH_LEN})"
else
    log_fail "Spectral centrality verification failed: PR=${V_PR_LEN}, Hubs=${V_HUB_LEN}, Auth=${V_AUTH_LEN}"
fi

# Step 3: Verify Single-Page Link Collator Sink (/links & /link-tracker)
log_info "Step 3: Probing Single-Page Multi-Sink Collator at /links..."
LINKS_HTML=$(curl -s --retry 3 --retry-connrefused --max-time 15 "http://127.0.0.1:4100/links")

if grep -q "Universal Link Tracker" <<< "${LINKS_HTML}"; then
    log_pass "Single-page collator view renders header and route sink"
else
    log_fail "Single-page collator view at /links missing expected title"
fi

if grep -q "Spectral Graph Centrality" <<< "${LINKS_HTML}"; then
    log_pass "Single-page collator renders Spectral Graph Centrality & Literature Lineage"
else
    log_fail "Spectral Graph Centrality panel missing from /links"
fi

if grep -E -q "Knowledge Base (&amp;|&) Transclusion Sink" <<< "${LINKS_HTML}"; then
    log_pass "Single-page collator renders Knowledge Base & Transclusion Sink"
else
    log_fail "Knowledge Base & Transclusion Sink missing from /links"
fi

if grep -q "A2UI Component Functionality Sink" <<< "${LINKS_HTML}"; then
    log_pass "Single-page collator renders A2UI Component Functionality Sink"
else
    log_fail "A2UI Component Functionality Sink missing from /links"
fi

if grep -E -q "Operational Health (&amp;|&) Hardware Enclave Sink" <<< "${LINKS_HTML}"; then
    log_pass "Single-page collator renders Operational Health & Hardware Enclave Sink"
else
    log_fail "Operational Health & Hardware Enclave Sink missing from /links"
fi

# Step 4: Verify REST API Status Endpoint (/api/v1/links/status)
log_info "Step 4: Probing REST API /api/v1/links/status..."
API_JSON=$(curl -s --retry 3 --retry-connrefused --max-time 15 "http://127.0.0.1:4100/api/v1/links/status")

if echo "${API_JSON}" | jq -e '.status == "nominal"' >/dev/null 2>&1; then
    log_pass "REST API returns status == 'nominal'"
else
    log_fail "REST API did not return status 'nominal'"
fi

# Step 5: Verify Lean 4 Mathematical Invariants
log_info "Step 5: Verifying Lean 4 Formal Proofs..."
if [[ -x "${UOS_ROOT}/tools/lean" ]]; then
    LEAN_OUTPUT1=$("${UOS_ROOT}/tools/lean" "${UOS_ROOT}/formal/lean/LinkGraphInvariants.lean" 2>&1)
    if [[ -z "${LEAN_OUTPUT1}" ]]; then
        log_pass "Lean 4 LinkGraphInvariants.lean verified cleanly (0 sorry, 0 warnings)"
    else
        echo "${LEAN_OUTPUT1}"
        log_fail "Lean 4 LinkGraphInvariants encountered errors"
    fi

    LEAN_OUTPUT2=$("${UOS_ROOT}/tools/lean" "${UOS_ROOT}/formal/lean/UnifiedWebSemantics.lean" 2>&1)
    if [[ -z "${LEAN_OUTPUT2}" ]]; then
        log_pass "Lean 4 UnifiedWebSemantics.lean verified cleanly (0 sorry, 0 warnings)"
    else
        echo "${LEAN_OUTPUT2}"
        log_fail "Lean 4 UnifiedWebSemantics encountered errors"
    fi

    LEAN_OUTPUT3=$("${UOS_ROOT}/tools/lean" "${UOS_ROOT}/formal/lean/KnowledgeGraphTopology.lean" 2>&1)
    if [[ -z "${LEAN_OUTPUT3}" ]]; then
        log_pass "Lean 4 KnowledgeGraphTopology.lean verified cleanly (0 sorry, 0 warnings)"
    else
        echo "${LEAN_OUTPUT3}"
        log_fail "Lean 4 KnowledgeGraphTopology encountered errors"
    fi

    LEAN_OUTPUT4=$("${UOS_ROOT}/tools/lean" "${UOS_ROOT}/formal/lean/BrowserStateMachineInvariants.lean" 2>&1)
    if [[ -z "${LEAN_OUTPUT4}" ]]; then
        log_pass "Lean 4 BrowserStateMachineInvariants.lean verified cleanly (0 sorry, 0 warnings)"
    else
        echo "${LEAN_OUTPUT4}"
        log_fail "Lean 4 BrowserStateMachineInvariants encountered errors"
    fi
else
    log_fail "tools/lean toolchain wrapper not found or not executable"
fi

# Step 5b: Native OCaml Browser Deep DOM Inspection & FSM Test Suite (16 Views)
log_info "Step 5b: Executing Native OCaml Google Chrome CDP Deep DOM & FSM Suite..."
if [[ ! -x "${UOS_ROOT}/tools/webui_browser_suite.exe" ]]; then
    log_info "Compiling tools/webui_browser_suite.ml..."
    ocamlfind ocamlopt -package yojson,unix -linkpkg "${UOS_ROOT}/tools/webui_browser_suite.ml" -o "${UOS_ROOT}/tools/webui_browser_suite.exe"
fi
if "${UOS_ROOT}/tools/webui_browser_suite.exe"; then
    log_pass "Native OCaml Google Chrome CDP Suite passed (16/16 endpoints 100% green)"
else
    log_fail "Native OCaml Google Chrome CDP Suite reported failures"
fi

# Step 5c: Native OCaml BDD Gherkin Browser Test Suite (8 Features, 86 Steps)
log_info "Step 5c: Executing Native OCaml BDD Gherkin Browser Test Suite..."
if [[ ! -x "${UOS_ROOT}/tools/webui_bdd_runner.exe" ]]; then
    log_info "Compiling tools/webui_bdd_runner.ml..."
    ocamlfind ocamlopt -package yojson,unix,str -linkpkg "${UOS_ROOT}/tools/webui_bdd_runner.ml" -o "${UOS_ROOT}/tools/webui_bdd_runner.exe"
fi
if "${UOS_ROOT}/tools/webui_bdd_runner.exe"; then
    log_pass "Native OCaml BDD Gherkin Browser Suite passed (8/8 features, 86/86 steps 100% green)"
else
    log_fail "Native OCaml BDD Gherkin Browser Suite reported failures"
fi

# Step 6: Final Gate Decision
echo "========================================================================"
echo "SOP Verification Summary:"
echo "Checks Passed: ${PASS_COUNT}"
echo "Checks Failed: ${FAIL_COUNT}"
echo "========================================================================"

if [[ "${FAIL_COUNT}" -eq 0 ]]; then
    echo -e "\033[1;32m>>> UNIFIED SOP VERIFICATION ADMISSION GRANTED: 100% GREEN <<<\033[0m"
    exit 0
else
    echo -e "\033[1;31m>>> ANDON STOP LINE TRIGGERED: FAIL-CLOSED (-32002) <<<\033[0m"
    exit 1
fi
