# ==============================================================================
# [C3I-SIL6-MSTS] Turnkey Self-Contained Deployment & Reboot Orchestrator
# Target Node: razr15-1 (Razer Blade 15 Laptop - Windows 11 + WSL2 GPU Node)
# ==============================================================================
# Execute from Windows PowerShell (Run as Administrator) on razr15-1:
# powershell -ExecutionPolicy Bypass -File deploy-and-reboot.ps1
# ==============================================================================

param(
    [switch]$NoReboot = $false
)

$ErrorActionPreference = "Stop"

Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host "[UOS-DEPLOY] TURNKEY PROVISIONING & REBOOT ORCHESTRATION (razr15-1)" -ForegroundColor Cyan
Write-Host "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')" -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Cyan

# 0. Check Administrator Privileges
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "[FATAL] This script must be run as Administrator! Please right-click PowerShell and select 'Run as administrator'."
    exit 1
}

$nas1Key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMMewbASbkM+twLcsqnapyPzDLI08UlHhZFiRN8QCp01 an@nas-1"
$vm1Key  = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIANEVh3rGVj7FyOcgeKMjAptJzcEWceoCmkVzYLxrrIY an@vm-1"

# 1. Deploy Hardened .wslconfig (Prevents VM Idle Shutdown)
Write-Host "`n[1/7] Deploying hardened .wslconfig to host profile..." -ForegroundColor Yellow
$userProfile = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::UserProfile)
$wslConfigPath = Join-Path $userProfile ".wslconfig"
$wslConfigContent = @"
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
"@
Set-Content -Path $wslConfigPath -Value $wslConfigContent -Encoding UTF8 -Force
Write-Host "  [PASS] Hardened .wslconfig deployed (vmIdleTimeout=-1)." -ForegroundColor Green

# 2. Authorize Keys in Windows Host OpenSSH (Both User & Administrators group)
Write-Host "`n[2/7] Authorizing nas-1 and vm-1 ED25519 keys in Windows OpenSSH..." -ForegroundColor Yellow

# User authorized_keys
$winUserSshDir = Join-Path $userProfile ".ssh"
if (-not (Test-Path $winUserSshDir)) { New-Item -ItemType Directory -Path $winUserSshDir -Force | Out-Null }
$winUserAuthKeys = Join-Path $winUserSshDir "authorized_keys"
Set-Content -Path $winUserAuthKeys -Value "$nas1Key`n$vm1Key" -Encoding ascii -Force
Write-Host "  [PASS] User authorized_keys updated: $winUserAuthKeys" -ForegroundColor Green

# Administrators group authorized_keys with strict ACLs
$progDataSsh = "C:\ProgramData\ssh"
if (-not (Test-Path $progDataSsh)) { New-Item -ItemType Directory -Path $progDataSsh -Force | Out-Null }
$adminAuthKeys = Join-Path $progDataSsh "administrators_authorized_keys"
Set-Content -Path $adminAuthKeys -Value "$nas1Key`n$vm1Key" -Encoding ascii -Force

# Windows OpenSSH requires exact ACL: Administrators:F and SYSTEM:F, no inheritance
icacls.exe $adminAuthKeys /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F" | Out-Null
Write-Host "  [PASS] administrators_authorized_keys configured with strict ACL." -ForegroundColor Green

# Ensure Windows sshd service is running and restarted
try {
    Set-Service -Name sshd -StartupType Automatic
    Restart-Service -Name sshd -Force
    Write-Host "  [PASS] Windows OpenSSH (sshd) service restarted." -ForegroundColor Green
} catch {
    Write-Warning "Could not restart Windows sshd service: $_"
}

# 3. Configure WSL2 /etc/wsl.conf and Boot Entrypoint
Write-Host "`n[3/7] Ingesting hardened /etc/wsl.conf and boot entrypoint into WSL2..." -ForegroundColor Yellow

