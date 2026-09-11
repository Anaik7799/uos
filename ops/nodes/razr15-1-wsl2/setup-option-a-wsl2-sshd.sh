#!/usr/bin/env bash
# ==============================================================================
# [C3I-SIL6-MSTS] Option A: Turnkey OpenSSH & Tailscale Setup inside WSL2
# ==============================================================================
# Host: razr15-1 (WSL2 Instance 2 GPU Node)
# Purpose: Configure OpenSSH server, enable systemd, register Tailscale node
#          with Tailscale SSH, and authorize nas-1 and vm-1 public keys.
# ==============================================================================
set -euo pipefail

echo "=============================================================================="
echo "[C3I-OPTION-A] PROVISIONING OPENSSH & TAILSCALE INSIDE WSL2 (razr15-1)"
echo "Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo "=============================================================================="

# Ensure running as root or with sudo
if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] This script must be run as root (e.g. sudo bash $0)"
    exit 1
fi

TARGET_USER="${SUDO_USER:-an}"
TARGET_HOME=$(getent passwd "${TARGET_USER}" | cut -d: -f6)
if [ -z "${TARGET_HOME}" ] || [ ! -d "${TARGET_HOME}" ]; then
    TARGET_HOME="/home/${TARGET_USER}"
    mkdir -p "${TARGET_HOME}"
fi

echo "[1/7] Target user detected: ${TARGET_USER} (Home: ${TARGET_HOME})"

# 1. Update packages and install OpenSSH server & curl
echo "[2/7] Installing openssh-server, curl, and prerequisites..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y openssh-server curl ca-certificates iptables

# 2. Configure /etc/wsl.conf for persistent systemd and networking
echo "[3/7] Ensuring /etc/wsl.conf enables systemd and standard hostname..."
mkdir -p /etc
cat << 'EOF' > /etc/wsl.conf
[boot]
systemd=true

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

# 3. Configure OpenSSH Server
echo "[4/7] Configuring OpenSSH server daemon (/etc/ssh/sshd_config.d/60-uos-mesh.conf)..."
mkdir -p /etc/ssh/sshd_config.d
cat << 'EOF' > /etc/ssh/sshd_config.d/60-uos-mesh.conf
# UOS Sovereign Mesh OpenSSH Configuration
Port 22
ListenAddress 0.0.0.0
PubkeyAuthentication yes
PasswordAuthentication yes
PermitRootLogin prohibit-password
AuthorizedKeysFile .ssh/authorized_keys
ChallengeResponseAuthentication no
UsePAM yes
X11Forwarding no
PrintMotd no
AcceptEnv LANG LC_*
ClientAliveInterval 30
ClientAliveCountMax 5
EOF

# Generate host keys if missing
ssh-keygen -A

# 4. Inject Authorized Keys for nas-1 and vm-1
echo "[5/7] Authorizing nas-1 and vm-1 host public keys..."
USER_SSH_DIR="${TARGET_HOME}/.ssh"
mkdir -p "${USER_SSH_DIR}"
chmod 700 "${USER_SSH_DIR}"
AUTH_KEYS="${USER_SSH_DIR}/authorized_keys"
touch "${AUTH_KEYS}"

# Canonical UOS Host Keys
NAS1_PUB="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMMewbASbkM+twLcsqnapyPzDLI08UlHhZFiRN8QCp01 an@nas-1"
VM1_PUB="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIANEVh3rGVj7FyOcgeKMjAptJzcEWceoCmkVzYLxrrIY an@vm-1"

for key in "${NAS1_PUB}" "${VM1_PUB}"; do
    if ! grep -qF "${key}" "${AUTH_KEYS}"; then
        echo "${key}" >> "${AUTH_KEYS}"
        echo "  [+] Appended authorized key: $(echo "${key}" | awk '{print $3}')"
    else
        echo "  [=] Key already authorized: $(echo "${key}" | awk '{print $3}')"
    fi
done

chmod 600 "${AUTH_KEYS}"
chown -R "${TARGET_USER}:${TARGET_USER}" "${USER_SSH_DIR}"

# Also authorize for root to allow supervisor emergency access
ROOT_SSH_DIR="/root/.ssh"
mkdir -p "${ROOT_SSH_DIR}"
chmod 700 "${ROOT_SSH_DIR}"
ROOT_AUTH="${ROOT_SSH_DIR}/authorized_keys"
touch "${ROOT_AUTH}"
for key in "${NAS1_PUB}" "${VM1_PUB}"; do
    if ! grep -qF "${key}" "${ROOT_AUTH}"; then
        echo "${key}" >> "${ROOT_AUTH}"
    fi
done
chmod 600 "${ROOT_AUTH}"

# 5. Install & Configure Tailscale inside WSL2
echo "[6/7] Installing / updating Tailscale inside WSL2..."
if ! command -v tailscale &>/dev/null; then
    curl -fsSL https://tailscale.com/install.sh | sh
fi

# Enable and start services via systemd
if command -v systemctl &>/dev/null && [ -d /run/systemd/system ]; then
    echo "  [+] Starting ssh and tailscaled via systemd..."
    systemctl daemon-reload || true
    systemctl enable --now ssh
    systemctl restart ssh
    systemctl enable --now tailscaled
    systemctl restart tailscaled
else
    echo "  [!] Systemd not active in current session. Starting services via init..."
    service ssh restart || /usr/sbin/sshd
    service tailscaled restart || tailscaled &
fi

# 6. Bring Tailscale online with Tailscale SSH
echo "[7/7] Bringing Tailscale online (hostname: razr15-wsl2, with Tailscale SSH)..."
tailscale up --hostname=razr15-wsl2 --accept-routes --ssh || true

echo "=============================================================================="
echo "[SUCCESS] OPTION A SETUP COMPLETED ON razr15-1 WSL2"
echo "=============================================================================="
echo "Local SSH Status:"
systemctl status ssh --no-pager || service ssh status || true
echo "------------------------------------------------------------------------------"
echo "Tailscale Status:"
tailscale status || true
echo "------------------------------------------------------------------------------"
echo "Tailscale IP:"
tailscale ip -4 || true
echo "=============================================================================="
echo "Test connection from nas-1 using:"
echo "  ssh ${TARGET_USER}@\$(tailscale ip -4)"
echo "  or"
echo "  tailscale ssh ${TARGET_USER}@razr15-wsl2"
echo "=============================================================================="
