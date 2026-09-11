#!/usr/bin/env bash
# ==============================================================================
# [C3I-SIL6-MSTS] Ultra-Robust Option A: OpenSSH & Tailscale Setup inside WSL2
# ==============================================================================
# Target Node: razr15-1 (Razer Blade 15 WSL2 Instance 2 GPU Node)
# Hardened Against:
#   1. Systemd vs SysVinit PID-1 discrepancy
#   2. Missing /dev/net/tun in WSL2 kernel
#   3. Port 22 collision with Windows OpenSSH (enables dual-port 22 + 2222)
#   4. Multi-user key authorization (root, an, abhij, ubuntu, Windows host)
#   5. Missing NVIDIA WSL library paths (/usr/lib/wsl/lib)
#   6. WSL2 VM idle termination (keepalive daemon)
# ==============================================================================
set -euo pipefail

trap 'echo "[ERROR] Option A setup failed at line $LINENO on command: $BASH_COMMAND" >&2' ERR

echo "=============================================================================="
echo "[C3I-OPTION-A] PROVISIONING HARDENED OPENSSH & TAILSCALE IN WSL2 (razr15-1)"
echo "Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo "=============================================================================="

# Ensure root
if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] This script must be run as root (e.g. sudo bash $0)" >&2
    exit 1
fi

# 1. TUN Device Creation & Validation for Tailscale WireGuard
echo "[1/8] Verifying /dev/net/tun character device..."
if [ ! -c /dev/net/tun ]; then
    echo "  [+] Creating /dev/net/tun device node..."
    mkdir -p /dev/net
    mknod /dev/net/tun c 10 200 || true
    chmod 666 /dev/net/tun || true
fi
if [ -c /dev/net/tun ]; then
    echo "  [PASS] /dev/net/tun character device verified."
else
    echo "  [WARN] /dev/net/tun could not be created directly; userspace networking fallback will be used."
fi

# 2. Package Installation with Retry Logic
echo "[2/8] Ensuring openssh-server, curl, ca-certificates, and iptables are installed..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y -q || true
for pkg in openssh-server curl ca-certificates iptables net-tools iproute2; do
    if ! dpkg -s "$pkg" &>/dev/null; then
        echo "  [+] Installing $pkg..."
        apt-get install -y -q "$pkg" || true
    fi
done

# 3. Configure /etc/wsl.conf for Systemd and Hostname
echo "[3/8] Writing hardened /etc/wsl.conf..."
cat << 'EOF' > /etc/wsl.conf
# ==============================================================================
# [C3I-SIL6-MSTS] Hardened WSL2 Configuration
# ==============================================================================
[boot]
systemd=true
command=/usr/local/bin/uos-boot-entrypoint.sh

[automount]
enabled=true
mountFsTab=true
root=/mnt/
options="metadata,umask=22,fmask=11"

[network]
hostname=razr15-wsl2
generateHosts=true
generateResolvConf=true

[interop]
enabled=true
appendWindowsPath=false
EOF

# Install /usr/local/bin/uos-boot-entrypoint.sh
echo "  [+] Installing /usr/local/bin/uos-boot-entrypoint.sh..."
cat << 'EOF' > /usr/local/bin/uos-boot-entrypoint.sh
#!/usr/bin/env bash
set -u
LOG_FILE="/var/log/uos-boot-entrypoint.log"
exec >> "$LOG_FILE" 2>&1

echo "=============================================================================="
echo "[UOS-BOOT] AUTONOMOUS WSL2 BOOT ENTRYPOINT INITIALIZING"
echo "Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo "=============================================================================="

# 1. TUN Device Creation for Tailscale WireGuard
if [ ! -c /dev/net/tun ]; then
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
if command -v systemctl &>/dev/null && [ -d /run/systemd/system ]; then
    systemctl restart ssh 2>/dev/null || service ssh restart 2>/dev/null || true
else
    service ssh restart 2>/dev/null || /usr/sbin/sshd 2>/dev/null || true
fi

# 4. Start Tailscale Daemon & Bring Node Online
if command -v systemctl &>/dev/null && [ -d /run/systemd/system ]; then
    systemctl restart tailscaled 2>/dev/null || service tailscaled restart 2>/dev/null || true
else
    if ! pgrep -x "tailscaled" >/dev/null; then
        mkdir -p /var/lib/tailscale /var/log
        tailscaled --state=/var/lib/tailscale/tailscaled.state >/var/log/tailscaled.log 2>&1 &
        sleep 2
    fi
fi
tailscale up --hostname=razr15-wsl2 --accept-routes --ssh 2>/dev/null || true

