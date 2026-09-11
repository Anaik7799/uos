# ==============================================================================
# [C3I-SIL6-MSTS] Option A: Windows PowerShell Setup & Keep-Alive Runner for razr15-1 WSL2
# ==============================================================================
# Execute from Windows PowerShell on razr15-1 (Razer Blade 15):
# powershell -ExecutionPolicy Bypass -File install-wsl2-option-a.ps1
# ==============================================================================

Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host "[C3I-OPTION-A] AUTOMATED PROVISIONING OF WSL2 INSTANCE 2 (razr15-1)" -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Cyan

# 1. Check WSL Status
Write-Host "`n[1/5] Checking WSL installation and running distributions..." -ForegroundColor Yellow
$wslDistros = wsl -l -v
$wslDistros | ForEach-Object { Write-Host "  $_" }

# 2. Deploy wsl.conf into WSL2
Write-Host "`n[2/5] Injecting /etc/wsl.conf into WSL2 to enable systemd..." -ForegroundColor Yellow
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
Write-Host "  [+] /etc/wsl.conf deployed." -ForegroundColor Green

# 3. Fetch and Run setup-option-a-wsl2-sshd.sh inside WSL2
Write-Host "`n[3/5] Executing turnkey setup-option-a-wsl2-sshd.sh inside WSL2..." -ForegroundColor Yellow
$scriptUrl = "http://nas-1.tail55d152.ts.net:4100/files/ops/nodes/razr15-1-wsl2/setup-option-a-wsl2-sshd.sh"
$setupCmd = @"
if [ -f "/mnt/c/Users/an/NAS-setup/uos/ops/nodes/razr15-1-wsl2/setup-option-a-wsl2-sshd.sh" ]; then
    bash /mnt/c/Users/an/NAS-setup/uos/ops/nodes/razr15-1-wsl2/setup-option-a-wsl2-sshd.sh
else
    curl -fsSL "$scriptUrl" | bash || curl -fsSL "http://100.87.7.78:4100/files/ops/nodes/razr15-1-wsl2/setup-option-a-wsl2-sshd.sh" | bash
fi
"@

# Run directly inside WSL as root
wsl -u root bash -c "$setupCmd"

# 4. Create Windows Scheduled Task to keep WSL2 and SSH alive in background
Write-Host "`n[4/5] Registering Windows Scheduled Task for persistent WSL2 background execution..." -ForegroundColor Yellow
$taskName = "UOS_WSL2_KeepAlive"
$action = New-ScheduledTaskAction -Execute "wsl.exe" -Argument "-u root -- systemctl default"
$trigger = New-ScheduledTaskTrigger -AtLogon
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 0

try {
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Force -ErrorAction Stop | Out-Null
    Write-Host "  [+] Scheduled Task '$taskName' successfully registered." -ForegroundColor Green
} catch {
    Write-Host "  [!] Note: Run as Administrator to register persistent background task." -ForegroundColor DarkYellow
}

# 5. Output Verification
Write-Host "`n[5/5] Checking WSL2 IP and Tailscale status..." -ForegroundColor Yellow
$wslIp = wsl bash -c "tailscale ip -4 2>/dev/null || hostname -I | awk '{print \$1}'"
Write-Host "  WSL2 IP / Tailscale IP: $wslIp" -ForegroundColor Cyan

Write-Host "`n==============================================================================" -ForegroundColor Green
Write-Host "[SUCCESS] OPTION A FULLY PROVISIONED ON razr15-1 WSL2!" -ForegroundColor Green
Write-Host "You can now connect from nas-1 via:" -ForegroundColor Green
Write-Host "  ssh an@$wslIp" -ForegroundColor White
Write-Host "  or: tailscale ssh an@razr15-wsl2" -ForegroundColor White
Write-Host "==============================================================================" -ForegroundColor Green
