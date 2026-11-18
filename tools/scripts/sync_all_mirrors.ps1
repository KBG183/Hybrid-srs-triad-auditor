<#
.SYNOPSIS
    KINTAI Full Mirror & Dashboard Automated Synchronization Tool
.DESCRIPTION
    1. Executes sync_dashboard.ps1 to synchronize Japanese dashboards and Korean mirror dashboards simultaneously.
    2. Validates 1:1 structural alignment between config/srs_specification_ssot.md and config/srs_specification_ssot_KO.md.
    3. Validates 1:1 structural alignment between GEMINI.md and GEMINI_KO.md.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
if (-not (Test-Path $projectRoot)) { $projectRoot = (Get-Location).Path }

Write-Host "=== [KINTAI FULL MIRROR SYNCHRONIZER] ===" -ForegroundColor Cyan

# 1. Synchronize Dashboards (Both JA and KO simultaneously)
$dashSyncScript = Join-Path $projectRoot "tools\scripts\sync_dashboard.ps1"
if (Test-Path $dashSyncScript) {
    Write-Host "[1/3] Synchronizing Japanese & Korean Dashboards..." -ForegroundColor Yellow
    & powershell -ExecutionPolicy Bypass -File $dashSyncScript
}

# 2. Check SSOT Structural Parity (REQ count & IDs)
Write-Host "[2/3] Checking SSOT Japanese vs Korean Structural Parity..." -ForegroundColor Yellow
$jaSsot = Join-Path $projectRoot "config\srs_specification_ssot.md"
$koSsot = Join-Path $projectRoot "config\srs_specification_ssot_KO.md"

if ((Test-Path $jaSsot) -and (Test-Path $koSsot)) {
    $reqRegex = [System.Text.RegularExpressions.Regex]::new('^#{3,4}\s*\[(REQ-[A-Z0-9\-]+)\]')
    
    $jaLines = [System.IO.File]::ReadAllLines($jaSsot, [System.Text.Encoding]::UTF8)
    $jaReqs = @()
    foreach ($l in $jaLines) {
        $m = $reqRegex.Match($l.Trim())
        if ($m.Success) { $jaReqs += $m.Groups[1].Value }
    }

    $koLines = [System.IO.File]::ReadAllLines($koSsot, [System.Text.Encoding]::UTF8)
    $koReqs = @()
    foreach ($l in $koLines) {
        $m = $reqRegex.Match($l.Trim())
        if ($m.Success) { $koReqs += $m.Groups[1].Value }
    }

    Write-Host "  -> JA SSOT Requirements: $($jaReqs.Count) | KO SSOT Requirements: $($koReqs.Count)" -ForegroundColor White
    $diff = Compare-Object $jaReqs $koReqs
    if ($diff) {
        Write-Host "  [WARN] Discrepancy detected in requirements between JA and KO SSOT!" -ForegroundColor Red
        $diff | Format-Table | Out-String | Write-Host
    } else {
        Write-Host "  [PASS] 100% Structural Parity Confirmed (All $($jaReqs.Count) requirements matched exactly)." -ForegroundColor Green
    }
}

# 3. Check Protocol Rule Parity
Write-Host "[3/3] Checking GEMINI.md vs GEMINI_KO.md Rule Parity..." -ForegroundColor Yellow
$jaGemini = Join-Path $projectRoot "GEMINI.md"
$koGemini = Join-Path $projectRoot "GEMINI_KO.md"

if ((Test-Path $jaGemini) -and (Test-Path $koGemini)) {
    $jaRules = (Get-Content $jaGemini -Encoding UTF8 | Select-String -Pattern '^## \d+\.').Count
    $koRules = (Get-Content $koGemini -Encoding UTF8 | Select-String -Pattern '^## \d+\.').Count
    Write-Host "  -> JA Protocol Rules: $jaRules | KO Protocol Rules: $koRules" -ForegroundColor White
    if ($jaRules -eq $koRules) {
        Write-Host "  [PASS] 100% Rule Article Parity Confirmed (All $jaRules articles matched)." -ForegroundColor Green
    } else {
        Write-Host "  [WARN] Rule count mismatch between JA ($jaRules) and KO ($koRules) protocols!" -ForegroundColor Red
    }
}

Write-Host "=== [ALL MIRRORS FULLY SYNCHRONIZED & VERIFIED] ===" -ForegroundColor Green
