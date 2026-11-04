#!/usr/bin/env bash
set -u
TARGET_IP="100.114.9.28"
LOG="/tmp/razr15_2222_autopush.log"

echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] Starting dual-channel SSH watcher (an@100.114.9.28:2222 AND abhij@100.114.9.28:22)..." >> "$LOG"

while true; do
  if ssh -p 2222 -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=accept-new "an@${TARGET_IP}" "echo WSL2_SSH_2222_READY" 2>/dev/null | grep -q "WSL2_SSH_2222_READY"; then
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] SSH 2222 CONNECTED! Pushing and executing install_max_mojo_wsl2.sh and benchmark_engine.mojo..." >> "$LOG"
    scp -P 2222 -o StrictHostKeyChecking=accept-new \
      /home/an/NAS-setup/uos/var/benchmarks/install_max_mojo_wsl2.sh \
      /home/an/NAS-setup/uos/services/inference/max/benchmark_engine.mojo \
      "an@${TARGET_IP}:/tmp/" >> "$LOG" 2>&1
    ssh -p 2222 -o StrictHostKeyChecking=accept-new "an@${TARGET_IP}" \
      "chmod +x /tmp/install_max_mojo_wsl2.sh && /tmp/install_max_mojo_wsl2.sh && ~/.modular/bin/magic run mojo /tmp/benchmark_engine.mojo" >> "$LOG" 2>&1
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] Remote installation and benchmark execution finished via port 2222 (exit=$?)." >> "$LOG"
    break
  fi

  if ssh -p 22 -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=accept-new "abhij@${TARGET_IP}" "echo WIN_SSH_22_READY" 2>/dev/null | grep -q "WIN_SSH_22_READY"; then
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] Windows SSH 22 CONNECTED! Bootstrapping WSL2 SSH 2222 and installing MAX/Mojo..." >> "$LOG"
    ssh -p 22 -o StrictHostKeyChecking=accept-new "abhij@${TARGET_IP}" \
      "powershell -NoProfile -ExecutionPolicy Bypass -Command \"irm http://100.87.7.78:8999/fix-2222-and-install-max-mojo.ps1 | iex\"" >> "$LOG" 2>&1
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] Remote installation via Windows SSH 22 finished (exit=$?)." >> "$LOG"
    break
  fi

  sleep 5
done
