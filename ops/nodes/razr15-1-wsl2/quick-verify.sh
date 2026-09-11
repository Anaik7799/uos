#!/usr/bin/env bash
set -u

TARGET_IP="100.114.9.28"
TARGET_USER="abhij"

echo "=== [UOS-VERIFY] LISTENING FOR ACTIVE SSH CONNECTION ON RAZR15-1 ==="

while true; do
  # Check Windows SSH
  if ssh -o BatchMode=yes -o ConnectTimeout=2 -o StrictHostKeyChecking=no "${TARGET_USER}@${TARGET_IP}" "echo WIN_OK" 2>/dev/null | grep -q "WIN_OK"; then
    echo "[$(date -u +%T)] SUCCESS: Windows OpenSSH Authenticated!"
    break
  fi
  # Check WSL2 Port 2222
  if ssh -p 2222 -o BatchMode=yes -o ConnectTimeout=2 -o StrictHostKeyChecking=no "an@${TARGET_IP}" "echo WSL_OK" 2>/dev/null | grep -q "WSL_OK"; then
    echo "[$(date -u +%T)] SUCCESS: WSL2 SSH on Port 2222 Authenticated!"
    break
  fi
  # Check WSL2 Tailscale IP
  if ssh -o BatchMode=yes -o ConnectTimeout=2 -o StrictHostKeyChecking=no "an@100.117.25.70" "echo TS_OK" 2>/dev/null | grep -q "TS_OK"; then
    echo "[$(date -u +%T)] SUCCESS: WSL2 Tailscale node 100.117.25.70 Authenticated!"
    break
  fi
  sleep 2
done

echo ""
echo "=============================================================================="
echo "[UOS-VERIFY] NODE REACHABLE! EXECUTING FULL COLD-BOOT CAPABILITY TEST"
echo "=============================================================================="

# 1. Windows Host Info
echo "--- 1. Windows Host Status & Uptime ---"
ssh -o BatchMode=yes "${TARGET_USER}@${TARGET_IP}" 'powershell -Command "Write-Host OS: ((Get-CimInstance Win32_OperatingSystem).Caption); Write-Host LastBoot: ((Get-CimInstance Win32_OperatingSystem).LastBootUpTime)"' 2>/dev/null || true

# 2. WSL2 Kernel & Uptime
echo "--- 2. WSL2 Kernel & Uptime ---"
ssh -o BatchMode=yes "${TARGET_USER}@${TARGET_IP}" 'wsl -u root -- uptime' 2>/dev/null || ssh -p 2222 -o BatchMode=yes "an@${TARGET_IP}" "uptime" 2>/dev/null || true
ssh -o BatchMode=yes "${TARGET_USER}@${TARGET_IP}" 'wsl -u root -- uname -a' 2>/dev/null || ssh -p 2222 -o BatchMode=yes "an@${TARGET_IP}" "uname -a" 2>/dev/null || true

# 3. GPU Hardware & Drivers
echo "--- 3. NVIDIA GPU Hardware & Drivers (NVIDIA-SMI) ---"
ssh -o BatchMode=yes "${TARGET_USER}@${TARGET_IP}" 'wsl -u root -- nvidia-smi' 2>/dev/null || ssh -p 2222 -o BatchMode=yes "an@${TARGET_IP}" "nvidia-smi" 2>/dev/null || true

# 4. CPU and Memory Allocation (.wslconfig)
echo "--- 4. Resource Allocation (.wslconfig) ---"
ssh -o BatchMode=yes "${TARGET_USER}@${TARGET_IP}" 'wsl -u root -- free -h; wsl -u root -- nproc' 2>/dev/null || ssh -p 2222 -o BatchMode=yes "an@${TARGET_IP}" "free -h; nproc" 2>/dev/null || true

# 5. Triadic Mesh Probe & Distribute Verification
echo "--- 5. Triadic Mesh Integration Verification ---"
/home/an/NAS-setup/uos/tools/triadic-resource-probe || true

echo ""
echo "=== [UOS-VERIFY] RAZR15-1 COLD-BOOT & GPU VERIFICATION COMPLETE ==="
