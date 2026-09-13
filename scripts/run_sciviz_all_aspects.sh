#!/usr/bin/env bash
# ==============================================================================
# Unified Operational System (UOS)
# SciViz & 167 Extensions Comprehensive Multi-Aspect Test Runner
#
# Contracts: SC-GLM-UI-001, SC-CHECKLIST-001, SC-MUDA-001, SC-ZMOF-001
# Technology: OCaml 5.5 Native CDP Runner (Zero Node.js / Zero Playwright)
# 
# Usage:
#   ./scripts/run_sciviz_all_aspects.sh [OPTIONS]
#
# Modes:
#   --all                  Run all 5 SciViz features (15..19, 542 scenarios)
#   --feature <15..19>     Run a specific feature file
#   --tag <@tag>           Run scenarios matching tag (e.g. @visual-parity)
#   --filter <query>       Run scenarios matching text filter
#   --category "<name>"    Run scenarios matching taxonomic category
#   --modality "<name>"    Run scenarios matching formal verification modality
#   --matrix               Run coverage matrix generator and display summary
#   --5domains             Run 5-domain canonical verification script
#   --full-cycle           Run complete end-to-end cycle (matrix + tests + 5domains)
#   --report <path>        Custom JSON report destination
#   --help                 Display this help synopsis
# ==============================================================================
set -euo pipefail

UOS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$UOS_ROOT"

# Ensure in-project toolchain is in environment
if [ -f "tools/lib/uos-toolchain.sh" ]; then
  # shellcheck source=/dev/null
  source tools/lib/uos-toolchain.sh && uos_env >/dev/null 2>&1 || true
fi

RUNNER_BIN="tools/webui_bdd_runner.exe"
REPORT_DEST="var/bdd_sciviz_report.json"
FEATURE_DIR="test/features"

# Feature files mapping
FEAT_15="$FEATURE_DIR/15_sciviz_167_card_visual_parity.feature"
FEAT_16="$FEATURE_DIR/16_sciviz_167_features_offered.feature"
FEAT_17="$FEATURE_DIR/17_sciviz_167_fractal_specifications.feature"
FEAT_18="$FEATURE_DIR/18_sciviz_categories_and_modalities.feature"
FEAT_19="$FEATURE_DIR/19_sciviz_cockpit_and_dsl_invariants.feature"
FEAT_20="$FEATURE_DIR/20_sciviz_comprehensive_deep_dive.feature"
ALL_SCIVIZ_FEATS=("$FEAT_15" "$FEAT_16" "$FEAT_17" "$FEAT_18" "$FEAT_19" "$FEAT_20")

print_banner() {
  echo "==============================================================================="
  echo "    SCIVIZ & 167 EXTENSIONS COMPREHENSIVE MULTI-ASPECT RUNNER (569 TESTS)      "
  echo "   Zero-Muda Pure OCaml Native CDP Browser Runner (Zero Playwright/Node.js)    "
  echo "==============================================================================="
}

show_help() {
  print_banner
  cat << 'HELP_EOF'

SYNOPSIS:
  ./scripts/run_sciviz_all_aspects.sh [MODE] [OPTIONS]

AVAILABLE MODES:
  --all                  Execute all 5 SciViz feature suites (542 scenarios, 1,623 steps):
                           - Feature 15: Visual parity & layout for all 167 extensions
                           - Feature 16: Features offered, algorithms & interactive controls
                           - Feature 17: 1x1 specifications, fractal layers & author attribution
                           - Feature 18: Taxonomic categories (16) & verification modalities (9)
                           - Feature 19: Cockpit navigation, SVG rendering & SIL-6 invariants
  --feature <ID|PATH>    Execute a single feature file (e.g. 15, 16, 17, 18, 19)
  --tag <@tag>           Execute scenarios matching Gherkin tag:
                           @visual-parity, @features-offered, @fractal-specifications,
                           @categories-and-modalities, @cockpit-navigation
  --category "<NAME>"    Execute scenarios matching category (e.g. "Quantum Computing",
                           "Bioinformatics", "Neuroimaging", "Genomics", "Astrophysics")
  --modality "<NAME>"    Execute scenarios matching modality (e.g. "Formal Model Checking",
                           "Visual Parity", "Differential Parity", "Invariant Assertion")
  --filter "<TEXT>"      Arbitrary scenario name substring filter
  --matrix               Generate & print SciViz 167-extension complete coverage matrix
  --5domains             Execute 5-Domain canonical verification evaluator (18/18 checks)
  --full-cycle           Execute Matrix Generator -> 542 Scenarios -> 5-Domain Verifier
  --help                 Show this help screen

OPTIONS:
  --report <FILE>        Specify destination for JSON execution receipt (default: var/bdd_sciviz_report.json)

EXAMPLES:
  # Run entire 542-test SciViz BDD suite
  ./scripts/run_sciviz_all_aspects.sh --all

  # Run only Visual Parity feature across 167 extensions
  ./scripts/run_sciviz_all_aspects.sh --feature 15

  # Run all scenarios tagged with @features-offered
  ./scripts/run_sciviz_all_aspects.sh --tag @features-offered

  # Run scenarios covering "Quantum Computing" category
  ./scripts/run_sciviz_all_aspects.sh --category "Quantum Computing"

  # Run complete verification cycle with 5-domain evaluation
  ./scripts/run_sciviz_all_aspects.sh --full-cycle

HELP_EOF
}

