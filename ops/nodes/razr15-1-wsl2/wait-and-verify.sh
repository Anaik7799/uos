#!/usr/bin/env bash
set -u

TARGET_IP="100.114.9.28"
TARGET_USER="abhij"
LOG_STAGING="/home/an/.gemini/antigravity-cli/brain/eb7a42c0-03e5-4814-9e55-4414c7c4eb28/.system_generated/tasks/task-7822.log"

echo "=== [UOS-WATCHDOG] PERSISTENT MONITORING RAZR15-1 DEPLOYMENT & REBOOT ==="
echo "Target IP: $TARGET_IP"
echo "Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"

# Phase 1: Wait for download or SSH authentication
echo "[Phase 1] Waiting for deploy-and-reboot.ps1 execution or SSH key acceptance..."
DOWNLOADED=0
while true; do
  if [ -f "$LOG_STAGING" ] && grep -q "$TARGET_IP" "$LOG_STAGING" 2>/dev/null; then
    echo "[$(date -u +%T)] Download detected from $TARGET_IP!"
    DOWNLOADED=1
    break
  fi
  if ssh -o BatchMode=yes -o ConnectTimeout=2 -o StrictHostKeyChecking=no "${TARGET_USER}@${TARGET_IP}" "echo WIN_SSH_OK" 2>/dev/null | grep -q "WIN_SSH_OK"; then
    echo "[$(date -u +%T)] SSH key authentication active!"
    DOWNLOADED=1
    break
  fi
  sleep 3
done

echo "[Phase 2] Waiting for script execution and machine reboot..."
REBOOT_DETECTED=0
for i in {1..200}; do
  if ! ping -c 1 -W 2 "$TARGET_IP" &>/dev/null; then
    echo "[$(date -u +%T)] Host $TARGET_IP went DOWN (Reboot in progress)!"
    REBOOT_DETECTED=1
    break
  fi
  sleep 2
done

if [ "$REBOOT_DETECTED" -eq 0 ]; then
  echo "[$(date -u +%T)] Note: Host may have rebooted rapidly or script still running. Checking post-boot SSH..."
fi

# Phase 3: Wait for host to come back ONLINE
echo "[Phase 3] Waiting for $TARGET_IP to come back online and OpenSSH to respond..."
HOST_BACK=0
for i in {1..300}; do
  if ping -c 1 -W 2 "$TARGET_IP" &>/dev/null; then
    if ssh -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=no "${TARGET_USER}@${TARGET_IP}" "echo POST_REBOOT_OK" 2>/dev/null | grep -q "POST_REBOOT_OK"; then
      echo "[$(date -u +%T)] SUCCESS: Host is back ONLINE and Windows OpenSSH is responding!"
      HOST_BACK=1
      break
    fi
  fi
  sleep 2
done

if [ "$HOST_BACK" -eq 0 ]; then
  echo "[$(date -u +%T)] Timeout waiting for Windows OpenSSH after reboot."
  exit 1
fi

# Phase 4: Verification of WSL2 Autostart, GPU, and Mesh Ports
echo "=== [UOS-VERIFY] EXECUTING FULL POST-REBOOT COLD-BOOT VERIFICATION ==="

echo "--- 1. Windows Host Last Boot Up Time ---"
ssh -o BatchMode=yes "${TARGET_USER}@${TARGET_IP}" 'powershell -Command "(Get-CimInstance Win32_OperatingSystem).LastBootUpTime"' 2>/dev/null || true

echo "--- 2. WSL2 Cold-Boot Autostart & Kernel Uptime ---"
ssh -o BatchMode=yes "${TARGET_USER}@${TARGET_IP}" 'wsl -u root -- uptime' 2>/dev/null || true
ssh -o BatchMode=yes "${TARGET_USER}@${TARGET_IP}" 'wsl -u root -- uname -a' 2>/dev/null || true

echo "--- 3. NVIDIA GPU Hardware & Drivers ---"
ssh -o BatchMode=yes "${TARGET_USER}@${TARGET_IP}" 'wsl -u root -- nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader' 2>/dev/null || true

echo "--- 4. Dual-Port WSL2 SSH (Port 2222) Verification ---"
for p in {1..20}; do
  if ssh -p 2222 -o BatchMode=yes -o ConnectTimeout=2 -o StrictHostKeyChecking=no "an@${TARGET_IP}" "echo PORT_2222_OK" 2>/dev/null | grep -q "PORT_2222_OK"; then
    echo "[PASS] Port 2222 WSL2 SSH directly reachable!"
    break
  fi
  sleep 2
done

echo "--- 5. WSL2 Memory & CPU Allocation (.wslconfig) ---"
ssh -o BatchMode=yes "${TARGET_USER}@${TARGET_IP}" 'wsl -u root -- free -h' 2>/dev/null || true
ssh -o BatchMode=yes "${TARGET_USER}@${TARGET_IP}" 'wsl -u root -- nproc' 2>/dev/null || true

echo "--- 6. Scheduled Task Cold-Boot Registration ---"
ssh -o BatchMode=yes "${TARGET_USER}@${TARGET_IP}" 'powershell -Command "Get-ScheduledTask -TaskName UOS_WSL2_ColdBoot_Autostart | Select-Object TaskName, State"' 2>/dev/null || true

echo "=== [UOS-WATCHDOG] ALL VERIFICATION STEPS COMPLETE ==="
