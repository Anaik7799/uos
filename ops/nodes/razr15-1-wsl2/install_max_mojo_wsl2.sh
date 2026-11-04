#!/usr/bin/env bash
# ============================================================
# install_max_mojo_wsl2.sh
# Target: RAZR1 — Windows 11 / WSL2 Ubuntu 22.04|24.04 / NVIDIA GPU
# Role:   Automated MAX + Mojo (Magic toolchain) deployment
# Author: Claude (SRE Sovereign, UOS) & Pi (Caste02)
# ============================================================

set -euo pipefail

log()  { echo -e "\033[1;36m[DEPLOY]\033[0m $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; }
fail() { echo -e "\033[1;31m[FAIL]\033[0m $*"; exit 1; }

# ---------- 0. Environment sanity ----------
if ! grep -qi microsoft /proc/version 2>/dev/null; then
    fail "This script must be run inside WSL2 Ubuntu, not native Linux or Windows PowerShell."
fi

if [ -f /etc/os-release ]; then
    . /etc/os-release
    log "Detected: $PRETTY_NAME"
    if [[ "$VERSION_ID" != "22.04" && "$VERSION_ID" != "24.04" ]]; then
        warn "Expected Ubuntu 22.04 or 24.04, found $VERSION_ID. Proceeding anyway."
    fi
fi

# ---------- 1. Strict NVIDIA/WSL2 guard ----------
log "Checking for forbidden Linux NVIDIA driver packages..."
if dpkg -l 2>/dev/null | grep -Ei 'nvidia-driver|nvidia-dkms' | grep -v '^rc'; then
    fail "A Linux NVIDIA driver package is installed. This BREAKS WSL2 GPU passthrough.
Remove it with: sudo apt purge 'nvidia-driver-*' 'nvidia-dkms-*' && wsl --shutdown (from Windows)"
fi
log "OK — no conflicting Linux NVIDIA driver detected."

# ---------- 2. systemd check ----------
if [ ! -f /etc/wsl.conf ] || ! grep -q "systemd=true" /etc/wsl.conf; then
    warn "systemd not enabled. Writing /etc/wsl.conf — you MUST run 'wsl --shutdown' from
Windows PowerShell and reopen this terminal after this script finishes."
    sudo bash -c 'cat >> /etc/wsl.conf' <<'EOF'

[boot]
systemd=true
EOF
    SYSTEMD_PENDING=true
else
    log "systemd already enabled."
    SYSTEMD_PENDING=false
fi

# ---------- 3. Base prerequisites ----------
log "Updating apt and installing base prerequisites..."
sudo apt-get update -y
sudo apt-get install -y \
    curl \
    git \
    build-essential \
    libgl1-mesa-glx \
    ca-certificates \
    pkg-config

# ---------- 4. GPU passthrough verification (no driver install) ----------
log "Verifying GPU passthrough stub (/usr/lib/wsl/lib)..."
if [ -d /usr/lib/wsl/lib ]; then
    log "Passthrough directory found: /usr/lib/wsl/lib"
else
    warn "/usr/lib/wsl/lib not found. Ensure Windows NVIDIA driver is installed and WSL2 is updated:
  (Windows PowerShell)  wsl --update"
fi

if command -v nvidia-smi >/dev/null 2>&1; then
    log "nvidia-smi found — testing passthrough:"
    nvidia-smi || warn "nvidia-smi present but failed to query GPU. Check Windows host driver."
else
    warn "nvidia-smi not found inside WSL2. This usually resolves after Windows driver update + wsl --update.
Do NOT fix this by apt-installing a Linux nvidia driver."
fi

# ---------- 5. Install Magic (official Modular installer) ----------
log "Installing Magic (Modular's official package/environment manager)..."
curl -ssL https://magic.modular.com | bash

MAGIC_BIN="$HOME/.modular/bin"
if [[ ":$PATH:" != *":$MAGIC_BIN:"* ]]; then
    echo '' >> ~/.bashrc
    echo '# --- Modular / Magic / Mojo ---' >> ~/.bashrc
    echo "export MODULAR_HOME=\"$HOME/.modular\"" >> ~/.bashrc
    echo "export PATH=\"\$MODULAR_HOME/bin:\$PATH\"" >> ~/.bashrc
fi

export MODULAR_HOME="$HOME/.modular"
export PATH="$MAGIC_BIN:$PATH"

if ! command -v magic >/dev/null 2>&1; then
    fail "Magic installation failed — 'magic' not found on PATH after install."
fi
log "Magic installed: $(magic --version)"

# ---------- 6. Create Mojo/MAX project ----------
PROJECT_DIR="$HOME/mojo-max-stack"
log "Creating project at $PROJECT_DIR ..."
if [ ! -d "$PROJECT_DIR" ]; then
    magic init "$PROJECT_DIR" --format mojoproject
fi
cd "$PROJECT_DIR"

log "Adding max and mojo packages to project..."
magic add max mojo

# ---------- 7. Self-test ----------
log "Running self-test inside magic environment..."
cat > /tmp/hello.mojo <<'EOF'
fn main():
    print("MAX+Mojo operational on RAZR1 WSL2")
EOF

magic run mojo --version || fail "mojo --version failed inside magic environment."
magic run mojo run /tmp/hello.mojo || fail "mojo run self-test failed."

# Also expose global mojo binary if magic provides it
if [ -f "$HOME/.modular/bin/mojo" ]; then
    log "Global mojo found at $HOME/.modular/bin/mojo"
fi

log "============================================================"
log " MAX + Mojo installation complete on RAZR1 WSL2."
log " Project: $PROJECT_DIR"
log " Enter environment with:  cd $PROJECT_DIR && magic shell"
log " Run Mojo directly with: magic run mojo run <file.mojo>"
log "============================================================"

if [ "$SYSTEMD_PENDING" = true ]; then
    warn "ACTION REQUIRED: Run 'wsl --shutdown' in Windows PowerShell now,
then reopen this WSL2 terminal to activate systemd before heavy MAX/GPU workloads."
fi
