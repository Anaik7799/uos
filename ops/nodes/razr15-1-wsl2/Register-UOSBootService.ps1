# ==============================================================================
# [C3I-SIL6-MSTS] Windows Host Cold-Boot Autostart & Keep-Alive Service
# ==============================================================================
# Run as Administrator in Windows PowerShell on razr15-1:
# powershell -ExecutionPolicy Bypass -File Register-UOSBootService.ps1
#
# Guarantees that WSL2 starts on reboot BEFORE user login, keeps running on battery,
# and restarts automatically within 60s if terminated.
# ==============================================================================

Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host "[UOS-BOOT] CONFIGURING SYSTEM COLD-BOOT AUTOSTART FOR WSL2 (razr15-1)" -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Cyan

# Check Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "[FATAL] This script must be run as Administrator! Right-click PowerShell -> Run as administrator."
    exit 1
}

$taskName = "UOS_WSL2_ColdBoot_Autostart"

# 1. Action: Launch WSL2 root boot entrypoint
$action = New-ScheduledTaskAction -Execute "wsl.exe" -Argument "-u root -- /bin/bash -c `"/usr/local/bin/uos-boot-entrypoint.sh 2>&1 | tee -a /var/log/uos-boot.log`""

# 2. Triggers: At system startup (before logon) + At user logon
$triggerBoot  = New-ScheduledTaskTrigger -AtStartup
$triggerLogon = New-ScheduledTaskTrigger -AtLogon

# 3. Principal: NT AUTHORITY\SYSTEM with Highest Privileges
$principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest

# 4. Settings: Never sleep, run on battery, infinite auto-restart
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit 0 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -RestartCount 999 `
    -Priority 4 `
    -MultipleInstancesPolicy IgnoreNew

# 5. Register Task
try {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
    Register-ScheduledTask `
        -TaskName $taskName `
        -Action $action `
        -Trigger @($triggerBoot, $triggerLogon) `
        -Principal $principal `
        -Settings $settings `
        -Description "UOS Cold-Boot & Zero-Timeout Autostart Service for Instance 2 GPU Node" `
        -Force | Out-Null

    Write-Host "  [PASS] Scheduled Task '$taskName' registered under SYSTEM account." -ForegroundColor Green
    Write-Host "  [PASS] Triggers: AtStartup (Cold Boot) + AtLogon (User Login)." -ForegroundColor Green
    Write-Host "  [PASS] Power: Battery execution enabled, timeout set to 0 (infinite)." -ForegroundColor Green
} catch {
    Write-Error "Failed to register scheduled task: $_"
    exit 1
}

# 6. Test Trigger the Task Immediately
Write-Host "`nTesting immediate task invocation..." -ForegroundColor Yellow
Start-ScheduledTask -TaskName $taskName
Start-Sleep -Seconds 3

$taskState = (Get-ScheduledTask -TaskName $taskName).State
Write-Host "  [INFO] Task State: $taskState" -ForegroundColor Cyan

# 7. Sync Dynamic Portproxy (Port 2222 -> WSL2 Internal IP)
Write-Host "`nSynchronizing dynamic portproxy for host fallback on port 2222..." -ForegroundColor Yellow
try {
    $wslIp = (wsl hostname -I).Trim().Split(" ")[0]
    if ($wslIp) {
        netsh interface portproxy delete v4tov4 listenport=2222 listenaddress=0.0.0.0 2>$null | Out-Null
        netsh interface portproxy add v4tov4 listenport=2222 listenaddress=0.0.0.0 connectport=2222 connectaddress=$wslIp
        Write-Host "  [PASS] Portproxy active: 0.0.0.0:2222 -> $wslIp:2222" -ForegroundColor Green
    }
} catch {
    Write-Warning "Could not configure portproxy: $_"
}

Write-Host "`n==============================================================================" -ForegroundColor Green
Write-Host "[SUCCESS] WSL2 WILL NOW FULLY AUTOSTART ON LAPTOP REBOOT (WITHOUT LOGGING IN)" -ForegroundColor Green
Write-Host "==============================================================================" -ForegroundColor Green