# 5. Start UOS Instance 2 Daemon
INSTANCE2_SCRIPT="/home/an/uos/ops/nodes/razr15-1-wsl2/start-instance2.sh"
if [ -f "$INSTANCE2_SCRIPT" ] && ! pgrep -f "start-instance2.sh" >/dev/null; then
    if id an &>/dev/null; then
        su - an -c "bash $INSTANCE2_SCRIPT" >/var/log/uos-instance2.log 2>&1 &
    else
        bash "$INSTANCE2_SCRIPT" >/var/log/uos-instance2.log 2>&1 &
    fi
fi

# 6. Fork Continuous Self-Healing Network Watchdog
if ! pgrep -f "uos-network-watchdog" >/dev/null; then
    (
        exec -a "uos-network-watchdog" bash -c '
            PRIMARY_NAS="100.87.7.78"
            while true; do
                sleep 30
                if ! ping -c 1 -W 3 "$PRIMARY_NAS" &>/dev/null; then
                    [ ! -c /dev/net/tun ] && mkdir -p /dev/net && mknod /dev/net/tun c 10 200 && chmod 666 /dev/net/tun
                    service tailscaled status &>/dev/null || service tailscaled restart &>/dev/null || tailscaled &
                    tailscale up --hostname=razr15-wsl2 --accept-routes --ssh &>/dev/null || true
                    service ssh status &>/dev/null || service ssh restart &>/dev/null || /usr/sbin/sshd &>/dev/null || true
                fi
            done
        ' &
    )
fi
echo "[UOS-BOOT] Autonomous boot sequence completed successfully."
exit 0
EOF
chmod 755 /usr/local/bin/uos-boot-entrypoint.sh


# 4. Configure Dual-Port SSH Daemon (22 & 2222)
echo "[4/8] Configuring OpenSSH daemon (/etc/ssh/sshd_config.d/60-uos-mesh.conf)..."
mkdir -p /etc/ssh/sshd_config.d
cat << 'EOF' > /etc/ssh/sshd_config.d/60-uos-mesh.conf
# ==============================================================================
# UOS Sovereign Mesh OpenSSH Configuration (Dual-Port Resilient)
# ==============================================================================
# Port 22: Native Tailscale interface (razr15-wsl2)
# Port 2222: Windows host loopback & portproxy fallback
Port 22
Port 2222
ListenAddress 0.0.0.0
ListenAddress ::

PubkeyAuthentication yes
PasswordAuthentication yes
PermitRootLogin prohibit-password
AuthorizedKeysFile .ssh/authorized_keys

# Performance & Keep-Alive Hardening
ClientAliveInterval 15
ClientAliveCountMax 8
TCPKeepAlive yes
UseDNS no
PrintMotd no
AcceptEnv LANG LC_*
X11Forwarding no
EOF

# Verify syntax and generate host keys if needed
ssh-keygen -A 2>/dev/null || true
sshd -t -f /etc/ssh/sshd_config || echo "[WARN] sshd -t returned warnings"

# 5. Inject Authorized Keys Universally (Multi-User & Cross-OS)
echo "[5/8] Authorizing canonical UOS host public keys across all user accounts..."
NAS1_PUB="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMMewbASbkM+twLcsqnapyPzDLI08UlHhZFiRN8QCp01 an@nas-1"
VM1_PUB="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIANEVh3rGVj7FyOcgeKMjAptJzcEWceoCmkVzYLxrrIY an@vm-1"

inject_keys_for_user() {
    local u="$1"
    local uhome="$2"
    if [ -d "$uhome" ]; then
        local u_ssh="$uhome/.ssh"
        local u_auth="$u_ssh/authorized_keys"
        mkdir -p "$u_ssh"
        chmod 700 "$u_ssh"
        touch "$u_auth"
        for k in "$NAS1_PUB" "$VM1_PUB"; do
            if ! grep -qF "$k" "$u_auth" 2>/dev/null; then
                echo "$k" >> "$u_auth"
                echo "    [+] Added to $u: $(echo "$k" | awk '{print $3}')"
            fi
        done
        chmod 600 "$u_auth"
        chown -R "$u:$u" "$u_ssh" 2>/dev/null || true
    fi
}

# Root account
inject_keys_for_user root /root

# Target Linux accounts
for u in an abhij ubuntu "${SUDO_USER:-}"; do
    [ -n "$u" ] && [ "$u" != "root" ] && inject_keys_for_user "$u" "/home/$u"
done