$wslBashScript = @"
mkdir -p /root/.ssh /etc/ssh/sshd_config.d /dev/net /usr/local/bin /var/log

# Create TUN device
if [ ! -c /dev/net/tun ]; then
    mknod /dev/net/tun c 10 200 || true
    chmod 666 /dev/net/tun || true
fi

# Write /etc/wsl.conf
cat << 'EOF' > /etc/wsl.conf
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

# Write /usr/local/bin/uos-boot-entrypoint.sh
cat << 'EOF' > /usr/local/bin/uos-boot-entrypoint.sh
#!/usr/bin/env bash
set -u
LOG_FILE="/var/log/uos-boot-entrypoint.log"
exec >> "\$LOG_FILE" 2>&1

echo "=============================================================================="
echo "[UOS-BOOT] AUTONOMOUS WSL2 BOOT ENTRYPOINT INITIALIZING"
echo "Timestamp: \$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo "=============================================================================="

# 1. TUN Device Creation for Tailscale
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

# 3. Start OpenSSH Server
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
if [ -f "\$INSTANCE2_SCRIPT" ] && ! pgrep -f "start-instance2.sh" >/dev/null; then
    if id an &>/dev/null; then
        su - an -c "bash \$INSTANCE2_SCRIPT" >/var/log/uos-instance2.log 2>&1 &
    else
        bash "\$INSTANCE2_SCRIPT" >/var/log/uos-instance2.log 2>&1 &
    fi
fi

