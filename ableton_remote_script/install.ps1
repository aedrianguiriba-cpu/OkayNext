# SetlistBridge Installer
# Run this script from the ableton_remote_script folder:
#   Right-click install.ps1 → Run with PowerShell

$ScriptName = "SetlistBridge"
$Source = Join-Path $PSScriptRoot $ScriptName

# ── Find all possible Ableton Remote Scripts locations ──────────────────────
$candidates = @()

# Live 11 / 12 — User Library (recommended path)
$userLib = Join-Path ([Environment]::GetFolderPath("MyDocuments")) "Ableton\User Library\Remote Scripts"
$candidates += $userLib

# Live 10 — old Preferences path
$appData = $env:APPDATA
if ($appData) {
    $ablDir = Join-Path $appData "Ableton"
    if (Test-Path $ablDir) {
        Get-ChildItem $ablDir -Directory | ForEach-Object {
            $candidates += Join-Path $_.FullName "Preferences\User Remote Scripts"
        }
    }
}

# ── Pick the first one that exists (or create the Live 11 one) ──────────────
$dest = $null
foreach ($c in $candidates) {
    if (Test-Path $c) {
        $dest = $c
        break
    }
}

if (-not $dest) {
    # Live 11 path doesn't exist yet — create it
    $dest = $userLib
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    Write-Host "Created: $dest"
}

$target = Join-Path $dest $ScriptName

Write-Host ""
Write-Host "Source : $Source"
Write-Host "Dest   : $target"
Write-Host ""

# ── Copy ────────────────────────────────────────────────────────────────────
if (Test-Path $target) {
    Remove-Item $target -Recurse -Force
    Write-Host "Removed old installation."
}

Copy-Item $Source $target -Recurse
Write-Host "Copied SetlistBridge to:"
Write-Host "  $target"
Write-Host ""
Write-Host "✓ Done! Now:"
Write-Host "  1. Restart Ableton Live completely"
Write-Host "  2. Preferences → Link/Tempo/MIDI → Control Surface → SetlistBridge"
Write-Host ""
Read-Host "Press Enter to close"
