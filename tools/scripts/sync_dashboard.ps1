<#
.SYNOPSIS
    KINTAI Dashboard Automated Single Source of Truth Synchronization Script
.DESCRIPTION
    Reads enterprise_audit_ledger.csv and deterministically synchronizes 
    CURRENT_STATUS.md and pipeline_metrics.md to eliminate human/AI status discrepancies.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$LedgerFile = "logs\enterprise_audit_ledger.csv",

    [Parameter(Mandatory = $false)]
    [string]$StatusFile = "logs\CURRENT_STATUS.md",

    [Parameter(Mandatory = $false)]
    [string]$MetricsFile = "logs\pipeline_metrics.md"
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
if (-not (Test-Path $projectRoot)) { $projectRoot = (Get-Location).Path }

$ledgerPath = Join-Path $projectRoot $LedgerFile
$statusPath = Join-Path $projectRoot $StatusFile
$metricsPath = Join-Path $projectRoot $MetricsFile

if (-not (Test-Path $ledgerPath)) {
    Write-Error "Ledger file not found: $ledgerPath"
    exit 1
}

# 1. Read and parse ledger
$rawLines = [System.IO.File]::ReadAllLines($ledgerPath, [System.Text.Encoding]::UTF8)
$validRows = @()
foreach ($l in $rawLines) {
    $trimmed = $l.Trim()
    if ($trimmed.Length -gt 0) { $validRows += $trimmed }
}

if ($validRows.Count -le 1) {
    Write-Error "Ledger contains no data rows."
    exit 1
}

$header = $validRows[0]
$lastRow = $validRows[$validRows.Count - 1]
$totalRecords = $validRows.Count - 1

# Calculate ledger content hash & metadata
$ledgerHash = (Get-FileHash -Path $ledgerPath -Algorithm SHA256).Hash
$lastCols = $lastRow -split ","
$lastTimestamp = $lastCols[0]
$lastBatchId = $lastCols[1]
$lastModuleName = $lastCols[2]
$lastStatus = $lastCols[3]
$lastDefectType = $lastCols[4]
$lastNotes = if ($lastCols.Count -ge 12) { $lastCols[11] } else { "" }

Write-Host ">>> [LEDGER STATE] Batch: $lastBatchId | Status: $lastStatus | Records: $totalRecords | Hash: $($ledgerHash.Substring(0, 12))..." -ForegroundColor Cyan

# 2. Update CURRENT_STATUS.md
if (Test-Path $statusPath) {
    $statusContent = [System.IO.File]::ReadAllText($statusPath, [System.Text.Encoding]::UTF8)
    
    # Deterministic pattern replace for health check verdict
    $newHealth = "- **最新ヘルスチェック判定**: ``$lastStatus``（``enterprise_audit_ledger.csv`` $lastBatchId 準拠: $lastNotes）"
    $statusUpdated = [System.Text.RegularExpressions.Regex]::Replace(
        $statusContent,
        "- \*\*最新ヘルスチェック判定\*\*:.+",
        $newHealth
    )
    
    [System.IO.File]::WriteAllText($statusPath, $statusUpdated, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "  -> Successfully synchronized: $StatusFile" -ForegroundColor Green
}

# 3. Update pipeline_metrics.md
if (Test-Path $metricsPath) {
    $metricsContent = [System.IO.File]::ReadAllText($metricsPath, [System.Text.Encoding]::UTF8)
    
    $newMetricVerdict = "* **最新統合監査判定**: ``$lastStatus``（``enterprise_audit_ledger.csv`` $lastBatchId 準拠: $lastNotes）"
    $metricsUpdated = [System.Text.RegularExpressions.Regex]::Replace(
        $metricsContent,
        "\* \*\*最新統合監査判定\*\*:.+",
        $newMetricVerdict
    )
    
    [System.IO.File]::WriteAllText($metricsPath, $metricsUpdated, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "  -> Successfully synchronized: $MetricsFile" -ForegroundColor Green
}

Write-Host ">>> [SYNC COMPLETE] Ledgers and markdown dashboards 100% aligned with Single Source of Truth." -ForegroundColor Green
exit 0
