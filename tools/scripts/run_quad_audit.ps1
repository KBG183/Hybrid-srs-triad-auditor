<#
.SYNOPSIS
    KINTAI Quad-Audit Master Orchestrator (Relay & Cross-Verification Runner)
.DESCRIPTION
    Runs integrated multi-AI hybrid audit across:
    1. OpenAI Codex (gpt-6.2-astra / gpt-6.2-sol)
    2. Anthropic Claude (claude-sonnet-5-5)
    3. Local Qwen 27B (qwen3.8:27b / qwen27b:latest via RTX 5070 Ti)
    4. Deterministic C# Linters (VerifySRS_Deterministic.exe & verify_repo_total_integrity.ps1)
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$TargetFile = "config/srs_specification_ssot.md",

    [Parameter(Mandatory = $false)]
    [string]$LineRange = "",

    [Parameter(Mandatory = $false)]
    [string]$CustomPrompt = "",

    [Parameter(Mandatory = $false)]
    [ValidateSet("RELAY", "PARALLEL")]
    [string]$Mode = "RELAY",

    [Parameter(Mandatory = $false)]
    [switch]$SkipCodex,

    [Parameter(Mandatory = $false)]
    [switch]$SkipClaude,

    [Parameter(Mandatory = $false)]
    [switch]$SkipQwen
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
if (-not (Test-Path $projectRoot)) { $projectRoot = (Get-Location).Path }

$timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
$runMasterDir = Join-Path $projectRoot "audit\runs\${timestamp}_quad_master_run"
if (-not (Test-Path $runMasterDir)) { New-Item -ItemType Directory -Path $runMasterDir -Force | Out-Null }

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host " [QUAD-AUDITOR] Starting $Mode Multi-AI Cross-Verification Pipeline" -ForegroundColor Cyan
Write-Host " Target: $TargetFile $(if ($LineRange) { "(Lines $LineRange)" })" -ForegroundColor Cyan
Write-Host " Output: $runMasterDir" -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan

$auditSummary = [ordered]@{
    timestamp = $timestamp
    target = $TargetFile
    line_range = $LineRange
    mode = $Mode
    stages = @()
}

# -------------------------------------------------------------------------
# Stage 1: OpenAI Codex Cross-Audit
# -------------------------------------------------------------------------
if (-not $SkipCodex) {
    Write-Host "`n>>> [Stage 1/4] Running OpenAI Codex (gpt-6.2-astra)..." -ForegroundColor Yellow
    $callCodex = Join-Path $scriptDir "call_codex.ps1"
    $codexPrompt = if ($CustomPrompt) { $CustomPrompt } else { "Perform strict adversarial audit on target requirements focusing on concurrency, DDL integrity, and Japanese labor law." }
    $codexContext = Join-Path $projectRoot $TargetFile
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    & powershell -ExecutionPolicy Bypass -File $callCodex -Prompt $codexPrompt -ContextFile $codexContext -Model "gpt-6.2-astra"
    $sw.Stop()
    
    # Save Codex artifact
    $codexMsg = Join-Path $projectRoot "scratch\test_runs\codex_last_msg.txt"
    $destReport = Join-Path $runMasterDir "01_codex_report.txt"
    if (Test-Path $codexMsg) { Copy-Item $codexMsg $destReport -Force }
    $auditSummary.stages += [ordered]@{
        auditor = "OpenAI Codex (gpt-6.2-astra)"
        duration_s = [math]::Round($sw.Elapsed.TotalSeconds, 2)
        artifact = $destReport
    }
    Write-Host "  -> Codex stage completed in $($sw.Elapsed.TotalSeconds.ToString('F2'))s." -ForegroundColor Green
}

# -------------------------------------------------------------------------
# Stage 2: Anthropic Claude Cross-Audit
# -------------------------------------------------------------------------
if (-not $SkipClaude) {
    Write-Host "`n>>> [Stage 2/4] Running Anthropic Claude (claude-sonnet-5-5)..." -ForegroundColor Yellow
    $callClaude = Join-Path $scriptDir "call_claude.ps1"
    if (Test-Path $callClaude) {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $claudePrompt = if ($CustomPrompt) { $CustomPrompt } else { "Review domain edge cases, statutory exceptions, and algebraic consistency." }
        & powershell -ExecutionPolicy Bypass -File $callClaude -Prompt $claudePrompt
        $sw.Stop()
        Write-Host "  -> Claude stage completed in $($sw.Elapsed.TotalSeconds.ToString('F2'))s." -ForegroundColor Green
        $auditSummary.stages += [ordered]@{
            auditor = "Anthropic Claude (claude-sonnet-5-5)"
            duration_s = [math]::Round($sw.Elapsed.TotalSeconds, 2)
        }
    } else {
        Write-Host "  -> Claude script not found, skipping." -ForegroundColor DarkGray
    }
}

# -------------------------------------------------------------------------
# Stage 3: Local Qwen 27B Audit
# -------------------------------------------------------------------------
if (-not $SkipQwen) {
    Write-Host "`n>>> [Stage 3/4] Running Local Qwen 27B (RTX 5070 Ti Remote)..." -ForegroundColor Yellow
    $hermesScript = Join-Path $env:USERPROFILE ".gemini\scripts\audit_with_hermes.ps1"
    if (Test-Path $hermesScript) {
        $targetResolved = Join-Path $projectRoot $TargetFile
        $qwenOut = Join-Path $runMasterDir "03_qwen_report.md"
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $qwenArgs = @("-TargetFile", $targetResolved, "-OutputFile", $qwenOut, "-Model", "qwen27b:latest", "-AuditMode", "STANDARD")
        if ($LineRange) { $qwenArgs += @("-LineRange", $LineRange) }
        & powershell -ExecutionPolicy Bypass -File $hermesScript @qwenArgs
        $sw.Stop()
        Write-Host "  -> Qwen stage completed in $($sw.Elapsed.TotalSeconds.ToString('F2'))s." -ForegroundColor Green
        $auditSummary.stages += [ordered]@{
            auditor = "Local Qwen 27B (qwen3.8:27b)"
            duration_s = [math]::Round($sw.Elapsed.TotalSeconds, 2)
            artifact = $qwenOut
        }
    }
}

# -------------------------------------------------------------------------
# Stage 4: Deterministic Repository Total Integrity Linters
# -------------------------------------------------------------------------
Write-Host "`n>>> [Stage 4/4] Running Master Total Integrity Verifier..." -ForegroundColor Yellow
$masterLinter = Join-Path $scriptDir "verify_repo_total_integrity.ps1"
& powershell -ExecutionPolicy Bypass -File $masterLinter
$linterExit = $LASTEXITCODE

if ($linterExit -ne 0) {
    Write-Host "`n[FATAL] Stage 4 Master Linter failed with exit code $linterExit!" -ForegroundColor Red
    exit $linterExit
}

$doneMarker = Join-Path $runMasterDir ".done"
if (Test-Path $doneMarker) { Remove-Item $doneMarker -Force }

$gitSha = try { (git rev-parse HEAD).Trim() } catch { "UNKNOWN" }
$doneMeta = [ordered]@{
    timestamp = $timestamp
    target = $TargetFile
    git_sha = $gitSha
    mode = $Mode
    linter_exit = $linterExit
} | ConvertTo-Json -Compress

[System.IO.File]::WriteAllText($doneMarker, $doneMeta, [System.Text.Encoding]::UTF8)
Write-Host "`n=== [QUAD-AUDIT PIPELINE COMPLETED] ===" -ForegroundColor Green
Write-Host "All audit artifacts firmly archived in: $runMasterDir"
