#!/usr/bin/env bash
# =============================================================================
# UOS in-project toolchain resolver (SC-TOOLCHAIN-INPROJECT-001)
# -----------------------------------------------------------------------------
# Operator mandate (2026-09-08): "all tool chain must be in uos project".
# Every toolchain entrypoint MUST resolve inside $UOS_ROOT. Nothing here may
# point at $HOME, /nix/store, /usr, /tmp, or an external evidence tree
# (/home/an/dev/ver/*): tmpfs is volatile, /usr is not ours to pin, and external
# trees are read-only evidence under canonical policy section 3, not runtime
# dependencies.
#
# BEAM policy (operator directive, 2026-09-08): UOS runs on OTP 29 ONLY. The
# host's OTP 27 and the zigvm tree's vendored OTP-30 artifacts are both barred.
#
# Pinned by governance/sources/20260908-2016-formal-toolchain-in-project-installation.json
#
# Usage:  source "$(dirname "$0")/lib/uos-toolchain.sh"
#         uos_tool gleam   -> absolute path, or non-zero exit if absent
#         uos_have gleam   -> 0 if runnable, 1 if absent (never fabricates)
#         uos_env          -> exports PATH/ERL_TOP/etc for an in-project shell
# =============================================================================
# Resolve this file's own location portably. bash exposes BASH_SOURCE; zsh -- the
# operator's login shell -- does not, and exposes ${(%):-%x} instead. Getting this
# wrong is not a cosmetic failure: an unset BASH_SOURCE under `set -u` aborts the
# source, and without `set -u` UOS_ROOT silently becomes a parent of $PWD, so every
# entrypoint below resolves to a path that does not exist while uos_have() reports
# a truthful-looking ABSENT for a toolchain that is in fact installed.
if [ -n "${BASH_SOURCE:-}" ]; then
  _uos_self="${BASH_SOURCE[0]}"
  _uos_sourced=0
  [ "${BASH_SOURCE[0]}" != "$0" ] && _uos_sourced=1
elif [ -n "${ZSH_VERSION:-}" ]; then
  eval '_uos_self="${(%):-%x}"'
  _uos_sourced=1
else
  _uos_self="$0"
  _uos_sourced=0
fi

# Harden only when EXECUTED. `set -e` leaking into an operator's interactive shell
# would terminate the session on the first failed command; every tools/* wrapper
# already sets its own `set -euo pipefail` before sourcing this library.
[ "$_uos_sourced" = 1 ] || set -euo pipefail

UOS_ROOT="$(cd "$(dirname "$_uos_self")/../.." && pwd)"
unset _uos_self _uos_sourced
export UOS_ROOT
UOS_TC="$UOS_ROOT/toolchains"
export UOS_TC

uos_tool_path() {
  case "$1" in
    # --- BEAM (OTP 29 only) ---
    # OTP 29 ONLY (SC-NIX-DEVENV-001), from the Determinate Nix profile.
    erl)        printf '%s\n' "$UOS_TC/nix-profile/bin/erl" ;;
    erlc)       printf '%s\n' "$UOS_TC/nix-profile/bin/erlc" ;;
    escript)    printf '%s\n' "$UOS_TC/nix-profile/bin/escript" ;;
    gleam)      printf '%s\n' "$UOS_TC/gleam-1.16.0/bin/gleam" ;;
    rebar3)     printf '%s\n' "$UOS_TC/nix-profile/bin/rebar3" ;;
    # --- systems ---
    zig)        printf '%s\n' "$UOS_TC/nix-profile/bin/zig" ;;
    cargo)      printf '%s\n' "$UOS_TC/cargo/bin/cargo" ;;
    rustc)      printf '%s\n' "$UOS_TC/cargo/bin/rustc" ;;
    rustup)     printf '%s\n' "$UOS_TC/cargo/bin/rustup" ;;
    # --- OCaml / Hermes ---
    ocaml)      printf '%s\n' "$UOS_TC/opam-ocaml/bin/ocaml" ;;
    ocamlfind)  printf '%s\n' "$UOS_TC/opam-ocaml/bin/ocamlfind" ;;
    dune)       printf '%s\n' "$UOS_TC/opam-ocaml/bin/dune" ;;
    # --- formal ---
    lean)       printf '%s\n' "$UOS_TC/lean-4.33.0/bin/lean" ;;
    lake)       printf '%s\n' "$UOS_TC/lean-4.33.0/bin/lake" ;;
    leanc)      printf '%s\n' "$UOS_TC/lean-4.33.0/bin/leanc" ;;
    z3)         printf '%s\n' "$UOS_TC/nix-profile/bin/z3" ;;
    quint)      printf '%s\n' "$UOS_TC/nix-profile/bin/quint" ;;
    # --- inference / js ---
    pixi)       printf '%s\n' "$UOS_TC/pixi/bin/pixi" ;;
    mojo)       printf '%s\n' "$UOS_ROOT/services/inference/max/.pixi/envs/default/bin/mojo" ;;
    node)       printf '%s\n' "$UOS_TC/node-22/bin/node" ;;
    npm)        printf '%s\n' "$UOS_TC/node-22/bin/npm" ;;
    *)          return 1 ;;
  esac
}

# True only if the entrypoint exists AND is executable. Absence is reported
# honestly; callers must fail closed, never substitute a host binary.
uos_have() {
  local p
  p="$(uos_tool_path "$1")" || return 1
  [ -x "$p" ]
}

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

# Export an in-project environment. Deliberately PREPENDS, and pins the BEAM and
# OCaml roots, so a stray host erl/ocaml cannot win a PATH race.
uos_env() {
  export PATH="$UOS_TC/nix-profile/bin:$UOS_TC/gleam-1.16.0/bin:$UOS_TC/opam-ocaml/bin:$UOS_TC/lean-4.33.0/bin:$UOS_TC/cargo/bin:$UOS_TC/node-22/bin:$PATH"
  export OPAM_SWITCH_PREFIX="$UOS_TC/opam-ocaml"
  export CARGO_HOME="$UOS_TC/cargo"
  export RUSTUP_HOME="$UOS_TC/rustup"
  # Keep build caches inside the project too, so a wiped $HOME cannot change a build.
  export ZIG_GLOBAL_CACHE_DIR="$UOS_TC/.cache/zig"
  mkdir -p "$ZIG_GLOBAL_CACHE_DIR"
}

UOS_ALL_TOOLS="erl erlc escript gleam rebar3 zig cargo rustc ocaml ocamlfind dune lean lake z3 quint pixi mojo node npm"

uos_toolchain_report() {
  local name p status
  printf '%-12s %-8s %s\n' TOOLCHAIN STATUS PATH
  for name in $UOS_ALL_TOOLS; do
    p="$(uos_tool_path "$name")"
    if [ -x "$p" ]; then status=PRESENT; else status=ABSENT; fi
    printf '%-12s %-8s %s\n' "$name" "$status" "${p#$UOS_ROOT/}"
  done
}
