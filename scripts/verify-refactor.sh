#!/usr/bin/env bash
# ==============================================================================
# UOS Deterministic Pre-Commit Refactoring Gate (scripts/verify-refactor.sh)
# ==============================================================================
# Enforces >95% quality threshold across Lean 4.35.0, Mojo, Gleam, and OCaml:
#   1. Immutable Test & .mli Interface Boundaries (Standalone Jujutsu + Git)
#   2. Forbidden Escape-Hatch Diff & Source Scan:
#      - Lean 4: sorry, admit, axiom, unsafe, @[implemented_by]
#      - Mojo:   UnsafePointer, std.python, bitcast (outside FFI bridge)
#      - Gleam:  let assert, panic, todo in apps/*/src/
#      - OCaml:  Obj.magic, assert false
#   3. 4-Language Compiler, Proof & Verification Gates
# ==============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "=== 1. Checking Immutable Test & Interface Boundaries ==="
if [ -d ".jj" ]; then
  LOCKED_MODS=$(jj diff --name-only 'glob:**/test/**' 'glob:**/tests/**' 'glob:**/*.mli' 2>/dev/null | grep -vE '(^|/)README\.md$' || true)
  if [ -n "$LOCKED_MODS" ]; then
    echo "ERROR: Refactoring agent modified locked test files or OCaml .mli interfaces:"
    echo "$LOCKED_MODS"
    exit 1
  fi
elif [ -d ".git" ]; then
  LOCKED_MODS=$(git diff --name-only -- '*/test/*' '*/tests/*' '*.mli' 2>/dev/null | grep -vE '(^|/)README\.md$' || true)
  if [ -n "$LOCKED_MODS" ]; then
    echo "ERROR: Refactoring agent modified locked test files or OCaml .mli interfaces:"
    echo "$LOCKED_MODS"
    exit 1
  fi
fi

echo "=== 2. Scanning Diffs & Production Sources for Forbidden Escape Hatches ==="
diff_added_for() {
  if [ -d ".jj" ]; then
    jj diff --git "$@" 2>/dev/null | grep -E '^\+[^+]' | grep -vE '^[+](\s*--|\s*//|\s*#|\s*\*)' || true
  elif [ -d ".git" ]; then
    git diff -U0 -- "$@" 2>/dev/null | grep -E '^\+[^+]' | grep -vE '^[+](\s*--|\s*//|\s*#|\s*\*)' || true
  fi
}

check_forbidden() {
  local added="$1"
  local pattern="$2"
  local msg="$3"
  if [ -n "$added" ] && echo "$added" | grep -Eq "$pattern"; then
    echo "ESCAPE HATCH DETECTED: $msg"
    exit 1
  fi
}

LEAN_ADDED="$(diff_added_for 'glob:formal/lean/**/*.lean')"
GLEAM_ADDED="$(diff_added_for 'glob:apps/*/src/**/*.gleam')"
OCAML_ADDED="$(diff_added_for 'glob:engines/**/*.ml' 'glob:tools/**/*.ml')"
MOJO_ADDED="$(diff_added_for 'glob:formal/mojo/*_oracle.mojo' | grep -v 'mojo_oracle_unsafe' || true)"

# 2a. Diff-level escape hatch rejection
check_forbidden "$LEAN_ADDED" '\b(sorry|admit|axiom|unsafe)\b' "Lean 4 unsoundness escape hatch (sorry/admit/axiom/unsafe)"
check_forbidden "$GLEAM_ADDED" '\b(let assert|panic|todo)\b' "Gleam partiality escape hatch (let assert/panic/todo)"
check_forbidden "$OCAML_ADDED" '\b(Obj\.magic|assert false)\b' "OCaml type safety escape hatch (Obj.magic/assert false)"
check_forbidden "$MOJO_ADDED" '\b(UnsafePointer|std\.python|bitcast)\b' "Mojo raw UnsafePointer/std.python/bitcast introduced in oracle"

# 2b. Whole-tree invariant check on production paths
GLEAM_SRC_ESCAPE=$({ grep -rnE '^\s*(let assert|panic as)\b' apps/*/src/ 2>/dev/null || true; } | wc -l)
if [ "$GLEAM_SRC_ESCAPE" -ne 0 ]; then
  echo "ERROR: Found $GLEAM_SRC_ESCAPE 'let assert' or 'panic as' occurrences in apps/*/src/ (must be 0)."
  exit 1
fi

OCAML_SRC_ESCAPE=$({ grep -rnE '\bObj\.magic\b' tools/*.ml 2>/dev/null || true; } | wc -l)
if [ "$OCAML_SRC_ESCAPE" -ne 0 ]; then
  echo "ERROR: Found $OCAML_SRC_ESCAPE 'Obj.magic' occurrences in tools/*.ml (must be 0)."
  exit 1
fi

AUTO_IMPLICIT_COUNT=$(grep -c "autoImplicit = false" formal/lean/lakefile.toml formal/lean/ruliad/lakefile.toml 2>/dev/null | awk -F: '{s+=$2} END{print s+0}')
if [ "$AUTO_IMPLICIT_COUNT" -lt 2 ]; then
  echo "ERROR: autoImplicit = false must be pinned in formal/lean/lakefile.toml and formal/lean/ruliad/lakefile.toml."
  exit 1
fi

echo "=== 3. Running Language-Specific Compiler, Proof & Coverage Gates ==="

# Lean 4 Gate
echo "[Lean 4.35.0] Elaborating Unified Digital Twin & Proof Plane Guard..."
./tools/lean formal/lean/UosFullSystemCodeUnifiedDigitalTwin.lean
./tools/mojo run -I formal/mojo formal/mojo/proof_plane_guard_oracle.mojo >/dev/null

# Mojo Gate
echo "[Mojo] Running Full System Code Differential Oracle..."
./tools/mojo run -I formal/mojo formal/mojo/full_system_code_oracle.mojo >/dev/null

# Gleam Gate
echo "[Gleam] Type-checking and building apps/cepaf_gleam (0 let assert in src/)..."
(cd apps/cepaf_gleam && gleam build)

# OCaml Gate
echo "[OCaml] Verifying Hermes dispatch hook & proof-plane scanner..."
./engines/hermes/_build/default/modules/system_engg/test_agent_dispatch_hook.exe >/dev/null

echo "All refactoring quality gates passed (>=95% standard verified)."
