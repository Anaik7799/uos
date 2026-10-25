#!/usr/bin/env bash
# SC-HARNESS-MCP-001 / SC-OBSERVER-001: Pinned reproducible clean-checkout builder
# for sa_plan_observer.exe and obs_guardian.exe.
# Spec: uos.telegram-observer-candidate.v1
# Plan: uos/telegram-runtime/20261001-1150
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

source tools/lib/uos-toolchain.sh
uos_env

OCAMLFIND="$(uos_tool_path ocamlfind)"

# Upstream pinned source hashes
EXPECTED_PRIORITY_SHA="86c2138c2a149908b05466f2c9befcafe13e414a8ab4405229ac152655b3b724"
EXPECTED_BOUNDED_SHA="fd78167db257d863415ea9ceb6399662e2ce24b46cc15a7b0cc04ea57e23b13f"
EXPECTED_LIVE_PLAN_SHA="7f83f174d6b384f42d1983ed0e21b63f15fad4bbaed72938186b98da4644a3f6"
EXPECTED_OBSERVER_SRC_SHA="b0f443e62e3bbd5504900616c5c2810e054e4fe2bd671f1824d36f8889ae203b"
EXPECTED_GUARDIAN_SRC_SHA="4ddae78d954989511c79196ab5d508ab362c2cf4efa704eb9950603c70be58e4"

# Target pinned binary hashes
EXPECTED_OBSERVER_BIN_SHA="5b9dab694c7486f39decb0f3db4238b74753941a659106d5e12fee3c0fe656e2"
EXPECTED_GUARDIAN_BIN_SHA="b7bab1a85ffa3689a2548ff28a391e659c0537104dec7be0f774bae1820ec4be"

check_sha() {
  local file="$1"
  local expected="$2"
  local actual
  actual="$(sha256sum "$file" | awk '{print $1}')"
  if [[ "$actual" != "$expected" ]]; then
    echo "ERROR: Source checksum mismatch for $file: got $actual, expected $expected" >&2
    exit 1
  fi
}

check_sha "plugins/uos-risk-prioritization/validation/priority.ml" "$EXPECTED_PRIORITY_SHA"
check_sha "plugins/uos-risk-prioritization/validation/bounded.ml" "$EXPECTED_BOUNDED_SHA"
check_sha "plugins/uos-risk-prioritization/validation/live_plan.ml" "$EXPECTED_LIVE_PLAN_SHA"
check_sha "tools/validation/sa_plan_observer.ml" "$EXPECTED_OBSERVER_SRC_SHA"
check_sha "tools/validation/obs_guardian.ml" "$EXPECTED_GUARDIAN_SRC_SHA"

TMP_BUILD="$(mktemp -d "${TMPDIR:-/tmp}/uos-observer-build.XXXXXX")"
trap 'rm -rf -- "$TMP_BUILD"' EXIT

SRC_DIR="$TMP_BUILD/src"
mkdir -p "$SRC_DIR"

cp "plugins/uos-risk-prioritization/validation/priority.ml" "$SRC_DIR/"
cp "plugins/uos-risk-prioritization/validation/bounded.ml" "$SRC_DIR/"
cp "plugins/uos-risk-prioritization/validation/live_plan.ml" "$SRC_DIR/"
cp "tools/validation/sa_plan_observer.ml" "$SRC_DIR/"
cp "tools/validation/obs_guardian.ml" "$SRC_DIR/"

cd "$SRC_DIR"

# 1. Compile sa_plan_observer.exe
"$OCAMLFIND" ocamlopt -linkpkg -package yojson,unix,cryptokit,sqlite3 \
  priority.ml bounded.ml live_plan.ml sa_plan_observer.ml \
  -o "$TMP_BUILD/sa_plan_observer.exe"

# 2. Compile obs_guardian.exe
"$OCAMLFIND" ocamlopt -linkpkg -package unix,cryptokit,mtime.clock.os \
  obs_guardian.ml \
  -o "$TMP_BUILD/obs_guardian.exe"