check_preflight() {
  # 1. Verify runner binary exists and is executable
  if [ ! -x "$RUNNER_BIN" ]; then
    echo "[PREFLIGHT] Compiling $RUNNER_BIN via in-project OCaml 5.5..."
    source tools/lib/uos-toolchain.sh && uos_env
    ocamlfind ocamlopt -package unix,yojson -linkpkg -o "$RUNNER_BIN" tools/webui_bdd_runner.ml
  fi

  # 2. Check BEAM WebUI health on port 4100
  if ! curl -s -f http://127.0.0.1:4100/health >/dev/null 2>&1 && \
     ! curl -s http://127.0.0.1:4100/sciviz | grep -q "SciViz" 2>/dev/null; then
    echo -e "\033[31m[ERROR]\033[0m BEAM WebUI service is not responding on port 4100."
    echo "        Please start the server with: (cd apps/cepaf_gleam && gleam run) or tools/uos start"
    exit 1
  fi
}

run_matrix() {
  echo ""
  echo ">>> [ASPECT: COVERAGE MATRIX] Generating 167-Extension Coverage Matrix..."
  python3 tools/sciviz_coverage_matrix_generator.py
}

run_5domains() {
  echo ""
  echo ">>> [ASPECT: 5-DOMAIN VERIFICATION] Executing Canonical Verification Checks..."
  bash scripts/verify_sciviz_5domains.sh
}

# Parse Command Line Arguments
MODE="help"
SELECTED_FEATS=()
EXTRA_ARGS=()

if [ $# -eq 0 ]; then
  show_help
  exit 0
fi

while [ $# -gt 0 ]; do
  case "$1" in
    --all)
      MODE="all"
      SELECTED_FEATS=("${ALL_SCIVIZ_FEATS[@]}")
      shift
      ;;
    --feature)
      MODE="feature"
      FEAT_ARG="$2"
      case "$FEAT_ARG" in
        15) SELECTED_FEATS=("$FEAT_15") ;;
        16) SELECTED_FEATS=("$FEAT_16") ;;
        17) SELECTED_FEATS=("$FEAT_17") ;;
        18) SELECTED_FEATS=("$FEAT_18") ;;
        19) SELECTED_FEATS=("$FEAT_19") ;;
        *)
          if [ -f "$FEAT_ARG" ]; then
            SELECTED_FEATS=("$FEAT_ARG")
          elif [ -f "$FEATURE_DIR/$FEAT_ARG" ]; then
            SELECTED_FEATS=("$FEATURE_DIR/$FEAT_ARG")
          else
            echo -e "\033[31m[ERROR]\033[0m Unknown feature: $FEAT_ARG"
            exit 1
          fi
          ;;
      esac
      shift 2
      ;;
    --tag)
      MODE="filtered"
      EXTRA_ARGS+=("--tag" "$2")
      if [ ${#SELECTED_FEATS[@]} -eq 0 ]; then
        SELECTED_FEATS=("${ALL_SCIVIZ_FEATS[@]}")
      fi
      shift 2
      ;;
    --category)
      MODE="filtered"
      EXTRA_ARGS+=("--filter" "$2")
      if [ ${#SELECTED_FEATS[@]} -eq 0 ]; then
        SELECTED_FEATS=("${ALL_SCIVIZ_FEATS[@]}")
      fi
      shift 2
      ;;
    --modality)
      MODE="filtered"
      EXTRA_ARGS+=("--filter" "$2")
      if [ ${#SELECTED_FEATS[@]} -eq 0 ]; then
        SELECTED_FEATS=("${ALL_SCIVIZ_FEATS[@]}")
      fi
      shift 2
      ;;
    --filter)
      MODE="filtered"
      EXTRA_ARGS+=("--filter" "$2")
      if [ ${#SELECTED_FEATS[@]} -eq 0 ]; then
        SELECTED_FEATS=("${ALL_SCIVIZ_FEATS[@]}")
      fi
      shift 2
      ;;
    --matrix)
      MODE="matrix"
      shift
      ;;
    --5domains)
      MODE="5domains"
      shift
      ;;
    --full-cycle)
      MODE="full-cycle"
      SELECTED_FEATS=("${ALL_SCIVIZ_FEATS[@]}")
      shift
      ;;
    --report)
      REPORT_DEST="$2"
      shift 2
      ;;
    --help|-h)
      show_help
      exit 0
      ;;
    *)
      echo -e "\033[31m[ERROR]\033[0m Unknown argument: $1"
      show_help
      exit 1
      ;;
  esac
done

print_banner
check_preflight

case "$MODE" in
  matrix)
    run_matrix
    ;;
  5domains)
    run_5domains
    ;;
  full-cycle)
    run_matrix
    echo ""
    echo ">>> [ASPECT: BDD GHERKIN HARNESS] Executing All 542 Scenarios Across 5 Suites..."
    mkdir -p "$(dirname "$REPORT_DEST")"
    "$RUNNER_BIN" "${SELECTED_FEATS[@]}" --report "$REPORT_DEST"
    run_5domains
    echo ""
    echo "==============================================================================="
    echo "  FULL CYCLE COMPLETE: MATRIX + 542 BDD TESTS + 5 DOMAINS (18/18 CHECKS) PASS "
    echo "==============================================================================="
    ;;
  all|feature|filtered)
    echo ""
    echo ">>> [ASPECT: BDD GHERKIN HARNESS] Executing Selected Suites..."
    mkdir -p "$(dirname "$REPORT_DEST")"
    "$RUNNER_BIN" "${SELECTED_FEATS[@]}" "${EXTRA_ARGS[@]}" --report "$REPORT_DEST"
    ;;
esac
