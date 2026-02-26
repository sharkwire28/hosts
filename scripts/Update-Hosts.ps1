# ================================
# Self-Elevating Hosts Updater
# Author: Gary Magallanes
# Date: Feb 26, 2026
# ================================

# ---- Self Elevation ----
if (-not ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent() `
    ).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
{
    Write-Host "Restarting as Administrator..."
    Start-Process powershell `
        -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" `
        -Verb RunAs
    exit
}

# ---- Paths ----
$hostsPath  = "C:\Windows\System32\drivers\etc\hosts"
$backupPath = "C:\Windows\System32\drivers\etc\hosts.bak"
$tempPath   = "$env:TEMP\hosts_new"

$repoRawUrl = "https://raw.githubusercontent.com/sharkwire28/hosts/refs/heads/main/system/hosts"

Write-Host "Downloading latest hosts file..."

try {
    Invoke-WebRequest -Uri $repoRawUrl -OutFile $tempPath -UseBasicParsing
}
catch {
    Write-Host "Download failed."
    exit 1
}

# ---- Compute Hashes ----
if (Test-Path $hostsPath) {
    $currentHash = (Get-FileHash $hostsPath -Algorithm SHA256).Hash
} else {
    $currentHash = ""
}

$newHash = (Get-FileHash $tempPath -Algorithm SHA256).Hash

# ---- Compare ----
if ($currentHash -eq $newHash) {
    Write-Host "Hosts file is already up to date. No changes made."
    Remove-Item $tempPath -Force
    exit
}

Write-Host "Change detected. Updating hosts file..."

# ---- Backup ----
if (Test-Path $hostsPath) {
    Copy-Item $hostsPath $backupPath -Force
    Write-Host "Backup created at $backupPath"
}

# ---- Replace ----
Copy-Item $tempPath $hostsPath -Force
Remove-Item $tempPath -Force

# ---- Flush DNS ----
ipconfig /flushdns | Out-Null

Write-Host "Hosts file updated successfully."
