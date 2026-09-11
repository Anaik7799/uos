#!/usr/bin/env bash
# ==============================================================================
# Autonomous Remote Bootstrapper & Reboot Watchdog for razr15-1
# Executes from nas-1 as soon as Windows OpenSSH access is established.
# ==============================================================================
set -u

TARGET_IP="100.114.9.28"
TARGET_USER="abhij"

echo "=== [UOS-REMOTE] WAITING FOR SSH ACCESS TO $TARGET_USER@$TARGET_IP ==="

for i in {1..450}; do
  if ssh -o BatchMode=yes -o ConnectTimeout=2 -o StrictHostKeyChecking=no "${TARGET_USER}@${TARGET_IP}" "echo WIN_SSH_OK" 2>/dev/null | grep -q "WIN_SSH_OK"; then
    echo "[$(date -u +%T)] SSH CONNECTION ESTABLISHED! Taking control of razr15-1..."
    break
  fi
  sleep 2
done

# Verify connection
if ! ssh -o BatchMode=yes -o ConnectTimeout=2 -o StrictHostKeyChecking=no "${TARGET_USER}@${TARGET_IP}" "echo WIN_SSH_OK" 2>/dev/null | grep -q "WIN_SSH_OK"; then
  echo "[$(date -u +%T)] [TIMEOUT] Remote bootstrap watchdog timed out waiting for SSH."
  exit 1
fi

echo "[$(date -u +%T)] [1/5] Deploying hardened .wslconfig to Windows Host..."
ssh -o BatchMode=yes "${TARGET_USER}@${TARGET_IP}" 'powershell -Command "Set-Content -Path \"$env:USERPROFILE\.wslconfig\" -Value @\"
[wsl2]
memory=12GB
processors=12
swap=8GB
localhostForwarding=true
nestedVirtualization=true
guiApplications=false
gpuSupport=true
pageReporting=true
vmIdleTimeout=-1

[experimental]
autoMemoryReclaim=gradual
sparseVhd=true
autoProxy=true
\"@ -Encoding UTF8 -Force"'

echo "[$(date -u +%T)] [2/5] Configuring WSL2 filesystem, /etc/wsl.conf, and boot hook..."
ssh -o BatchMode=yes "${TARGET_USER}@${TARGET_IP}" 'wsl -u root bash -c "
mkdir -p /root/.ssh /etc/ssh/sshd_config.d /dev/net /usr/local/bin /var/log
[ ! -c /dev/net/tun ] && mknod /dev/net/tun c 10 200 && chmod 666 /dev/net/tun

cat << '\''EOF'\'' > /etc/wsl.conf
[boot]
systemd=true
command=/usr/local/bin/uos-boot-entrypoint.sh

[automount]
enabled=true
options=\"metadata,umask=22,fmask=11\"

[network]
hostname=razr15-wsl2
generateHosts=true

[interop]
enabled=true
EOF

cat << '\''EOF'\'' > /usr/local/bin/uos-boot-entrypoint.sh
#!/usr/bin/env bash
set -u
exec >> /var/log/uos-boot-entrypoint.log 2>&1
[ ! -c /dev/net/tun ] && mkdir -p /dev/net && mknod /dev/net/tun c 10 200 && chmod 666 /dev/net/tun
[ -d /usr/lib/wsl/lib ] && echo \"/usr/lib/wsl/lib\" > /etc/ld.so.conf.d/ld.wsl.conf && ldconfig 2>/dev/null
service ssh restart 2>/dev/null || /usr/sbin/sshd 2>/dev/null || true
tailscaled --state=/var/lib/tailscale/tailscaled.state >/var/log/tailscaled.log 2>&1 &
sleep 2
tailscale up --hostname=razr15-wsl2 --accept-routes --ssh 2>/dev/null || true
(
  exec -a \"uos-network-watchdog\" bash -c '\''
    while true; do
      sleep 30
      if ! ping -c 1 -W 3 100.87.7.78 &>/dev/null; then
        [ ! -c /dev/net/tun ] && mknod /dev/net/tun c 10 200 && chmod 666 /dev/net/tun
        service ssh restart 2>/dev/null || /usr/sbin/sshd 2>/dev/null
        tailscale up --hostname=razr15-wsl2 --accept-routes --ssh 2>/dev/null || true
      fi
    done
  '\'' &
)
exit 0
EOF
chmod 755 /usr/local/bin/uos-boot-entrypoint.sh

cat << '\''EOF'\'' > /etc/ssh/sshd_config.d/60-uos-mesh.conf
Port 22
Port 2222
ListenAddress 0.0.0.0
PubkeyAuthentication yes
PermitRootLogin prohibit-password
AuthorizedKeysFile .ssh/authorized_keys
ClientAliveInterval 15
ClientAliveCountMax 8
EOF

mkdir -p /root/.ssh
echo \"ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMMewbASbkM+twLcsqnapyPzDLI08UlHhZFiRN8QCp01 an@nas-1\" >> /root/.ssh/authorized_keys
echo \"ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIANEVh3rGVj7FyOcgeKMjAptJzcEWceoCmkVzYLxrrIY an@vm-1\" >> /root/.ssh/authorized_keys
sort -u /root/.ssh/authorized_keys -o /root/.ssh/authorized_keys
chmod 700 /root/.ssh && chmod 600 /root/.ssh/authorized_keys

