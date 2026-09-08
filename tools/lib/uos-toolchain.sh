#!/usr/bin/env bash
# =============================================================================
# UOS in-project toolchain resolver (SC-TOOLCHAIN-INPROJECT-001)
# -----------------------------------------------------------------------------
# Operator mandate (2026-09-08): "all tool chain must be in uos project".
# Every toolchain entrypoint MUST resolve inside $UOS_ROOT. Nothing here may
# point at $HOME, /tmp, or an external evidence tree (/home/an/dev/ver/*):
# tmpfs is volatile and external trees are read-only evidence, not runtime deps.
#
# Pinned by governance/sources/20260908-2016-formal-toolchain-in-project-installation.json
#
# Usage:  source "$(dirname "$0")/lib/uos-toolchain.sh"
#         uos_tool lean   -> absolute path, or exits non-zero if absent
#         uos_have lean   -> 0 if runnable, 1 if absent (never fabricates)
# =============================================================================
set -euo pipefail

# Resolve UOS_ROOT from this file's own location (repo-relative, no absolutes).
UOS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export UOS_ROOT

UOS_TOOLCHAIN_DIR="$UOS_ROOT/formal/.toolchain"
export UOS_TOOLCHAIN_DIR

# --- entrypoint table -------------------------------------------------------
uos_tool_path() {
  case "$1" in
    lean)       printf '%s\n' "$UOS_TOOLCHAIN_DIR/lean-4.33.0/bin/lean" ;;
    lake)       printf '%s\n' "$UOS_TOOLCHAIN_DIR/lean-4.33.0/bin/lake" ;;
    leanc)      printf '%s\n' "$UOS_TOOLCHAIN_DIR/lean-4.33.0/bin/leanc" ;;
    z3)         printf '%s\n' "$UOS_TOOLCHAIN_DIR/z3/z3" ;;
    quint-eval) printf '%s\n' "$UOS_TOOLCHAIN_DIR/quint-0.6.0/quint_evaluator" ;;
    pixi)       printf '%s\n' "$UOS_TOOLCHAIN_DIR/pixi/bin/pixi" ;;
    mojo)       printf '%s\n' "$UOS_ROOT/services/inference/max/.pixi/envs/default/bin/mojo" ;;
    *)          return 1 ;;
  esac
}

# uos_have <name> -- true only if the entrypoint exists AND is executable.
# Absence is reported honestly; callers must fail closed, never substitute.
uos_have() {
  local p
  p="$(uos_tool_path "$1")" || return 1
  [ -x "$p" ]
}

# uos_tool <name> -- print the path, or fail loudly with a fix hint.
uos_tool() {
  local p
  if ! p="$(uos_tool_path "$1")"; then
    echo "uos-toolchain: unknown toolchain '$1'" >&2
    return 2
  fi
  if [ ! -x "$p" ]; then
    echo "uos-toolchain: '$1' is NOT installed in-project at $p" >&2
    echo "uos-toolchain: see governance/sources/20260908-2016-formal-toolchain-in-project-installation.json" >&2
    return 3
  fi
  printf '%s\n' "$p"
}

# uos_toolchain_report -- availability matrix; the honest probe used by doctor.
uos_toolchain_report() {
  local name p status
  printf '%-12s %-8s %s\n' TOOLCHAIN STATUS PATH
  for name in lean lake z3 quint-eval pixi mojo; do
    p="$(uos_tool_path "$name")"
    if [ -x "$p" ]; then status=PRESENT; else status=ABSENT; fi
    printf '%-12s %-8s %s\n' "$name" "$status" "${p#$UOS_ROOT/}"
  done
}
