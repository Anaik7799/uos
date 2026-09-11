#!/usr/bin/env bash
# ==============================================================================
# [C3I-SIL6] UOS Distributed Instance Launcher (Pure Erlang/OTP 29)
# Node: razr15-1 (Razer Blade 15 Laptop GPU / Worker Node)
# Usage: curl -fsSL http://192.168.1.220:8999/run | bash
# Mandate: SC-NIX-DEVENV-001, SC-ZMOF-001, SC-TIME, Zero-Muda
# ==============================================================================
set -euo pipefail

echo "=============================================================================="
echo "   SAṀVID VAJRAVYŪHA: UOS DISTRIBUTED INSTANCE 2 (razr15-1 NODE)"
echo "   RUNTIME: PURE ERLANG/OTP 29 (ERTS 17.0.5) ONLY"
echo "Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo "=============================================================================="

UOS_DIR="${HOME}/uos"
mkdir -p "${UOS_DIR}"
cd "${UOS_DIR}"

# 1. Discover active UOS Controller Host
SERVER_URL=""
for host in "192.168.1.220:8999" "100.87.7.78:8999" "nas-1.tail55d152.ts.net:8999"; do
    if curl -s -m 2 -I "http://${host}/cmd.txt" 2>/dev/null | grep -q "200 OK"; then
        SERVER_URL="http://${host}"
        break
    fi
done

if [ -z "${SERVER_URL}" ]; then
    SERVER_URL="http://192.168.1.220:8999"
fi
echo "[1/5] Using UOS Repository Server: ${SERVER_URL}"

# 2. Check or install Pure Erlang/OTP 29 runtime closure
PINNED_ERL="/nix/store/96cqahwqjxzx4pywz1bj53apncjmhhdg-erlang-29.0.5/bin/erl"
echo "[2/5] Checking Erlang/OTP 29 runtime engine..."

if [ -x "${PINNED_ERL}" ] && "${PINNED_ERL}" -noshell -eval 'case erlang:system_info(otp_release) of "29" -> halt(0); _ -> halt(1) end.' 2>/dev/null; then
    echo "  [PASS] Found existing Erlang/OTP 29 at ${PINNED_ERL}."
    ERL_BIN="${PINNED_ERL}"
else
    echo "  [FETCH] Downloading pure OTP 29 runtime closure (78MB)..."
    curl -fsSL "${SERVER_URL}/uos-otp29-runtime.tar.gz" -o "/tmp/uos-otp29-runtime.tar.gz"

    echo "  [EXTRACT] Unpacking OTP 29 closure to /nix/store..."
    if [ -w /nix ] 2>/dev/null || [ -w /nix/store ] 2>/dev/null; then
        tar -xzf "/tmp/uos-otp29-runtime.tar.gz" -C /
    elif sudo -n true 2>/dev/null; then
        sudo mkdir -p /nix/store
        sudo tar -xzf "/tmp/uos-otp29-runtime.tar.gz" -C /
    else
        echo "  [AUTH] Sudo permission required to unpack OTP 29 into /nix/store:"
        sudo mkdir -p /nix/store
        sudo tar -xzf "/tmp/uos-otp29-runtime.tar.gz" -C /
    fi
    rm -f "/tmp/uos-otp29-runtime.tar.gz"

    if [ ! -x "${PINNED_ERL}" ]; then
        echo "  [ERROR] Pinned Erlang binary ${PINNED_ERL} not found after extraction!"
        exit 1
    fi
    ERL_BIN="${PINNED_ERL}"
    echo "  [PASS] Erlang/OTP 29 installed successfully."
fi

# Verify OTP 29 release and ERTS version
OTP_VER="$("${ERL_BIN}" -noshell -eval 'io:format("~s (ERTS ~s)", [erlang:system_info(otp_release), erlang:system_info(version)]), halt().')"
echo "  [CONFIRMED] Active BEAM: Erlang/OTP ${OTP_VER}"

# 3. Fetch Instance 2 BEAM Application Bytecode
echo "[3/5] Fetching compiled UOS Instance 2 bytecode..."
curl -fsSL "${SERVER_URL}/uos_instance2.beam" -o "${UOS_DIR}/uos_instance2.beam"
echo "  [PASS] Downloaded uos_instance2.beam to ${UOS_DIR}."

# 4. Probe Hardware & Network Configuration
echo "[4/5] Probing hardware accelerators and mesh network..."
if [ -e "/dev/dxg" ] || command -v nvidia-smi &>/dev/null; then
    echo "  [PASS] Hardware GPU acceleration detected (/dev/dxg)."
    if command -v nvidia-smi &>/dev/null; then
        nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader 2>/dev/null || true
    fi
else
    echo "  [INFO] Running in CPU SIMD mode."
fi

# Detect Local Node IP
LOCAL_IP=""
if command -v ip &>/dev/null; then
    LOCAL_IP="$(ip -4 route get 192.168.1.1 2>/dev/null | grep -oP 'src \K\S+' || true)"
fi
if [ -z "${LOCAL_IP}" ]; then
    LOCAL_IP="$(hostname -I 2>/dev/null | awk '{print $1}' || echo '127.0.0.1')"
fi
NODE_NAME="instance2@${LOCAL_IP}"
echo "  [CONFIG] Node Name: ${NODE_NAME}"

# 5. Boot Instance 2 on Pure OTP 29
echo "[5/5] Launching UOS Distributed Instance 2 on port 8088..."
echo "------------------------------------------------------------------------------"
echo "  Web Health Endpoint: http://localhost:8088/health"
echo "  Local Dashboard:     http://localhost:8088/"
echo "  Prometheus Metrics:  http://localhost:8088/metrics"
echo "  Distributed Cookie:  uos_vajravyuh_cookie"
echo "------------------------------------------------------------------------------"

exec "${ERL_BIN}" \
    -name "${NODE_NAME}" \
    -setcookie uos_vajravyuh_cookie \
    -pa "${UOS_DIR}" \
    -noshell \
    -eval '
        case uos_instance2:start(8088) of
            {ok, _} ->
                io:format("[UOS-BOOT] Instance 2 node online and serving on port 8088.~n"),
                io:format("[UOS-BOOT] Mesh coordination active. Press Ctrl+C to stop.~n");
            {error, Reason} ->
                io:format("[UOS-BOOT] [ERROR] Startup failed: ~p~n", [Reason]),
                halt(1)
        end.
    '