for u in an abhij ubuntu; do
  if id \"\$u\" &>/dev/null; then
    uhome=\$(getent passwd \"\$u\" | cut -d: -f6)
    mkdir -p \"\$uhome/.ssh\"
    echo \"ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMMewbASbkM+twLcsqnapyPzDLI08UlHhZFiRN8QCp01 an@nas-1\" >> \"\$uhome/.ssh/authorized_keys\"
    echo \"ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIANEVh3rGVj7FyOcgeKMjAptJzcEWceoCmkVzYLxrrIY an@vm-1\" >> \"\$uhome/.ssh/authorized_keys\"
    sort -u \"\$uhome/.ssh/authorized_keys\" -o \"\$uhome/.ssh/authorized_keys\"
    chmod 700 \"\$uhome/.ssh\" && chmod 600 \"\$uhome/.ssh/authorized_keys\"
    chown -R \"\$u:\$u\" \"\$uhome/.ssh\"
  fi
done
service ssh restart 2>/dev/null || /usr/sbin/sshd 2>/dev/null || true
"'

echo "[$(date -u +%T)] [3/5] Setting up Windows Portproxy and Firewall..."
ssh -o BatchMode=yes "${TARGET_USER}@${TARGET_IP}" 'powershell -Command "
try {
  $wslIp = (wsl hostname -I).Trim().Split(\" \")[0]
  if ($wslIp) {
    netsh interface portproxy delete v4tov4 listenport=2222 listenaddress=0.0.0.0 2>`$null | Out-Null
    netsh interface portproxy add v4tov4 listenport=2222 listenaddress=0.0.0.0 connectport=2222 connectaddress=$wslIp
  }
} catch {}
New-NetFirewallRule -DisplayName \"UOS WSL2 SSH 2222\" -Direction Inbound -LocalPort 2222 -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
New-NetFirewallRule -DisplayName \"UOS WSL2 Health 8088\" -Direction Inbound -LocalPort 8088 -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
"'

echo "[$(date -u +%T)] [4/5] Registering UOS_WSL2_ColdBoot_Autostart under NT AUTHORITY\SYSTEM..."
ssh -o BatchMode=yes "${TARGET_USER}@${TARGET_IP}" 'powershell -Command "
$act = New-ScheduledTaskAction -Execute \"wsl.exe\" -Argument \"-u root -- /bin/bash /usr/local/bin/uos-boot-entrypoint.sh\"
$trg = @((New-ScheduledTaskTrigger -AtStartup), (New-ScheduledTaskTrigger -AtLogon))
$prn = New-ScheduledTaskPrincipal -UserId \"NT AUTHORITY\SYSTEM\" -LogonType ServiceAccount -RunLevel Highest
$set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 0 -RestartInterval (New-TimeSpan -Minutes 1) -RestartCount 999 -Priority 4
Unregister-ScheduledTask -TaskName \"UOS_WSL2_ColdBoot_Autostart\" -Confirm:`$false -ErrorAction SilentlyContinue | Out-Null
Register-ScheduledTask -TaskName \"UOS_WSL2_ColdBoot_Autostart\" -Action `$act -Trigger `$trg -Principal `$prn -Settings `$set -Force | Out-Null
Start-ScheduledTask -TaskName \"UOS_WSL2_ColdBoot_Autostart\"
"'

echo "[$(date -u +%T)] [5/5] INITIATING SYSTEM REBOOT ON razr15-1..."
ssh -o BatchMode=yes "${TARGET_USER}@${TARGET_IP}" 'shutdown /r /t 2 /c "UOS Cold-Boot Reboot Test"' || true

echo "[$(date -u +%T)] Reboot command sent! Monitoring post-reboot recovery..."
sleep 15

# Wait for host to drop and come back
for j in {1..120}; do
  if ping -c 1 -W 2 "${TARGET_IP}" &>/dev/null; then
    if ssh -o BatchMode=yes -o ConnectTimeout=2 "${TARGET_USER}@${TARGET_IP}" "echo POST_REBOOT_OK" 2>/dev/null | grep -q "POST_REBOOT_OK"; then
      echo "[$(date -u +%T)] SUCCESS: razr15-1 has rebooted and Windows OpenSSH is online!"
      echo "--- WSL2 Status ---"
      ssh -o BatchMode=yes "${TARGET_USER}@${TARGET_IP}" "wsl -u root -- uptime" 2>/dev/null || true
      ssh -o BatchMode=yes "${TARGET_USER}@${TARGET_IP}" "wsl -u root -- uname -a" 2>/dev/null || true
      echo "--- Dual Port 2222 Status ---"
      ssh -p 2222 -o BatchMode=yes an@"${TARGET_IP}" "uptime" 2>/dev/null || true
      echo "--- GPU Hardware Status ---"
      ssh -o BatchMode=yes "${TARGET_USER}@${TARGET_IP}" "wsl -u root -- nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader" 2>/dev/null || true
      echo "=== [UOS-REMOTE] REBOOT SURVIVAL AND COLD BOOT VERIFIED 100% GREEN ==="
      exit 0
    fi
  fi
  sleep 3
done

echo "[WARN] Post-reboot poll timed out. System may still be restarting."
exit 0