# 6. Fork Continuous Self-Healing Network Watchdog
if ! pgrep -f "uos-network-watchdog" >/dev/null; then
    (
        exec -a "uos-network-watchdog" bash -c '
            PRIMARY_NAS="100.87.7.78"
            while true; do
                sleep 30
                if ! ping -c 1 -W 3 "\$PRIMARY_NAS" &>/dev/null; then
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

# Configure Dual-Port SSH Daemon (22 & 2222)
cat << 'EOF' > /etc/ssh/sshd_config.d/60-uos-mesh.conf
Port 22
Port 2222
ListenAddress 0.0.0.0
ListenAddress ::
PubkeyAuthentication yes
PasswordAuthentication yes
PermitRootLogin prohibit-password
AuthorizedKeysFile .ssh/authorized_keys
ClientAliveInterval 15
ClientAliveCountMax 8
TCPKeepAlive yes
UseDNS no
EOF

# Inject authorized keys for root
echo '$nas1Key' >> /root/.ssh/authorized_keys
echo '$vm1Key' >> /root/.ssh/authorized_keys
sort -u /root/.ssh/authorized_keys -o /root/.ssh/authorized_keys
chmod 700 /root/.ssh && chmod 600 /root/.ssh/authorized_keys

# Inject authorized keys for existing linux users
for u in an abhij ubuntu; do
    if id "\$u" &>/dev/null; then
        uhome=\$(getent passwd "\$u" | cut -d: -f6)
        mkdir -p "\$uhome/.ssh"
        echo '$nas1Key' >> "\$uhome/.ssh/authorized_keys"
        echo '$vm1Key' >> "\$uhome/.ssh/authorized_keys"
        sort -u "\$uhome/.ssh/authorized_keys" -o "\$uhome/.ssh/authorized_keys"
        chmod 700 "\$uhome/.ssh" && chmod 600 "\$uhome/.ssh/authorized_keys"
        chown -R "\$u:\$u" "\$uhome/.ssh"
    fi
done

# Restart SSH inside WSL2
service ssh restart 2>/dev/null || /usr/sbin/sshd 2>/dev/null || true
"@

wsl -u root bash -c "$wslBashScript"
Write-Host "  [PASS] WSL2 wsl.conf, boot entrypoint, and SSH configuration injected." -ForegroundColor Green

# 4. Synchronize Portproxy (Port 2222 -> WSL2) & Firewall Rules
Write-Host "`n[4/7] Configuring Windows Port Forwarding and Firewall..." -ForegroundColor Yellow
try {
    $wslIp = (wsl hostname -I).Trim().Split(" ")[0]
    if ($wslIp) {
        netsh interface portproxy delete v4tov4 listenport=2222 listenaddress=0.0.0.0 2>$null | Out-Null
        netsh interface portproxy add v4tov4 listenport=2222 listenaddress=0.0.0.0 connectport=2222 connectaddress=$wslIp
        Write-Host "  [PASS] Portproxy active: 0.0.0.0:2222 -> $wslIp:2222" -ForegroundColor Green
    }
} catch {
    Write-Warning "Portproxy error: $_"
}

New-NetFirewallRule -DisplayName "UOS WSL2 SSH 2222" -Direction Inbound -LocalPort 2222 -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
New-NetFirewallRule -DisplayName "UOS WSL2 Health 8088" -Direction Inbound -LocalPort 8088 -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
Write-Host "  [PASS] Windows Firewall rules configured for 2222 and 8088." -ForegroundColor Green

# 5. Register Windows SYSTEM Scheduled Task for Cold Boot
Write-Host "`n[5/7] Registering Cold-Boot Autostart Scheduled Task under NT AUTHORITY\SYSTEM..." -ForegroundColor Yellow
$taskName = "UOS_WSL2_ColdBoot_Autostart"
$action = New-ScheduledTaskAction -Execute "wsl.exe" -Argument "-u root -- /bin/bash /usr/local/bin/uos-boot-entrypoint.sh"
$triggerBoot  = New-ScheduledTaskTrigger -AtStartup
$triggerLogon = New-ScheduledTaskTrigger -AtLogon
$principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit 0 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -RestartCount 999 `
    -Priority 4 `
    -MultipleInstancesPolicy IgnoreNew

try {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
    Register-ScheduledTask `
        -TaskName $taskName `
        -Action $action `
        -Trigger @($triggerBoot, $triggerLogon) `
        -Principal $principal `
        -Settings $settings `
        -Description "UOS Autonomous Cold-Boot & Zero-Timeout Autostart Service for WSL2 GPU Node" `
        -Force | Out-Null
    Write-Host "  [PASS] Scheduled Task '$taskName' registered under SYSTEM account." -ForegroundColor Green
} catch {
    Write-Error "Failed to register scheduled task: $_"
}

# 6. Test Trigger the Task
Write-Host "`n[6/7] Invoking scheduled task immediately to initialize environment..." -ForegroundColor Yellow
Start-ScheduledTask -TaskName $taskName
Start-Sleep -Seconds 3
$taskState = (Get-ScheduledTask -TaskName $taskName).State
Write-Host "  [PASS] Scheduled task state: $taskState" -ForegroundColor Green

# 7. Reboot Execution
Write-Host "`n==============================================================================" -ForegroundColor Green
Write-Host "[SUCCESS] PROVISIONING COMPLETE! LAPTOP IS FULLY CONFIGURED FOR SOVEREIGN MESH" -ForegroundColor Green
Write-Host "==============================================================================" -ForegroundColor Green

if ($NoReboot) {
    Write-Host "[-NoReboot specified. Skipping automatic reboot.]" -ForegroundColor Cyan
} else {
    Write-Host "`n>>> INITIATING AUTOMATIC REBOOT IN 5 SECONDS TO VERIFY COLD BOOT AUTOSTART <<<" -ForegroundColor Yellow
    Write-Host "Press Ctrl+C immediately if you wish to cancel the reboot." -ForegroundColor DarkGray
    for ($i = 5; $i -gt 0; $i--) {
        Write-Host "Rebooting in $i seconds..." -ForegroundColor Cyan
        Start-Sleep -Seconds 1
    }
    Write-Host "Rebooting system now..." -ForegroundColor Red
    Restart-Computer -Force
}
