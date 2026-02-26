# ================================
# Self-Elevating Hosts Updater
# Author: Gary Magallanes
# Date: Feb 26, 2026
# Run via PowerShell 
# Command: powershell -ExecutionPolicy Bypass -Command "iwr https://raw.githubusercontent.com/sharkwire28/hosts/main/scripts/Update-Hosts.ps1 -UseBasicParsing | iex"
# ================================

$ErrorActionPreference = "Stop"

# ---- Self-Elevation ----
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Start-Process powershell `
        -ArgumentList "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`"" `
        -Verb RunAs -WindowStyle Hidden
    exit
}

# ---- Paths ----
$hostsPath   = "C:\Windows\System32\drivers\etc\hosts"
$workDir     = "C:\ProgramData\HostsUpdater"
$tempPath    = "$workDir\hosts_new"
$logPath     = "$workDir\hosts-updater.log"
$etagPath    = "$workDir\etag.txt"

$repoRawUrl  = "https://raw.githubusercontent.com/sharkwire28/hosts/main/system/hosts"

# ---- Ensure Working Directory ----
if (!(Test-Path $workDir)) { New-Item -Path $workDir -ItemType Directory -Force | Out-Null }

# ---- Logging Function ----
function Write-Log { param([string]$msg) $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"; Add-Content $logPath "$ts - $msg" }

try {
    Write-Log "Starting hourly update check."

    # Force TLS 1.2
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    # ---- Check GitHub ETag for fast skip ----
    $response = Invoke-WebRequest -Uri $repoRawUrl -Method Head -TimeoutSec 15
    $remoteETag = $response.Headers.ETag
    $lastETag   = if (Test-Path $etagPath) { Get-Content $etagPath -Raw } else { "" }

    if ($remoteETag -eq $lastETag) {
        Write-Log "No changes detected on GitHub. Skipping download."
        exit
    }

    Write-Log "New version detected. Downloading file..."
    Invoke-WebRequest -Uri $repoRawUrl -OutFile $tempPath -UseBasicParsing -TimeoutSec 20

    # Save ETag locally
    $remoteETag | Set-Content $etagPath -Force

    # ---- Compute Hashes ----
    $currentHash = if (Test-Path $hostsPath) { (Get-FileHash $hostsPath -Algorithm SHA256).Hash } else { "" }
    $newHash     = (Get-FileHash $tempPath -Algorithm SHA256).Hash

    if ($currentHash -eq $newHash) {
        Write-Log "System file already up to date. Removing temp file."
        Remove-Item $tempPath -Force
        exit
    }

    Write-Log "Change detected! Updating file..."

    # ---- Backup ----
    if (Test-Path $hostsPath) {
        $timestamp  = Get-Date -Format "yyyyMMdd-HHmmss"
        $backupPath = "$workDir\hosts-$timestamp.bak"
        Copy-Item $hostsPath $backupPath -Force
        Write-Log "Backup created." #Removed $backupPath
    }

    # ---- Replace Hosts ----
    Copy-Item $tempPath $hostsPath -Force
    Remove-Item $tempPath -Force

    # ---- Flush DNS ----
    ipconfig /flushdns | Out-Null

    Write-Log "File updated successfully."

} catch {
    Write-Log "ERROR: $($_.Exception.Message)"
}
