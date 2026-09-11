# ==============================================================================
# [C3I-SIL6-MSTS] Ultra-Robust Option A Orchestrator & Keep-Alive for razr15-1
# ==============================================================================
# Execute from Windows PowerShell (Run as Administrator) on razr15-1:
# powershell -ExecutionPolicy Bypass -File install-wsl2-option-a.ps1
# ==============================================================================

Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host "[C3I-OPTION-A] ULTRA-ROBUST PROVISIONING FOR WSL2 INSTANCE 2 (razr15-1)" -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Cyan

# 1. Deploy Hardened C:\Users\abhij\.wslconfig (Prevents VM Idle Shutdown)
Write-Host "`n[1/6] Deploying hardened .wslconfig to host user profile..." -ForegroundColor Yellow
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
Write-Host "  [+] .wslconfig deployed to $wslConfigPath" -ForegroundColor Green

# 2. Inject Authorized Keys into Windows Host OpenSSH
Write-Host "`n[2/6] Authorizing nas-1 and vm-1 ED25519 keys on Windows Host..." -ForegroundColor Yellow
$winSshDir = Join-Path $userProfile ".ssh"
if (-not (Test-Path $winSshDir)) { New-Item -ItemType Directory -Path $winSshDir -Force | Out-Null }
$winAuthKeys = Join-Path $winSshDir "authorized_keys"

$nas1Pub = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMMewbASbkM+twLcsqnapyPzDLI08UlHhZFiRN8QCp01 an@nas-1"
$vm1Pub  = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIANEVh3rGVj7FyOcgeKMjAptJzcEWceoCmkVzYLxrrIY an@vm-1"

$existingKeys = if (Test-Path $winAuthKeys) { Get-Content $winAuthKeys } else { @() }
$newKeys = @()
if (-not ($existingKeys -contains $nas1Pub)) { $newKeys += $nas1Pub }
if (-not ($existingKeys -contains $vm1Pub))  { $newKeys += $vm1Pub }
if ($newKeys.Count -gt 0) {
    Add-Content -Path $winAuthKeys -Value ($newKeys -join "`n") -Encoding UTF8
    Write-Host "  [+] Added $($newKeys.Count) keys to Windows host $winAuthKeys" -ForegroundColor Green
} else {
    Write-Host "  [=] Keys already authorized in Windows host." -ForegroundColor DarkGray
}

# 3. Deploy wsl.conf into WSL2
Write-Host "`n[3/6] Injecting /etc/wsl.conf into WSL2..." -ForegroundColor Yellow
$wslConfContent = @"
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
"@
wsl -u root bash -c "cat << 'EOF' > /etc/wsl.conf`n$wslConfContent`nEOF"
Write-Host "  [+] /etc/wsl.conf injected." -ForegroundColor Green

# 4. Fetch and Execute setup-option-a-wsl2-sshd.sh
Write-Host "`n[4/6] Executing setup-option-a-wsl2-sshd.sh inside WSL2..." -ForegroundColor Yellow
$scriptUrl = "http://nas-1.tail55d152.ts.net:4100/files/ops/nodes/razr15-1-wsl2/setup-option-a-wsl2-sshd.sh"
$setupCmd = @"
if [ -f "/mnt/c/Users/abhij/NAS-setup/uos/ops/nodes/razr15-1-wsl2/setup-option-a-wsl2-sshd.sh" ]; then
    bash /mnt/c/Users/abhij/NAS-setup/uos/ops/nodes/razr15-1-wsl2/setup-option-a-wsl2-sshd.sh
else
    curl -fsSL "$scriptUrl" | bash || curl -fsSL "http://100.87.7.78:4100/files/ops/nodes/razr15-1-wsl2/setup-option-a-wsl2-sshd.sh" | bash
fi
"@
wsl -u root bash -c "$setupCmd"

# 5. Configure Windows Port Forwarding (Port 2222 -> WSL2 Port 2222) & Firewall
Write-Host "`n[5/6] Setting up fallback port proxy (Port 2222 -> WSL2) and Firewall rules..." -ForegroundColor Yellow
try {
    $wslIp = (wsl hostname -I).Trim().Split(" ")[0]
    if ($wslIp) {
        netsh interface portproxy delete v4tov4 listenport=2222 listenaddress=0.0.0.0 2>$null | Out-Null
        netsh interface portproxy add v4tov4 listenport=2222 listenaddress=0.0.0.0 connectport=2222 connectaddress=$wslIp
        Write-Host "  [+] Portproxy configured: 0.0.0.0:2222 -> $wslIp:2222" -ForegroundColor Green
    }
    New-NetFirewallRule -DisplayName "UOS WSL2 SSH 2222" -Direction Inbound -LocalPort 2222 -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
    New-NetFirewallRule -DisplayName "UOS WSL2 Health 8088" -Direction Inbound -LocalPort 8088 -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
    Write-Host "  [+] Windows Firewall rules configured for 2222 and 8088." -ForegroundColor Green
} catch {
    Write-Host "  [!] Portproxy notice: $($_.Exception.Message)" -ForegroundColor DarkYellow
}

# 6. Windows Scheduled Task for Permanent Keepalive
Write-Host "`n[6/6] Registering permanent background keepalive task..." -ForegroundColor Yellow
$taskName = "UOS_WSL2_Permanent_KeepAlive"
$action = New-ScheduledTaskAction -Execute "wsl.exe" -Argument "-u root -- systemctl default"
$trigger1 = New-ScheduledTaskTrigger -AtLogon
$trigger2 = New-ScheduledTaskTrigger -AtStartup
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 0 -RestartInterval (New-TimeSpan -Minutes 1) -RestartCount 999

try {
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger @($trigger1, $trigger2) -Settings $settings -Force -ErrorAction Stop | Out-Null
    Write-Host "  [+] Scheduled Task '$taskName' registered to run on boot and logon." -ForegroundColor Green
} catch {
    Write-Host "  [!] Scheduled task note: $($_.Exception.Message)" -ForegroundColor DarkYellow
}

Write-Host "`n==============================================================================" -ForegroundColor Green
Write-Host "[SUCCESS] ULTRA-ROBUST OPTION A FULLY DEPLOYED!" -ForegroundColor Green
Write-Host "WSL2 Tailscale Node:  razr15-wsl2" -ForegroundColor Cyan
Write-Host "Windows Host IP:      100.114.9.28" -ForegroundColor Cyan
Write-Host "Connect via:" -ForegroundColor White
Write-Host "  1. Direct SSH:        ssh an@razr15-wsl2" -ForegroundColor White
Write-Host "  2. Tailscale SSH:     tailscale ssh an@razr15-wsl2" -ForegroundColor White
Write-Host "  3. Dual-Port SSH:     ssh -p 2222 an@100.114.9.28" -ForegroundColor White
Write-Host "==============================================================================" -ForegroundColor Green