cd "$REPO_ROOT"

ACTUAL_OBSERVER_BIN_SHA="$(sha256sum "$TMP_BUILD/sa_plan_observer.exe" | awk '{print $1}')"
ACTUAL_GUARDIAN_BIN_SHA="$(sha256sum "$TMP_BUILD/obs_guardian.exe" | awk '{print $1}')"

if [[ "$ACTUAL_OBSERVER_BIN_SHA" != "$EXPECTED_OBSERVER_BIN_SHA" ]]; then
  echo "ERROR: Built sa_plan_observer.exe mismatch: got $ACTUAL_OBSERVER_BIN_SHA, expected $EXPECTED_OBSERVER_BIN_SHA" >&2
  exit 1
fi

if [[ "$ACTUAL_GUARDIAN_BIN_SHA" != "$EXPECTED_GUARDIAN_BIN_SHA" ]]; then
  echo "ERROR: Built obs_guardian.exe mismatch: got $ACTUAL_GUARDIAN_BIN_SHA, expected $EXPECTED_GUARDIAN_BIN_SHA" >&2
  exit 1
fi

# Stage to sibling temporary files in destination directory, verify both pair pins, then atomic rename
TMP_OBS="tools/validation/.sa_plan_observer.exe.tmp.$$"
TMP_GDN="tools/validation/.obs_guardian.exe.tmp.$$"
trap 'rm -rf -- "$TMP_BUILD" "$TMP_OBS" "$TMP_GDN"' EXIT

install -m 755 "$TMP_BUILD/sa_plan_observer.exe" "$TMP_OBS"
install -m 755 "$TMP_BUILD/obs_guardian.exe" "$TMP_GDN"

# Verify pair pins on staged sibling temporary files before replacing active targets
check_sha "$TMP_OBS" "$EXPECTED_OBSERVER_BIN_SHA"
check_sha "$TMP_GDN" "$EXPECTED_GUARDIAN_BIN_SHA"

# Atomic publish via rename
mv -f "$TMP_OBS" tools/validation/sa_plan_observer.exe
mv -f "$TMP_GDN" tools/validation/obs_guardian.exe

MANIFEST_PATH="tools/validation/telegram_observer_manifest.json"
cat > "$MANIFEST_PATH" <<EOF
{
  "schema": "uos.telegram-observer-build-manifest.v1",
  "built_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "status": "REPRODUCIBLE_CLEAN_BUILD_VERIFIED",
  "sources": [
    {"path": "plugins/uos-risk-prioritization/validation/priority.ml", "sha256": "$EXPECTED_PRIORITY_SHA"},
    {"path": "plugins/uos-risk-prioritization/validation/bounded.ml", "sha256": "$EXPECTED_BOUNDED_SHA"},
    {"path": "plugins/uos-risk-prioritization/validation/live_plan.ml", "sha256": "$EXPECTED_LIVE_PLAN_SHA"},
    {"path": "tools/validation/sa_plan_observer.ml", "sha256": "$EXPECTED_OBSERVER_SRC_SHA"},
    {"path": "tools/validation/obs_guardian.ml", "sha256": "$EXPECTED_GUARDIAN_SRC_SHA"}
  ],
  "binaries": [
    {"path": "tools/validation/sa_plan_observer.exe", "sha256": "$ACTUAL_OBSERVER_BIN_SHA"},
    {"path": "tools/validation/obs_guardian.exe", "sha256": "$ACTUAL_GUARDIAN_BIN_SHA"}
  ]
}
EOF

echo "BUILD_OK: Observer binaries reproduced bit-for-bit:"
echo "  sa_plan_observer.exe: $ACTUAL_OBSERVER_BIN_SHA"
echo "  obs_guardian.exe:     $ACTUAL_GUARDIAN_BIN_SHA"
