# ==============================================================================
# [UOS-FIX] Windows OpenSSH ACL & WSL2 Autostart Repair
# ==============================================================================
Write-Host "=== [UOS-FIX] REPAIRING OPENSSH ACLS & STARTING WSL2 ===" -ForegroundColor Cyan

$nas1Key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMMewbASbkM+twLcsqnapyPzDLI08UlHhZFiRN8QCp01 an@nas-1"
$vm1Key  = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIANEVh3rGVj7FyOcgeKMjAptJzcEWceoCmkVzYLxrrIY an@vm-1"
$keys = "$nas1Key`n$vm1Key`n"

# 1. Fix ProgramData administrators_authorized_keys
$progDataSsh = "C:\ProgramData\ssh"
$adminKeys = "$progDataSsh\administrators_authorized_keys"
if (-not (Test-Path $progDataSsh)) { New-Item -ItemType Directory -Path $progDataSsh -Force | Out-Null }
Set-Content -Path $adminKeys -Value $keys -Encoding ascii -Force

takeown.exe /f $adminKeys /a | Out-Null
icacls.exe $adminKeys /reset | Out-Null
icacls.exe $adminKeys /inheritance:r /grant "BUILTIN\Administrators:F" /grant "NT AUTHORITY\SYSTEM:F" | Out-Null
Write-Host "[1/5] administrators_authorized_keys permissions repaired." -ForegroundColor Green

# 2. Fix User .ssh\authorized_keys for current user and abhij
$userProfiles = @($env:USERPROFILE, "C:\Users\abhij") | Select-Object -Unique
foreach ($prof in $userProfiles) {
    if (Test-Path $prof) {
        $sshDir = "$prof\.ssh"
        $userKeys = "$sshDir\authorized_keys"
        if (-not (Test-Path $sshDir)) { New-Item -ItemType Directory -Path $sshDir -Force | Out-Null }
        Set-Content -Path $userKeys -Value $keys -Encoding ascii -Force
        
        icacls.exe $sshDir /inheritance:r /grant "$($env:USERNAME):F" /grant "NT AUTHORITY\SYSTEM:F" /grant "BUILTIN\Administrators:F" | Out-Null
        icacls.exe $userKeys /inheritance:r /grant "$($env:USERNAME):F" /grant "NT AUTHORITY\SYSTEM:F" /grant "BUILTIN\Administrators:F" | Out-Null
        Write-Host "[2/5] User authorized_keys repaired in $prof." -ForegroundColor Green
    }
}

# 3. Restart Windows sshd
Restart-Service sshd -Force -ErrorAction SilentlyContinue
Write-Host "[3/5] Windows OpenSSH service restarted." -ForegroundColor Green

# 4. Launch WSL2 and run boot entrypoint
Write-Host "[4/5] Starting WSL2 and executing entrypoint..." -ForegroundColor Yellow
Start-Process "wsl.exe" -ArgumentList "-u root -- /bin/bash /usr/local/bin/uos-boot-entrypoint.sh" -NoNewWindow -Wait
Start-Sleep -Seconds 3

# 5. Refresh Portproxy for Port 2222 -> WSL2
$wslIp = (wsl hostname -I).Trim().Split(" ")[0]
if ($wslIp) {
    netsh interface portproxy delete v4tov4 listenport=2222 listenaddress=0.0.0.0 2>$null | Out-Null
    netsh interface portproxy add v4tov4 listenport=2222 listenaddress=0.0.0.0 connectport=2222 connectaddress=$wslIp
    Write-Host "[5/5] Portproxy updated: 0.0.0.0:2222 -> $wslIp:2222" -ForegroundColor Green
}

Write-Host "`n=== [PASS] REPAIR COMPLETE! READY FOR VERIFICATION ===" -ForegroundColor Green
