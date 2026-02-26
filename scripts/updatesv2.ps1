# ================================
# Self-Elevating Hosts Updater
# Author: Gary Magallanes
# Date: Feb 26, 2026
# Version: 2.0 - GitHub Remote Execution
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

# ---- Script Configuration ----
$scriptUrl = "https://raw.githubusercontent.com/sharkwire28/hosts/main/scripts/updatesv2.ps1"
$repoRawUrl = "https://raw.githubusercontent.com/sharkwire28/hosts/main/system/hosts"

# ---- Self-Elevation for Remote Execution ----
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Requesting administrator privileges..." -ForegroundColor Yellow
    
    # Create a temporary script file for elevation
    $tempScript = [System.IO.Path]::Combine($env:TEMP, "hosts-updater-$(Get-Random).ps1")
    
    try {
        # Download the script to temp location
        $scriptContent = Invoke-RestMethod -Uri $scriptUrl -UseBasicParsing
        $scriptContent | Out-File -FilePath $tempScript -Encoding UTF8 -Force
        
        # Launch elevated PowerShell with the temporary script
        $processInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processInfo.FileName = "powershell.exe"
        $processInfo.Arguments = "-ExecutionPolicy Bypass -NoProfile -File `"$tempScript`""
        $processInfo.Verb = "RunAs"
        $processInfo.UseShellExecute = $true
        $processInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Normal
        
        $process = [System.Diagnostics.Process]::Start($processInfo)
        
        # Wait a moment before cleaning up to ensure the elevated process has read the file
        Start-Sleep -Seconds 2
        
        # Schedule cleanup of temp file after a delay
        $cleanupScript = @"
Start-Sleep -Seconds 5
if (Test-Path '$tempScript') { Remove-Item '$tempScript' -Force -ErrorAction SilentlyContinue }
"@
        Start-Process powershell -ArgumentList "-WindowStyle Hidden -Command `"$cleanupScript`"" -NoNewWindow
        
    } catch {
        Write-Host "Failed to elevate: $_" -ForegroundColor Red
        if (Test-Path $tempScript) { Remove-Item $tempScript -Force -ErrorAction SilentlyContinue }
    }
    
    exit
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

# ---- Prepare Directories ----
if (!(Test-Path $workDir)) { 
    New-Item -Path $workDir -ItemType Directory -Force | Out-Null 
    Write-Host "Created working directory: $workDir" -ForegroundColor Gray
}
if (!(Test-Path $tempDir)) { 
    New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
    (Get-Item $tempDir).Attributes = 'Hidden'
}

# ---- Logging Function ----
function Write-Log { 
    param(
        [string]$msg,
        [string]$Level = "INFO"
    )
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "$ts [$Level] - $msg"
    Add-Content $logPath $line
    
    switch ($Level) {
        "ERROR" { Write-Host $line -ForegroundColor Red }
        "WARNING" { Write-Host $line -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $line -ForegroundColor Green }
        default { Write-Host $line -ForegroundColor White }
    }
}

# ---- Backup Management Function ----
function Manage-Backups {
    $backups = Get-ChildItem -Path $workDir -Filter "hosts-*.bak" | 
               Sort-Object CreationTime -Descending
    
    if ($backups.Count -gt $maxBackups) {
        $toDelete = $backups | Select-Object -Skip $maxBackups
        foreach ($backup in $toDelete) {
            Remove-Item $backup.FullName -Force
            Write-Log "Removed old backup: $($backup.Name)" "INFO"
        }
    }
}

