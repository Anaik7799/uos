#!/usr/bin/env bash
# TEST ONLY: Pinned build recipe/runner for telegram store recovery fixtures
# Spec: uos.telegram-durable-store-corrected-development-spec.v1
# Plan: uos/telegram-runtime/20261001-1150
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

source tools/lib/uos-toolchain.sh
uos_env

OCAML="$(uos_tool_path ocaml)"
echo "=== Building Telegram Store Recovery Fixtures via Bounded OCaml Builder ==="
"$OCAML" tools/validation/telegram_store_recovery_build.ml
