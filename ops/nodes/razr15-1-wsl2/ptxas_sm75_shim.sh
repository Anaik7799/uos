#!/usr/bin/env bash
set -euo pipefail

# Atomic Temp-File PTX Lowering & Register Cap Wrapper for Turing sm_75 (RTX 2070 Max-Q)
# - Avoids in-place mutation of caller .ptx artifacts by rewriting into a mktemp copy
# - Lowers PTX ISA .version 8.[4-9] -> .version 8.3 and .target sm_8[0-9] -> .target sm_75
# - Rewrites -arch sm_80 -> -arch sm_75 and enforces --maxrregcount 128 for 64K SM register file

tmp_files=()
cleanup() {
  if (( ${#tmp_files[@]} > 0 )); then
    rm -f "${tmp_files[@]}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

rewritten_args=()
has_maxrregcount=0

while (( $# > 0 )); do
  arg="$1"
  shift
  if [[ "$arg" == "--maxrregcount" || "$arg" == "-maxrregcount" ]]; then
    has_maxrregcount=1
    rewritten_args+=("$arg")
    if (( $# > 0 )); then
      rewritten_args+=("$1")
      shift
    fi
  elif [[ "$arg" == "--gpu-name" || "$arg" == "-arch" ]]; then
    rewritten_args+=("$arg")
    if (( $# > 0 )); then
      arch_val="$1"
      shift
      if [[ "$arch_val" == sm_8* || "$arch_val" == sm_9* ]]; then
        rewritten_args+=("sm_75")
      else
        rewritten_args+=("$arch_val")
      fi
    fi
  elif [[ "$arg" == *.ptx && -f "$arg" ]]; then
    tmp_ptx="$(mktemp /tmp/uos_sm75_XXXXXX.ptx)"
    tmp_files+=("$tmp_ptx")
    sed -E \
      -e 's/\.version 8\.[4-9]/.version 8.3/g' \
      -e 's/\.target sm_8[0-9]/.target sm_75/g' \
      "$arg" > "$tmp_ptx"
    rewritten_args+=("$tmp_ptx")
  else
    rewritten_args+=("$arg")
  fi
done

if (( has_maxrregcount == 0 )); then
  rewritten_args+=("--maxrregcount" "128")
fi

PTXAS_BIN="/home/an/cuda123/.pixi/envs/default/bin/ptxas"
if [[ ! -x "$PTXAS_BIN" ]]; then
  PTXAS_BIN="/usr/local/cuda/bin/ptxas"
fi

exec "$PTXAS_BIN" "${rewritten_args[@]}"
