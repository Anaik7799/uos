#!/usr/bin/env bash
# ==============================================================================
# [C3I-SIL6] UOS Autonomous Intelligent Holon Node Launcher (aṃśa-pūrṇa)
# Target: razr15-1 (Razer Blade 15 Laptop GPU / Worker Holon)
# Runtime: Pure Erlang/OTP 29 (ERTS 17.0.5) ONLY
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

echo "=============================================================================="
echo "   SAṀVID VAJRAVYŪHA: UOS AUTONOMOUS INTELLIGENT HOLON NODE"
echo "   IDENTITY: holon-razr15-1 (SVADHARMA: Autonomous Compute & Acceleration)"
echo "   RUNTIME: Pure Erlang/OTP 29 (ERTS 17.0.5) ONLY"
echo "Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo "=============================================================================="

# 1. Locate Pinned Erlang OTP 29
PINNED_ERL="/nix/store/96cqahwqjxzx4pywz1bj53apncjmhhdg-erlang-29.0.5/bin/erl"
if [ ! -x "${PINNED_ERL}" ]; then
    echo "[ERROR] Pinned OTP 29 not found at ${PINNED_ERL}."
    echo "Run the automated installer first: curl -fsSL http://192.168.1.220:8999/holon | bash"
    exit 1
fi

# 2. Probe Network for Node Identity
LOCAL_IP=""
if command -v ip &>/dev/null; then
    LOCAL_IP="$(ip -4 route get 192.168.1.1 2>/dev/null | grep -oP 'src \K\S+' || true)"
fi
if [ -z "${LOCAL_IP}" ]; then
    LOCAL_IP="$(hostname -I 2>/dev/null | awk '{print $1}' || echo '127.0.0.1')"
fi
NODE_NAME="holon_razr15@${LOCAL_IP}"

echo "[HOLON] Node Name: ${NODE_NAME}"
echo "[HOLON] Cluster Cookie: uos_vajravyuh_cookie"
echo "[HOLON] Port 8088 Health API: http://localhost:8088/health"
echo "[HOLON] Port 8088 Substrate Telemetry: http://localhost:8088/holon"
echo "[HOLON] Port 8088 Interactive Cockpit: http://localhost:8088/"
echo "------------------------------------------------------------------------------"

exec "${PINNED_ERL}" \
    -name "${NODE_NAME}" \
    -setcookie uos_vajravyuh_cookie \
    -pa "${SCRIPT_DIR}" \
    -noshell \
    -eval '
        case uos_holon_node:start(8088) of
            {ok, _} ->
                io:format("[HOLON-INIT] Holon aṃśa-pūrṇa active and autonomous.~n"),
                io:format("[HOLON-INIT] Svadharma loop running. Substrate sensory active.~n"),
                io:format("[HOLON-INIT] Hive mesh connected. Listening for distributed jobs...~n");
            {error, Reason} ->
                io:format("[HOLON-INIT] [ERROR] Failed to boot Holon: ~p~n", [Reason]),
                halt(1)
        end.
    '
