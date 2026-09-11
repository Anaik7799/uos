#!/usr/bin/env bash
# ==============================================================================
# [C3I-SIL6] UOS Distributed Instance One-Liner Launcher (razr15-1 GPU Node)
# Usage: curl -fsSL http://192.168.1.220:8999/run | bash
# ==============================================================================
set -euo pipefail

echo "=============================================================================="
echo "   DOWNLOADING & LAUNCHING UOS DISTRIBUTED RUNTIME (razr15-1 GPU NODE)"
echo "Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo "=============================================================================="

UOS_DIR="${HOME}/uos"
mkdir -p "${UOS_DIR}"
cd "${UOS_DIR}"

SERVER_URL=""
for host in "192.168.1.220:8999" "100.87.7.78:8999"; do
    if curl -s -m 2 -I "http://${host}/uos-laptop-instance.tar.gz" 2>/dev/null | grep -q "200 OK"; then
        SERVER_URL="http://${host}"
        break
    fi
done

if [ -z "${SERVER_URL}" ]; then
    SERVER_URL="http://192.168.1.220:8999"
fi

echo "[UOS] Fetching distributed bundle from ${SERVER_URL}..."
curl -fsSL "${SERVER_URL}/uos-laptop-instance.tar.gz" | tar -xz
chmod +x zigvm run-uos-instance.sh start-instance2.sh 2>/dev/null || true

echo "[UOS] Bundle unpacked into ${UOS_DIR}."
echo "[UOS] Launching distributed operations..."
exec ./run-uos-instance.sh
