# ==============================================================================
# [UOS-RAZR15-1] Resync WSL2 Port 2222 SSH & Install Modular MAX + Mojo
# Run in Windows PowerShell (Admin) on razr15-1:
#   irm http://100.87.7.78:8999/fix-2222-and-install-max-mojo.ps1 | iex
# ==============================================================================
$ErrorActionPreference = "Continue"
Write-Host "=== [1/4] Fixing Windows OpenSSH Keys & Starting WSL2 ===" -ForegroundColor Cyan

$pubKeys = @(
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOqwuZCYQ9WlL2wIT3fBIQ6aH6V+IW8wisxlWYxUa9l0 an@nas-1",
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMk1aeYZE0K2I5JGn8I32+w4/W1r/G/H/yH2E0m2+mY8 an@vm-1",
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMMewbASbkM+twLcsqnapyPzDLI08UlHhZFiRN8QCp01 an@nas-1",
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIANEVh3rGVj7FyOcgeKMjAptJzcEWceoCmkVzYLxrrIY an@vm-1"
)

# 1. Start WSL2 and run canonical setup-option-a-wsl2-sshd.sh + ensure live keys
wsl -u root -- bash -c "curl -fsSL http://100.87.7.78:8999/setup-option-a-wsl2-sshd.sh | bash || true"
wsl -u root -- bash -c "mkdir -p /run/sshd /home/an/.ssh /root/.ssh; grep -q 'Port 2222' /etc/ssh/sshd_config || echo 'Port 2222' >> /etc/ssh/sshd_config; service ssh restart || /usr/sbin/sshd"
foreach ($k in $pubKeys) {
    wsl -u root -- bash -c "grep -qF '$k' /home/an/.ssh/authorized_keys 2>/dev/null || echo '$k' >> /home/an/.ssh/authorized_keys; chown -R an:an /home/an/.ssh; chmod 700 /home/an/.ssh; chmod 600 /home/an/.ssh/authorized_keys"
    wsl -u root -- bash -c "grep -qF '$k' /root/.ssh/authorized_keys 2>/dev/null || echo '$k' >> /root/.ssh/authorized_keys; chmod 700 /root/.ssh; chmod 600 /root/.ssh/authorized_keys"
}

Write-Host "=== [2/4] Updating Windows netsh portproxy 0.0.0.0:2222 -> WSL2 IP:2222 ===" -ForegroundColor Cyan
$wslIp = (wsl hostname -I).Trim().Split(" ")[0]
Write-Host "Detected active WSL2 IP: $wslIp" -ForegroundColor Green
netsh interface portproxy delete v4tov4 listenport=2222 listenaddress=0.0.0.0 2>$null | Out-Null
netsh interface portproxy add v4tov4 listenport=2222 listenaddress=0.0.0.0 connectport=2222 connectaddress=$wslIp
netsh advfirewall firewall add rule name="WSL2_SSH_2222" dir=in action=allow protocol=TCP localport=2222 2>$null | Out-Null

Write-Host "=== [3/4] Fixing Windows OpenSSH authorized_keys ACLs ===" -ForegroundColor Cyan
$sshDir = "$env:USERPROFILE\.ssh"
New-Item -ItemType Directory -Force -Path $sshDir | Out-Null
Set-Content -Path "$sshDir\authorized_keys" -Value ($pubKeys -join "`r`n") -Encoding Ascii
icacls "$sshDir\authorized_keys" /inheritance:r /grant "SYSTEM:(F)" /grant "Administrators:(F)" /grant "$($env:USERNAME):(R,W)" | Out-Null
if (Test-Path "$env:ProgramData\ssh") {
    Set-Content -Path "$env:ProgramData\ssh\administrators_authorized_keys" -Value ($pubKeys -join "`r`n") -Encoding Ascii
    icacls "$env:ProgramData\ssh\administrators_authorized_keys" /inheritance:r /grant "SYSTEM:(F)" /grant "Administrators:(F)" | Out-Null
}
Restart-Service sshd -ErrorAction SilentlyContinue

Write-Host "=== [4/4] Launching Modular MAX & Mojo Installer Inside WSL2 as 'an' ===" -ForegroundColor Cyan
wsl -u an -- bash -c "curl -fsSL http://100.87.7.78:8999/install_max_mojo_wsl2.sh | bash"
