#!/usr/bin/env bash
# =============================================================================
# UOS & C3I Unified Workspace Environment Setup (SC-PROVENANCE-001)
# =============================================================================
export UOS_ROOT="/home/an/NAS-setup/uos"
export C3I_ROOT="/home/an/dev/ver/c3i"
export UOS_SA_PLAN_DB="/home/an/NAS-setup/uos/var/sa-plan/uos.sqlite3"
export C3I_PLANNING_DB="/home/an/dev/ver/c3i/var/planning.db"

# Tailscale FQDN & Mesh Networking
export TAILSCALE_NODE="nas-1"
export TAILSCALE_FQDN="nas-1.tail55d152.ts.net"
export COCKPIT_URL="http://nas-1.tail55d152.ts.net:4100"
export SAPLAN_URL="http://nas-1.tail55d152.ts.net:4200"
export ZENOH_ROUTER="tcp/100.87.7.78:7447"
export ZENOH_HTTP="http://100.87.7.78:8080"
export REMOTE_MESH_GATEWAY="https://vm-1.tail55d152.ts.net:8443"

# Ports
export GLEAM_HTTP_PORT=4100
export SAPLAN_HTTP_PORT=4200
export ZENOH_PORT=7447
export TLS_PROXY_PORT=8443

# Toolchains & Path Augmentation
export PATH="${UOS_ROOT}/tools:${UOS_ROOT}/bin:${C3I_ROOT}:${PATH}"
if [ -d "/home/an/.local/bin" ]; then
    export PATH="/home/an/.local/bin:${PATH}"
fi

# Zero-Muda and Safety Locks
export ZERO_MUDA=1
export HARDWARE_NVME_LOCK="25503L801736"

echo "╔═══════════════════════════════════════════════════════════════════╗"
echo "║  UOS & C3I UNIFIED SERVICES ENVIRONMENT ACTIVE                    ║"
echo "║  Host: ${TAILSCALE_FQDN} | Cockpit: ${COCKPIT_URL} ║"
echo "╚═══════════════════════════════════════════════════════════════════╝"