# ---- Main Update Logic ----
try {
    Write-Log "Starting file update check" "INFO"
    
    # Force TLS 1.2 for GitHub
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    
    # ---- Check Remote File with ETag ----
    Write-Host "Checking for updates..." -ForegroundColor Yellow
    
    $headers = @{}
    $response = try {
        Invoke-WebRequest -Uri $repoRawUrl -UseBasicParsing -Method Head -TimeoutSec 3 -ErrorAction Stop
    } catch {
        Write-Log "Failed to check remote file: $_" "ERROR"
        throw
    }
    
    $remoteETag = $response.Headers.ETag
    $lastETag = if (Test-Path $etagPath) { 
        Get-Content $etagPath -Raw -ErrorAction SilentlyContinue 
    } else { 
        "" 
    }
    
    if ($remoteETag -and ($remoteETag -eq $lastETag)) {
        Write-Log "No changes detected on remote repository" "INFO"
        Write-Host "`nNo updates available. System is up to date." -ForegroundColor Green
        Start-Sleep -Seconds 2
        exit
    }
    
    # ---- Download New File ----
    Write-Log "New version detected. Downloading..." "INFO"
    Write-Host "Downloading latest file..." -ForegroundColor Yellow
    
    try {
        # Use Invoke-RestMethod for better compatibility
        $content = Invoke-RestMethod -Uri $repoRawUrl -UseBasicParsing -TimeoutSec 30
        $content | Out-File -FilePath $tempPath -Encoding UTF8 -Force
        
        # Verify download
        if (!(Test-Path $tempPath) -or (Get-Item $tempPath).Length -eq 0) {
            throw "Downloaded file is empty or missing"
        }
        
    } catch {
        Write-Log "Download failed: $_" "ERROR"
        throw
    }
    
    # Remove "downloaded from internet" security warning
    if (Test-Path $tempPath) { 
        Unblock-File $tempPath -ErrorAction SilentlyContinue 
    }
    
    # Save ETag for future comparisons
    if ($remoteETag) {
        $remoteETag | Set-Content $etagPath -Force
    }
    
    # ---- Compare File Contents ----
    $currentHash = if (Test-Path $hostsPath) { 
        (Get-FileHash $hostsPath -Algorithm SHA256).Hash 
    } else { 
        "" 
    }
    $newHash = (Get-FileHash $tempPath -Algorithm SHA256).Hash
    
    if ($currentHash -eq $newHash) {
        Write-Log "System hosts file already matches remote version" "INFO"
        Write-Host "`nFile is already up to date." -ForegroundColor Green
        Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        exit
    }
    
    Write-Log "Changes detected. Proceeding with update..." "WARNING"
    
    # ---- Backup Current Hosts File ----
    if (Test-Path $hostsPath) {
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $backupPath = "$workDir\hosts-$timestamp.bak"
        
        try {
            Copy-Item $hostsPath $backupPath -Force
            Write-Log "Backup created" "SUCCESS"
            
            # Clean up old backups
            Manage-Backups
            
        } catch {
            Write-Log "Failed to create backup: $_" "ERROR"
            throw
        }
    }
    
    # ---- Replace Hosts File ----
    try {
        # Attempt to copy with retry logic
        $retries = 3
        $copied = $false
        
        for ($i = 1; $i -le $retries; $i++) {
            try {
                Copy-Item $tempPath $hostsPath -Force -ErrorAction Stop
                $copied = $true
                break
            } catch {
                if ($i -eq $retries) { throw }
                Write-Log "Copy attempt $i failed, retrying..." "WARNING"
                Start-Sleep -Seconds 2
            }
        }
        
        if ($copied) {
            Write-Log "File updated successfully" "SUCCESS"
            Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
        }
        
    } catch {
        Write-Log "Failed to update hosts file: $_" "ERROR"
        throw
    }
    
    # ---- Flush DNS Cache ----
    Write-Host "Flushing DNS cache..." -ForegroundColor Yellow
    $dnsResult = ipconfig /flushdns 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Log "DNS cache flushed successfully" "SUCCESS"
    } else {
        Write-Log "DNS flush completed with warnings" "WARNING"
    }
    
    # ---- Final Success Message ----
    Write-Host "`n" -NoNewline
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  SYSTEM UPDATED SUCCESSFULLY!  " -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Log "Update process completed successfully" "SUCCESS"
    
    # Show summary
    Write-Host "Summary:" -ForegroundColor Cyan
    Write-Host "  > Backup Saved" -ForegroundColor Gray
    Write-Host "  > DNS Cache Flushed" -ForegroundColor Gray
    Write-Host "  > Log File Saved" -ForegroundColor Gray
    Write-Host ""
    
    Start-Sleep -Seconds 3
    
} catch {
    Write-Log "CRITICAL ERROR: $($_.Exception.Message)" "ERROR"
    Write-Host "`nUpdate failed. Check log file for details: $logPath" -ForegroundColor Red
    Start-Sleep -Seconds 5
    exit 1
}

# Clean up any remaining temp files
if (Test-Path $tempPath) {
    Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
}
