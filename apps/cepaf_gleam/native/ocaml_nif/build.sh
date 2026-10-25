#!/usr/bin/env bash
# Builds priv/c3i_ocaml_nif.so from this directory's sources with in-project
# toolchains only (SC-NIX-DEVENV-001): OCaml from toolchains/opam-ocaml via the
# resolver, ERTS headers from the pinned OTP 29 erl. The C compiler/linker is the
# host cc, the same linker the Rust NIF builds use; the resolver has no C entry.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRIV_DIR="${SCRIPT_DIR}/../../priv"
UOS_ROOT="${UOS_ROOT:-/home/an/NAS-setup/uos}"
mkdir -p "${PRIV_DIR}"

# shellcheck source=/dev/null
source "${UOS_ROOT}/tools/lib/uos-toolchain.sh"
uos_env

OCAMLLIB="$(ocamlopt -where)"
ERL_INCLUDE="$(erl -noshell -eval 'io:format("~s/erts-~s/include",[code:root_dir(),erlang:system_info(version)]),halt().')"
case "${OCAMLLIB}" in "${UOS_ROOT}"/toolchains/*) ;; *) echo "ocamlopt outside in-project toolchain: ${OCAMLLIB}" >&2; exit 1 ;; esac
case "${ERL_INCLUDE}" in /nix/store/*erlang-29*) ;; *) echo "ERTS headers are not the pinned OTP 29: ${ERL_INCLUDE}" >&2; exit 1 ;; esac

BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "${BUILD_DIR}"' EXIT

echo "[c3i_ocaml_nif] Compiling OCaml bridge with threads.cmxa..."
cp "${SCRIPT_DIR}/c3i_ocaml_bridge.ml" "${BUILD_DIR}/"
(cd "${BUILD_DIR}" && ocamlopt -I +unix -I +threads unix.cmxa threads.cmxa \
    -output-complete-obj -runtime-variant _pic \
    -o c3i_ocaml_substrate.o c3i_ocaml_bridge.ml)

echo "[c3i_ocaml_nif] Compiling and linking C NIF shared object..."
cc -fPIC -shared -O2 \
    -I"${ERL_INCLUDE}" \
    -I"${OCAMLLIB}" \
    "${SCRIPT_DIR}/c3i_ocaml_nif.c" "${BUILD_DIR}/c3i_ocaml_substrate.o" \
    -L"${OCAMLLIB}" -lthreadsnat \
    -o "${PRIV_DIR}/c3i_ocaml_nif.so" \
    -ldl -lm -lpthread

echo "[c3i_ocaml_nif] Successfully built ${PRIV_DIR}/c3i_ocaml_nif.so"
ls -lh "${PRIV_DIR}/c3i_ocaml_nif.so"
