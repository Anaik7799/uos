#!/usr/bin/env bash
# ==============================================================================
# [C3I-SIL6-MSTS] Autonomous WSL2 Boot Entrypoint & Self-Healing Watchdog
# ==============================================================================
# Executed automatically by WSL2 at VM boot time via /etc/wsl.conf [boot] command=
# Runs as root on cold boot, Windows logon, and scheduled task triggers.
# ==============================================================================
set -u

LOG_FILE="/var/log/uos-boot-entrypoint.log"
exec >> "$LOG_FILE" 2>&1

echo "=============================================================================="
echo "[UOS-BOOT] AUTONOMOUS WSL2 BOOT ENTRYPOINT INITIALIZING"
echo "Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo "=============================================================================="

# 1. TUN Device Creation for Tailscale WireGuard
if [ ! -c /dev/net/tun ]; then
    echo "[boot] Creating /dev/net/tun..."
    mkdir -p /dev/net
    mknod /dev/net/tun c 10 200 2>/dev/null || true
    chmod 666 /dev/net/tun 2>/dev/null || true
fi

# 2. NVIDIA WSL Library Linking
if [ -d /usr/lib/wsl/lib ]; then
    echo "/usr/lib/wsl/lib" > /etc/ld.so.conf.d/ld.wsl.conf
    ldconfig 2>/dev/null || true
fi

# 3. Start OpenSSH Server (Dual-Port 22 + 2222)
echo "[boot] Ensuring OpenSSH server is running..."
if command -v systemctl &>/dev/null && [ -d /run/systemd/system ]; then
    systemctl restart ssh 2>/dev/null || service ssh restart 2>/dev/null || true
else
    service ssh restart 2>/dev/null || /usr/sbin/sshd 2>/dev/null || true
fi

# 4. Start Tailscale Daemon & Bring Node Online
echo "[boot] Ensuring Tailscale is running with Tailscale SSH..."
if command -v systemctl &>/dev/null && [ -d /run/systemd/system ]; then
    systemctl restart tailscaled 2>/dev/null || service tailscaled restart 2>/dev/null || true
else
    if ! pgrep -x "tailscaled" >/dev/null; then
        mkdir -p /var/lib/tailscale /var/log
        tailscaled --state=/var/lib/tailscale/tailscaled.state >/var/log/tailscaled.log 2>&1 &
        sleep 2
    fi
fi

# Bring Tailscale online with dedicated hostname
tailscale up --hostname=razr15-wsl2 --accept-routes --ssh 2>/dev/null || true

# 5. Start UOS Instance 2 Daemon (Modular MAX GPU on port 8088)
INSTANCE2_SCRIPT="/home/an/uos/ops/nodes/razr15-1-wsl2/start-instance2.sh"
if [ -f "$INSTANCE2_SCRIPT" ] && ! pgrep -f "start-instance2.sh" >/dev/null; then
    echo "[boot] Launching UOS Instance 2 GPU Daemon..."
    if id an &>/dev/null; then
        su - an -c "bash $INSTANCE2_SCRIPT" >/var/log/uos-instance2.log 2>&1 &
    else
        bash "$INSTANCE2_SCRIPT" >/var/log/uos-instance2.log 2>&1 &
    fi
fi

# 6. Fork Continuous Self-Healing Network Watchdog
if ! pgrep -f "uos-network-watchdog" >/dev/null; then
    echo "[boot] Starting UOS Network Watchdog..."
    (
        exec -a "uos-network-watchdog" bash -c '
            PRIMARY_NAS="100.87.7.78"
            while true; do
                sleep 30
                # Check if Tailscale interface has dropped or cannot reach nas-1
                if ! ping -c 1 -W 3 "$PRIMARY_NAS" &>/dev/null; then
                    echo "[watchdog $(date -u +"%Y-%m-%dT%H:%M:%SZ")] Warning: nas-1 ($PRIMARY_NAS) unreachable. Healing network..."
                    # Ensure TUN
                    [ ! -c /dev/net/tun ] && mkdir -p /dev/net && mknod /dev/net/tun c 10 200 && chmod 666 /dev/net/tun
                    # Heal Tailscale
                    service tailscaled status &>/dev/null || service tailscaled restart &>/dev/null || tailscaled &
                    tailscale up --hostname=razr15-wsl2 --accept-routes --ssh &>/dev/null || true
                    # Heal SSH
                    service ssh status &>/dev/null || service ssh restart &>/dev/null || /usr/sbin/sshd &>/dev/null || true
                fi
            done
        ' &
    )
fi

echo "[UOS-BOOT] Autonomous boot sequence completed successfully at $(date -u +"%Y-%m-%dT%H:%M:%SZ")."
exit 0