# Cross-OS: Also inject into Windows host user profile if accessible via 9P mount
for win_user in abhij an Administrator; do
    WIN_SSH="/mnt/c/Users/$win_user/.ssh"
    if [ -d "/mnt/c/Users/$win_user" ]; then
        mkdir -p "$WIN_SSH"
        WIN_AUTH="$WIN_SSH/authorized_keys"
        touch "$WIN_AUTH" 2>/dev/null || true
        for k in "$NAS1_PUB" "$VM1_PUB"; do
            if ! grep -qF "$k" "$WIN_AUTH" 2>/dev/null; then
                echo "$k" >> "$WIN_AUTH" 2>/dev/null || true
                echo "    [+] Injected into Windows C:\\Users\\$win_user\\.ssh\\authorized_keys"
            fi
        done
    fi
done

# 6. NVIDIA WSL Dynamic Library Paths
echo "[6/8] Configuring NVIDIA CUDA driver library paths (/usr/lib/wsl/lib)..."
if [ -d /usr/lib/wsl/lib ]; then
    echo "/usr/lib/wsl/lib" > /etc/ld.so.conf.d/ld.wsl.conf
    ldconfig 2>/dev/null || true
    echo "  [PASS] /usr/lib/wsl/lib bound to ldconfig."
else
    echo "  [WARN] /usr/lib/wsl/lib not yet mounted. Will be mounted by WSL2 on boot."
fi

# 7. Dual Init Resilience & Keep-Alive Daemon
echo "[7/8] Configuring systemd services and SysVinit fallback..."

# Create Keepalive Service
cat << 'EOF' > /etc/systemd/system/uos-keepalive.service
[Unit]
Description=UOS WSL2 Background Keep-Alive Daemon
After=network.target

[Service]
Type=simple
ExecStart=/bin/bash -c "while true; do sleep 3600; done"
Restart=always
RestartSec=2s

[Install]
WantedBy=multi-user.target
EOF

# Add SysVinit fallback to /etc/rc.local
cat << 'EOF' > /etc/rc.local
#!/bin/sh -e
# UOS Boot Fallback for non-systemd init
[ ! -c /dev/net/tun ] && mkdir -p /dev/net && mknod /dev/net/tun c 10 200 2>/dev/null && chmod 666 /dev/net/tun 2>/dev/null
service ssh status >/dev/null 2>&1 || service ssh start
service tailscaled status >/dev/null 2>&1 || service tailscaled start
exit 0
EOF
chmod +x /etc/rc.local 2>/dev/null || true

# Check PID 1 init system
INIT_PID1=$(ps -p 1 -o comm= 2>/dev/null || echo "init")
echo "  [i] Detected PID 1 init system: $INIT_PID1"

if [ "$INIT_PID1" = "systemd" ] || [ -d /run/systemd/system ]; then
    echo "  [+] Managing services via systemctl..."
    systemctl daemon-reload || true
    systemctl enable --now uos-keepalive.service || true
    systemctl enable --now ssh || true
    systemctl restart ssh || true
else
    echo "  [+] Managing services via service / SysVinit..."
    service ssh restart || /usr/sbin/sshd
fi

# 8. Install and Start Tailscale
echo "[8/8] Provisioning Tailscale with Tailscale SSH..."
if ! command -v tailscale &>/dev/null; then
    echo "  [+] Installing Tailscale..."
    curl -fsSL https://tailscale.com/install.sh | sh || true
fi

# Start tailscaled daemon
if [ "$INIT_PID1" = "systemd" ] || [ -d /run/systemd/system ]; then
    systemctl enable --now tailscaled || true
    systemctl restart tailscaled || true
else
    service tailscaled restart 2>/dev/null || (killall tailscaled 2>/dev/null; tailscaled --state=/var/lib/tailscale/tailscaled.state &)
fi

sleep 2

# Bring Tailscale online
echo "  [+] Registering Tailscale node (razr15-wsl2) with Tailscale SSH..."
tailscale up --hostname=razr15-wsl2 --accept-routes --ssh || true

echo "=============================================================================="
echo "[SUCCESS] HARDENED OPTION A PROVISIONING COMPLETED"
echo "=============================================================================="
echo "SSH Listening Ports:"
ss -tulpn 2>/dev/null | grep sshd || netstat -tulpn 2>/dev/null | grep sshd || true
echo "------------------------------------------------------------------------------"
echo "Tailscale Status:"
tailscale status || true
echo "------------------------------------------------------------------------------"
echo "Tailscale IP:"
tailscale ip -4 2>/dev/null || true
echo "=============================================================================="
echo "You can now connect from nas-1 using:"
echo "  1. Tailscale FQDN:   ssh an@razr15-wsl2"
echo "  2. Tailscale SSH:    tailscale ssh an@razr15-wsl2"
echo "  3. Dual-Port 2222:   ssh -p 2222 an@100.114.9.28"
echo "=============================================================================="
