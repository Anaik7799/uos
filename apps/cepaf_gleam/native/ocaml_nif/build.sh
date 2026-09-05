#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRIV_DIR="${SCRIPT_DIR}/../../priv"
mkdir -p "${PRIV_DIR}"

eval $(~/.local/bin/opam env --switch=/home/an/dev/ver/zigvm --set-switch)
OCAMLLIB="$(ocamlopt -where)"
ERL_INCLUDE="/usr/lib/erlang/usr/include"

echo "[c3i_ocaml_nif] Compiling OCaml bridge with threads.cmxa..."
cd "${SCRIPT_DIR}"
ocamlopt -I +unix -I +threads unix.cmxa threads.cmxa \
    -output-complete-obj -runtime-variant _pic \
    -o c3i_ocaml_substrate.o c3i_ocaml_bridge.ml

echo "[c3i_ocaml_nif] Compiling and linking C NIF shared object..."
gcc -fPIC -shared -O2 \
    -I"${ERL_INCLUDE}" \
    -I"${OCAMLLIB}" \
    c3i_ocaml_nif.c c3i_ocaml_substrate.o \
    -L"${OCAMLLIB}" -lthreadsnat \
    -o "${PRIV_DIR}/c3i_ocaml_nif.so" \
    -ldl -lm -lpthread

echo "[c3i_ocaml_nif] Successfully built ${PRIV_DIR}/c3i_ocaml_nif.so"
ls -lh "${PRIV_DIR}/c3i_ocaml_nif.so"
