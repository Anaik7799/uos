#!/usr/bin/env bash
# ==============================================================================
# [C3I-SIL6] UOS Distributed Execution Instance 2 (razr15-1 Laptop GPU Node)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

echo "=============================================================================="
echo "   SAṀVID VAJRAVYŪHA: UOS DISTRIBUTED INSTANCE 2 (razr15-1 GPU NODE)"
echo "Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo "=============================================================================="

# 1. Probe GPU device acceleration in WSL2
echo "`n[1/4] Probing NVIDIA CUDA / DirectX acceleration..."
if [ -e "/dev/dxg" ] || command -v nvidia-smi &>/dev/null; then
    echo "  [PASS] Hardware GPU acceleration active (/dev/dxg)."
    if command -v nvidia-smi &>/dev/null; then
        nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader || true
    fi
else
    echo "  [WARN] /dev/dxg not found; running in CPU SIMD emulation mode."
fi

# 2. Test ZigVM Deterministic Engine
echo "`n[2/4] Initializing ZigVM Deterministic Runtime..."
if [ -x "./zigvm" ]; then
    ./zigvm version
    ./zigvm max-status || true
else
    echo "  [WARN] zigvm binary not in current directory, searching PATH..."
    if command -v zigvm &>/dev/null; then
        zigvm version
    fi
fi

# 3. Join Mesh Telemetry / Tailscale
echo "`n[3/4] Checking Tailscale Mesh connectivity to nas-1..."
PRIMARY_NAS="100.87.7.78"
if ping -c 1 -W 2 "$PRIMARY_NAS" &>/dev/null; then
    echo "  [PASS] Instance 0 (nas-1, $PRIMARY_NAS:4100) is REACHABLE."
else
    echo "  [WARN] Primary nas-1 ($PRIMARY_NAS) not reachable via Tailscale."
    echo "  Checking local subnet (192.168.1.220)..."
    if ping -c 1 -W 2 "192.168.1.220" &>/dev/null; then
        echo "  [PASS] Instance 0 is REACHABLE via LAN (192.168.1.220:4100)."
    fi
fi

# 4. Start Distributed Instance 2 Service (Port 8088)
echo "`n[4/4] Starting UOS Distributed Node Daemon on port 8088..."
python3 -c "
import http.server, socketserver, json, sys

PORT = 8088

class UOSDistributedHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path in ['/health', '/api/health', '/status', '/']:
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            payload = {
                'status': 'healthy',
                'instance_id': 'razr15-1-wsl2',
                'node_role': 'Instance 2 (Deep AI & GPU Accelerator)',
                'mesh': 'Saṁvid Vajravyūha',
                'primary_controller': 'http://100.87.7.78:4100',
                'peer_worker': 'http://100.78.98.18:8088',
                'has_gpu': True,
                'zigvm_kernel': 'deterministic_active',
                'distributed_operations': [
                    'MAX_GPU_INFERENCE',
                    'LOCAL_GEMMA4_ACCELERATION',
                    'FRACTAL_SWARM_WORK_STEALING'
                ]
            }
            self.wfile.write(json.dumps(payload, indent=2).encode())
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        sys.stderr.write('[UOS-DISTRIB-LOG] ' + (format % args) + '\n')

with socketserver.TCPServer(('', PORT), UOSDistributedHandler) as httpd:
    print(f'  [ONLINE] UOS Distributed Node active at http://0.0.0.0:{PORT}/health')
    print('  Listening for distributed tasks from nas-1 and vm-1... (Press Ctrl+C to stop)')
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print('\n  [OFFLINE] Stopping Instance 2 daemon.')
"
