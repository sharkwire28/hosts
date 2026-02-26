# ================================
# Self-Elevating Hosts Updater
# Author: Gary Magallanes
# Date: Feb 26, 2026
# Run via PowerShell 
# Execute command using the it.acrogroup.net domain or via raw.githubusercontent.com
# Command: powershell -ExecutionPolicy Bypass -Command "iwr https://raw.githubusercontent.com/sharkwire28/hosts/main/scripts/updates.ps1 -UseBasicParsing | iex"
# Command: powershell -ExecutionPolicy Bypass -Command "iwr http://it.acrogroup.net/script/updates.ps1 -UseBasicParsing | iex"
# ================================

$ErrorActionPreference = "Stop"

# ---- Self-Elevation ----
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Start-Process powershell `
        -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" `
        -Verb RunAs
    exit
}

# ---- Paths ----
$hostsPath   = "C:\Windows\System32\drivers\etc\hosts"
$workDir     = "C:\ProgramData\HostsUpdater"
$tempDir     = "$workDir\temp"
$tempPath    = "$tempDir\hosts_new"
$logPath     = "$workDir\hosts-updater.log"
$etagPath    = "$workDir\etag.txt"
$repoRawUrl  = "https://raw.githubusercontent.com/sharkwire28/hosts/main/system/hosts"

# ---- Prepare Directories ----
if (!(Test-Path $workDir)) { New-Item -Path $workDir -ItemType Directory -Force | Out-Null }
if (!(Test-Path $tempDir)) { 
    New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
    (Get-Item $tempDir).Attributes = 'Hidden'
}

# ---- Logging Function ----
function Write-Log { 
    param([string]$msg)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "$ts - $msg"
    Add-Content $logPath $line
    Write-Host $line
}

try {
    Write-Log "Starting update check."

    # Force TLS 1.2 for GitHub
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    # ---- Check GitHub ETag ----
    $response = Invoke-WebRequest -Uri $repoRawUrl -Method Head -TimeoutSec 10
    $remoteETag = $response.Headers.ETag
    $lastETag   = if (Test-Path $etagPath) { Get-Content $etagPath -Raw } else { "" }

    if ($remoteETag -eq $lastETag) {
        Write-Log "No changes detected on GitHub. Skipping download."
        exit
    }

    Write-Log "New version detected. Downloading file..."
    Invoke-WebRequest -Uri $repoRawUrl -OutFile $tempPath -UseBasicParsing -TimeoutSec 20

    # Remove "downloaded from internet" security warning
    if (Test-Path $tempPath) { Unblock-File $tempPath -ErrorAction SilentlyContinue }

    # Save ETag locally
    $remoteETag | Set-Content $etagPath -Force

    # ---- Compare Hashes ----
    $currentHash = if (Test-Path $hostsPath) { (Get-FileHash $hostsPath -Algorithm SHA256).Hash } else { "" }
    $newHash     = (Get-FileHash $tempPath -Algorithm SHA256).Hash

    if ($currentHash -eq $newHash) {
        Write-Log "System file already up to date. Removing temp file."
        Remove-Item $tempPath -Force
        exit
    }

    Write-Log "Change detected! Updating file..."

    # ---- Backup Current Hosts ----
    if (Test-Path $hostsPath) {
        $timestamp  = Get-Date -Format "yyyyMMdd-HHmmss"
        $backupPath = "$workDir\hosts-$timestamp.bak"
        Copy-Item $hostsPath $backupPath -Force
        Write-Log "Backup created"
    }

    # ---- Replace Hosts ----
    Copy-Item $tempPath $hostsPath -Force
    Remove-Item $tempPath -Force

    # ---- Flush DNS ----
    ipconfig /flushdns | Out-Null
    Write-Log "DNS cache flushed."

    Write-Log "File updated successfully."

} catch {
    Write-Log "ERROR: $($_.Exception.Message)"
}
