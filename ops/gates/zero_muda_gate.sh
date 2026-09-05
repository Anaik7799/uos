#!/usr/bin/env bash
# ==============================================================================
# UOS Zero-Muda Admission Gate (G-MUDA)
# Strictly bars Bevy and Graphite from code, dependencies, and manifests.
# ==============================================================================
set -euo pipefail

UOS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

echo "==> Running UOS Zero-Muda Gate (G-MUDA)..."

# 1. Check for prohibited directory patterns
PROHIBITED_DIRS=$(find "$UOS_ROOT" -type d \( -name "*bevy*" -o -name "*graphite*" \) -not -path "*/.jj/*" -not -path "*/legacy/*" || true)
if [[ -n "$PROHIBITED_DIRS" ]]; then
    echo "ERROR: Found prohibited Bevy/Graphite directories in admitted tree:"
    echo "$PROHIBITED_DIRS"
    exit 1
fi

# 2. Check for Cargo.toml dependencies on bevy crates
PROHIBITED_CARGO=$(rg -i "(bevy_ecs|bevy_math|bevy_color|bevy_render)" "$UOS_ROOT" -g "Cargo.toml" -g "Cargo.lock" -g "!legacy/**" || true)
if [[ -n "$PROHIBITED_CARGO" ]]; then
    echo "ERROR: Found prohibited Bevy dependencies in Cargo configurations:"
    echo "$PROHIBITED_CARGO"
    exit 1
fi

# 3. Check for active FFI or code calls
PROHIBITED_CALLS=$(rg "(bevy_math_op|bevy_color_convert|bevy_ecs_spawn|nif_ecs_spawn)" "$UOS_ROOT" -g "!ops/gates/**" -g "!legacy/**" -g "!migration/**" || true)
if [[ -n "$PROHIBITED_CALLS" ]]; then
    echo "ERROR: Found active Bevy function calls in source code:"
    echo "$PROHIBITED_CALLS"
    exit 1
fi

echo "==> Zero-Muda Gate: PASSED (Zero Bevy, Zero Graphite)."
exit 0
