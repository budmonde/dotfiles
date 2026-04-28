$ErrorActionPreference = "Stop"

# UWP apps to remove. These may be reinstalled by Windows Update or Intune;
# re-run this script periodically to clean them out.
$BloatApps = @(
    "Microsoft.BingSearch"
    "Microsoft.Copilot"
    "Microsoft.Edge.GameAssist"
    "Microsoft.GetHelp"
    "Microsoft.MicrosoftJournal"
    "Microsoft.MicrosoftStickyNotes"
    "Microsoft.Whiteboard"
    "Microsoft.Windows.DevHome"
    "Microsoft.WindowsCamera"
    "MicrosoftCorporationII.MicrosoftFamily"
    "MicrosoftCorporationII.QuickAssist"
    "Microsoft.CommandPalette"
    "AppUp.IntelTechnologyMDE"          # Intel Unison (phone mirroring)
    "AppUp.IntelManagementandSecurityStatus"
    "aimgr"                             # Local AI Manager for Microsoft 365
    "Microsoft.Xbox.TCUI"
    "Microsoft.XboxGamingOverlay"
    "Microsoft.XboxIdentityProvider"
    "Microsoft.XboxSpeechToTextOverlay"
)

$removed = 0
$skipped = 0

foreach ($app in $BloatApps) {
    $packages = Get-AppxPackage -Name "*$app*" -ErrorAction SilentlyContinue
    if ($packages) {
        foreach ($pkg in $packages) {
            Write-Host "Removing: $($pkg.Name)" -ForegroundColor Yellow
            try {
                $pkg | Remove-AppxPackage -ErrorAction Stop
                $removed++
            } catch {
                Write-Host "  Failed: $($_.Exception.Message)" -ForegroundColor Red
                $skipped++
            }
        }
    }
}

# Startup entries to disable
$startupRemovals = @{
    "MicrosoftEdgeAutoLaunch_*" = "Edge auto-launch"
}

foreach ($pattern in $startupRemovals.Keys) {
    $props = Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -ErrorAction SilentlyContinue
    $matching = $props.PSObject.Properties | Where-Object { $_.Name -like $pattern }
    foreach ($prop in $matching) {
        Write-Host "Removing startup: $($startupRemovals[$pattern]) ($($prop.Name))" -ForegroundColor Yellow
        Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name $prop.Name
        $removed++
    }
}

# Remove Steam from startup (registry)
$steamStartup = Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "Steam" -ErrorAction SilentlyContinue
if ($steamStartup) {
    Write-Host "Removing startup: Steam" -ForegroundColor Yellow
    Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "Steam"
    $removed++
}

# Uninstall classic Teams (winget)
$classicTeams = winget list --id Microsoft.Teams.Classic --accept-source-agreements 2>$null
if ($classicTeams -match "Microsoft.Teams.Classic") {
    Write-Host "Removing: Teams Machine-Wide Installer (classic)" -ForegroundColor Yellow
    winget uninstall --id Microsoft.Teams.Classic --silent 2>$null
    $removed++
}

# Clean up personal OneDrive folder (only if empty and account already unlinked).
# To unlink the personal account first:
#   OneDrive tray icon > Settings > Account > personal account > Unlink this PC
$personalOneDrive = Join-Path $env:USERPROFILE "OneDrive"
if (Test-Path $personalOneDrive) {
    $items = Get-ChildItem $personalOneDrive -Force -ErrorAction SilentlyContinue
    if (-not $items) {
        Write-Host "Removing empty personal OneDrive folder" -ForegroundColor Yellow
        Remove-Item $personalOneDrive -Force
        $removed++
    } else {
        Write-Host "Skipping personal OneDrive folder (not empty - unlink account first)" -ForegroundColor DarkYellow
    }
}

Write-Host ""
Write-Host "Done. Removed: $removed, Failed: $skipped" -ForegroundColor Green

if ($removed -eq 0 -and $skipped -eq 0) {
    Write-Host "System is clean - no bloatware found." -ForegroundColor Cyan
}
