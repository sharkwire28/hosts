# ================================
# Self-Elevating Hosts Updater
# Author: Gary Magallanes
# Date: Feb 27, 2026
# Version: 3.0 - GitHub Remote Execution
# Run via PowerShell using irm (Invoke-RestMethod)
# 
# Execute command using GitHub or custom domain:
# Command: irm https://raw.githubusercontent.com/sharkwire28/hosts/main/scripts/updatesv2.ps1 | iex
# Command: irm http://it.acrogroup.net/script/updatesv2.ps1 | iex
# 
# Or with execution policy bypass:
# Command: powershell -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/sharkwire28/hosts/main/scripts/updatesv2.ps1 | iex"
# Command: powershell -ExecutionPolicy Bypass -Command "irm http://it.acrogroup.net/script/updatesv2.ps1 | iex"
# ================================

$ErrorActionPreference = "Stop"
$global:ScriptResult = 0

# ---- Script Configuration ----
$scriptUrl = "https://raw.githubusercontent.com/sharkwire28/hosts/main/scripts/updatesv2.ps1"
$repoRawUrl = "https://raw.githubusercontent.com/sharkwire28/hosts/main/system/hosts"

# ---- Self Elevation ----
$identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)

if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {

    Write-Host "Requesting administrator privileges..." -ForegroundColor Yellow

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName  = "powershell.exe"
    $psi.Arguments = "-ExecutionPolicy Bypass -NoProfile -Command `"irm $scriptUrl | iex`""
    $psi.Verb      = "runas"
    $psi.UseShellExecute = $true
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Normal

    [System.Diagnostics.Process]::Start($psi) | Out-Null
    return
}

Write-Host "`n=== SYSTEM FILE UPDATER ===" -ForegroundColor Cyan
Write-Host "Running with administrator privileges" -ForegroundColor Green

# ---- Paths ----
$hostsPath   = "C:\Windows\System32\drivers\etc\hosts"
$workDir     = "C:\ProgramData\HostsUpdater"
$tempDir     = "$workDir\temp"
$tempPath    = "$tempDir\hosts_new"
$logPath     = "$workDir\hosts-updater.log"
$etagPath    = "$workDir\etag.txt"
$maxBackups  = 10  # Keep only last 10 backups

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

New-Item -Path $workDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
New-Item -Path $tempDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")

    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "$ts [$Level] - $Message"
    Add-Content -Path $logPath -Value $entry

    switch ($Level) {
        "ERROR"   { Write-Host $entry -ForegroundColor Red }
        "WARNING" { Write-Host $entry -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $entry -ForegroundColor Green }
        default   { Write-Host $entry }
    }
}

function Manage-Backups {
    $backups = Get-ChildItem -Path $workDir -Filter "hosts-*.bak" |
               Sort-Object CreationTime -Descending

    if ($backups.Count -gt $maxBackups) {
        $backups | Select-Object -Skip $maxBackups | Remove-Item -Force
        Write-Log "Old backups removed."
    }
}

try {

    Write-Log "Starting update check."

    # HEAD request for ETag
    $head = [System.Net.HttpWebRequest]::Create($repoRawUrl)
    $head.Method = "HEAD"
    $head.Timeout = 10000
    $response = $head.GetResponse()
    $remoteETag = $response.Headers["ETag"]
    $response.Close()

    $localETag = if (Test-Path $etagPath) { Get-Content $etagPath -Raw } else { "" }

    if ($remoteETag -and ($remoteETag -eq $localETag)) {
        Write-Log "No changes detected (ETag match)."
        Write-Host "`nSystem already up to date." -ForegroundColor Green
        return
    }

    Write-Log "Change detected. Downloading latest version..."

    $content = Invoke-RestMethod -Uri $repoRawUrl -TimeoutSec 20
    $content | Out-File -FilePath $tempPath -Encoding UTF8 -Force

    if ((Get-Item $tempPath).Length -eq 0) {
        throw "Downloaded file is empty."
    }

    $currentHash = if (Test-Path $hostsPath) {
        (Get-FileHash $hostsPath -Algorithm SHA256).Hash
    } else { "" }

    $newHash = (Get-FileHash $tempPath -Algorithm SHA256).Hash

    if ($currentHash -eq $newHash) {
        Write-Log "System file already matches remote version."
        Remove-Item $tempPath -Force
        return
    }

    Write-Log "Updating system file..." "WARNING"

    if (Test-Path $hostsPath) {
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $backupPath = "$workDir\hosts-$timestamp.bak"
        Copy-Item $hostsPath $backupPath -Force
        Write-Log "Backup created." "SUCCESS"
        Manage-Backups
    }

    Move-Item -Path $tempPath -Destination $hostsPath -Force
    Write-Log "System file updated successfully." "SUCCESS"

    if ($remoteETag) {
        $remoteETag | Set-Content $etagPath -Force
    }

    ipconfig /flushdns | Out-Null
    Write-Log "DNS cache flushed." "SUCCESS"

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  SYSTEM UPDATED SUCCESSFULLY!  " -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""

}
catch {
    $global:ScriptResult = 99
    Write-Log "CRITICAL ERROR: $($_.Exception.Message)" "ERROR"
}

# ---- Script Finished ----
Write-Host "`nScript finished. You may close this window." -ForegroundColor Cyan
