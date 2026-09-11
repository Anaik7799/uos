#!/usr/bin/env bash
# ==============================================================================
# [C3I-SIL6] UOS Autonomous Intelligent Holon Node Installer & Evolution Runner
# Entity: holon-razr15-1 (Razer Blade 15 Laptop GPU / Evolution Node)
# Full Stack: Opam/OCaml, Modular MAX/Mojo, Lean 4, Quint, OTP 29
# Usage: curl -fsSL http://192.168.1.220:8999/holon | bash
# Runtime: Pure Erlang/OTP 29 (ERTS 17.0.5) ONLY (SC-NIX-DEVENV-001)
# ==============================================================================
set -euo pipefail

echo "=============================================================================="
echo "   SAṀVID VAJRAVYŪHA: UOS AUTONOMOUS EVOLUTION HOLON NODE"
echo "   ENTITY: holon-razr15-1 (FULL DEVELOPMENT & EVOLUTION CAPABILITY)"
echo "   PILLARS: Opam/OCaml, Modular MAX/Mojo, Lean 4, Quint, OTP 29"
echo "Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo "=============================================================================="

UOS_DIR="${HOME}/uos"
mkdir -p "${UOS_DIR}"
cd "${UOS_DIR}"

# 1. Discover UOS Controller Server
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
echo "[1/6] Using UOS Repository Server: ${SERVER_URL}"

# 2. Check or install Pure Erlang/OTP 29 runtime closure
PINNED_ERL="/nix/store/96cqahwqjxzx4pywz1bj53apncjmhhdg-erlang-29.0.5/bin/erl"
echo "`n[2/6] Checking Erlang/OTP 29 runtime engine..."

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

OTP_VER="$("${ERL_BIN}" -noshell -eval 'io:format("~s (ERTS ~s)", [erlang:system_info(otp_release), erlang:system_info(version)]), halt().')"
echo "  [CONFIRMED] Active BEAM Engine: Erlang/OTP ${OTP_VER}"

# 3. Fetch Holon Bytecode & Support Modules
echo "`n[3/6] Fetching compiled UOS Holon bytecode and support modules..."
curl -fsSL "${SERVER_URL}/uos_holon_node.beam" -o "${UOS_DIR}/uos_holon_node.beam"
curl -fsSL "${SERVER_URL}/uos_holon_sensory.beam" -o "${UOS_DIR}/uos_holon_sensory.beam"
curl -fsSL "${SERVER_URL}/uos_holon_sup.beam" -o "${UOS_DIR}/uos_holon_sup.beam"
curl -fsSL "${SERVER_URL}/uos_instance2.beam" -o "${UOS_DIR}/uos_instance2.beam"
curl -fsSL "${SERVER_URL}/run-holon.sh" -o "${UOS_DIR}/run-holon.sh"
curl -fsSL "${SERVER_URL}/hydrate-evolution-stack.sh" -o "${UOS_DIR}/hydrate-evolution-stack.sh"
chmod +x "${UOS_DIR}/run-holon.sh" "${UOS_DIR}/hydrate-evolution-stack.sh"
echo "  [PASS] Downloaded Holon modules into ${UOS_DIR}."

# 4. Probe Substrate & Toolchains
echo "`n[4/6] Running Substrate Sensory Discovery & Toolchain Audit..."
export UOS_ROOT="${UOS_DIR}"
"${ERL_BIN}" -pa "${UOS_DIR}" -noshell -eval '
    Sensory = uos_holon_sensory:sense_all(),
    Cpu = maps:get(cpu, Sensory, #{}),
    Mem = maps:get(memory, Sensory, #{}),
    Gpu = maps:get(gpu, Sensory, #{}),
    Toolchains = maps:get(toolchains, Sensory, #{}),
    io:format("  [SENSORY] CPU: ~s (~p cores, ~p schedulers)~n",
        [maps:get(model, Cpu, <<"x86_64">>), maps:get(logical_cores, Cpu, 0), maps:get(beam_schedulers, Cpu, 0)]),
    io:format("  [SENSORY] RAM: ~.1f MB host available, ~.2f MB BEAM active~n",
        [maps:get(host_available_mb, Mem, 0.0), maps:get(beam_total_mb, Mem, 0.0)]),
    io:format("  [SENSORY] GPU: ~s (~s)~n",
        [maps:get(acceleration_mode, Gpu, <<"None">>), maps:get(device_name, Gpu, <<"None">>)]),
    io:format("  [SENSORY] Evolution Grade: ~s (Readiness: ~.1f%)~n",
        [maps:get(evolution_grade, Toolchains, <<"UNKNOWN">>), maps:get(evolution_readiness_pct, Toolchains, 0.0)]),
    halt().
'

# 5. Background Toolchain Hydration (Optional)
echo "`n[5/6] Evolution Stack Hydration readiness:"
echo "  To sync full Opam, Mojo/MAX, Lean 4, and Quint toolchains locally:"
echo "  Run: ${UOS_DIR}/hydrate-evolution-stack.sh"

# 6. Launch Autonomous Holon Node
echo "`n[6/6] Launching Autonomous Holon Node on port 8088..."
echo "------------------------------------------------------------------------------"
echo "  Holon Status API:    http://localhost:8088/health"
echo "  Evolution Matrix:    http://localhost:8088/evolution"
echo "  Substrate Telemetry: http://localhost:8088/holon"
echo "  Interactive Cockpit: http://localhost:8088/"
echo "  Prometheus Metrics:  http://localhost:8088/metrics"
echo "  Distributed Cookie:  uos_vajravyuh_cookie"
echo "------------------------------------------------------------------------------"

exec "${UOS_DIR}/run-holon.sh"
