# ================================
# Self-Elevating Hosts Updater
# Author: Gary Magallanes
# Date: Feb 27, 2026
# Version: 3.0 - GitHub Remote Execution
# Run via PowerShell using irm (Invoke-RestMethod)
# 
# Execute command using GitHub or custom domain:
# Command: irm https://raw.githubusercontent.com/sharkwire28/hosts/main/scripts/updatesv3.ps1 | iex
# Command: irm http://it.acrogroup.net/script/updatesv3.ps1 | iex
# 
# Or with execution policy bypass:
# Command: powershell -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/sharkwire28/hosts/main/scripts/updatesv3.ps1 | iex"
# Command: powershell -ExecutionPolicy Bypass -Command "irm http://it.acrogroup.net/script/updatesv3.ps1 | iex"
# ================================

$ErrorActionPreference = "Stop"

# ---- Script Configuration ----
$scriptUrl = "https://raw.githubusercontent.com/sharkwire28/hosts/main/scripts/updatesv3.ps1"
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
    exit
}

Write-Host "`n=== SYSTEM FILE UPDATER ===" -ForegroundColor Cyan
Write-Host "Running with administrator privileges" -ForegroundColor Green

# ---- Paths (UNCHANGED AS REQUESTED) ----
$hostsPath   = "C:\Windows\System32\drivers\etc\hosts"
$workDir     = "C:\ProgramData\HostsUpdater"
$tempDir     = "$workDir\temp"
$tempPath    = "$tempDir\hosts_new"
$logPath     = "$workDir\hosts-updater.log"
$etagPath    = "$workDir\etag.txt"
$maxBackups  = 10  # Keep only last 10 backups

# ---- Ensure TLS 1.2 ----
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ---- Prepare Directories ----
New-Item -Path $workDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
New-Item -Path $tempDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

# ---- Logging ----
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

# ---- Backup Rotation ----
function Manage-Backups {
    $backups = Get-ChildItem -Path $workDir -Filter "hosts-*.bak" |
               Sort-Object CreationTime -Descending

    if ($backups.Count -gt $maxBackups) {
        $backups | Select-Object -Skip $maxBackups | Remove-Item -Force
        Write-Log "Old backups removed." "INFO"
    }
}

# ---- Begin Update ----
try {
    Write-Log "Starting update check."

    # ---- Check Remote ETag ----
    $head = [System.Net.HttpWebRequest]::Create($repoRawUrl)
    $head.Method = "HEAD"
    $head.Timeout = 10000
    $response = $head.GetResponse()
    $remoteETag = $response.Headers["ETag"]
    $response.Close()

    $localETag = if (Test-Path $etagPath) {
        Get-Content $etagPath -Raw
    } else { "" }

    if ($remoteETag -and ($remoteETag -eq $localETag)) {
        Write-Log "No changes detected (ETag match)."
        exit 0
    }

    Write-Log "Change detected. Downloading latest version..."

    # ---- Download Using Invoke-RestMethod ----
    $downloadSuccess = $false
    for ($i = 1; $i -le 3; $i++) {
        try {
            $content = Invoke-RestMethod -Uri $repoRawUrl -TimeoutSec 20
            $content | Out-File -FilePath $tempPath -Encoding UTF8 -Force
            $downloadSuccess = $true
            break
        }
        catch {
            Write-Log "Download attempt $i failed. Retrying..." "WARNING"
            Start-Sleep -Seconds 3
        }
    }

    if (-not $downloadSuccess) {
        throw "Download failed after 3 attempts."
    }

    if ((Get-Item $tempPath).Length -eq 0) {
        throw "Downloaded file is empty."
    }

    # ---- Hash Compare ----
    $currentHash = if (Test-Path $hostsPath) {
        (Get-FileHash $hostsPath -Algorithm SHA256).Hash
    } else { "" }

    $newHash = (Get-FileHash $tempPath -Algorithm SHA256).Hash

    if ($currentHash -eq $newHash) {
        Write-Log "Hosts file already matches remote version."
        Remove-Item $tempPath -Force
        exit 0
    }

    Write-Log "Updating system hosts file..." "WARNING"

    # ---- Backup ----
    if (Test-Path $hostsPath) {
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $backupPath = "$workDir\hosts-$timestamp.bak"
        Copy-Item $hostsPath $backupPath -Force
        Write-Log "Backup created." "SUCCESS"
        Manage-Backups
    }

    # ---- Replace File ----
    Move-Item -Path $tempPath -Destination $hostsPath -Force
    Write-Log "Hosts file updated successfully." "SUCCESS"

    # ---- Save ETag ----
    if ($remoteETag) {
        $remoteETag | Set-Content $etagPath -Force
    }

    # ---- Flush DNS ----
    ipconfig /flushdns | Out-Null
    Write-Log "DNS cache flushed." "SUCCESS"

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  SYSTEM UPDATED SUCCESSFULLY!  " -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""

    Write-Log "Update completed successfully." "SUCCESS"
    exit 0
}
catch {
    Write-Log "CRITICAL ERROR: $($_.Exception.Message)" "ERROR"

    if (Test-Path $tempPath) {
        Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
    }

    exit 99

}
