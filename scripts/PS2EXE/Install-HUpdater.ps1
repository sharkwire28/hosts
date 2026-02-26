# ============================================
# One-Click Hosts Updater EXE Installer
# Fully Production-Ready Version
# ============================================

$ErrorActionPreference = "Stop"

# ---- Paths ----
$workDir    = "C:\ProgramData\HostsUpdater"
$scriptDir  = "$workDir\script"
$scriptPath = "$scriptDir\Update-Hosts-Hourly.ps1"
$logPath    = "$workDir\hosts-updater.log"
$repoUrl    = "https://raw.githubusercontent.com/sharkwire28/hosts/main/scripts/updates.ps1"

# ---- Prepare directories ----
if (-not (Test-Path $scriptDir)) {
    New-Item -Path $scriptDir -ItemType Directory -Force | Out-Null
    (Get-Item $scriptDir).Attributes = 'Hidden'
}
if (-not (Test-Path $workDir)) { New-Item -Path $workDir -ItemType Directory -Force | Out-Null }

# ---- Logging Function ----
function Write-Log { 
    param([string]$msg)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "$ts - $msg"
    Add-Content $logPath $line
    Write-Host $line
}

try {
    Write-Log "Starting one-click installer..."

    # ---- Download latest updater script ----
    Invoke-WebRequest -Uri $repoUrl -OutFile $scriptPath -UseBasicParsing -TimeoutSec 20
    if (Test-Path $scriptPath) { Unblock-File $scriptPath -ErrorAction SilentlyContinue }
    Write-Log "Downloaded updater script"

    # ---- Create scheduled task ----
    $action = New-ScheduledTaskAction -Execute 'PowerShell.exe' -Argument "-ExecutionPolicy Bypass -File `"$scriptPath`""

    # Hourly trigger (runs for 1 year)
    $triggerHourly = New-ScheduledTaskTrigger -Once -At (Get-Date) `
        -RepetitionInterval (New-TimeSpan -Hours 1) `
        -RepetitionDuration (New-TimeSpan -Days 365)

    # Daily triggers at 10AM and 3PM
    $trigger10AM = New-ScheduledTaskTrigger -Daily -At '10:00AM'
    $trigger3PM  = New-ScheduledTaskTrigger -Daily -At '03:00PM'

    # ---- Register scheduled task as SYSTEM ----
    Register-ScheduledTask -TaskName 'HUpdaterAuto' -Action $action `
        -Trigger $triggerHourly,$trigger10AM,$trigger3PM `
        -User 'SYSTEM' -RunLevel Highest -Force

    Write-Log "Scheduled task 'HUpdaterAuto' created successfully."
    Write-Log "Installation complete. Press any key to exit..."

    # ---- Pause console so user can see logs ----
    [void][System.Console]::ReadKey($true)

} catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    Write-Log "Press any key to exit..."
    [void][System.Console]::ReadKey($true)
}