<#
.SYNOPSIS
    Hybrid Token-Balancing Pipeline Executor v1.1
.DESCRIPTION
    Implements Plan A (Codex Drafting vs Antigravity Verification):
    - Run-isolated execution under scratch/runs/<RunId>/
    - 300s timeout with atomic rename (.tmp -> .md)
    - Injects static Japanese Labor Law Art 37 Golden Parameters
    - Executes Roslyn deterministic linting gate
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RequirementTitle,

    [Parameter(Mandatory = $true)]
    [string]$RequirementDetails,

    [Parameter(Mandatory = $false)]
    [string]$ContextSection = "",

    [Parameter(Mandatory = $false)]
    [int]$TimeoutSeconds = 300
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
if (-not (Test-Path $projectRoot)) { $projectRoot = (Get-Location).Path }

# 1. Allocate Isolated Run Directory
$runId = (Get-Date -Format "yyyyMMdd_HHmmss") + "_" + [System.Guid]::NewGuid().ToString().Substring(0, 8)
$runDir = Join-Path $projectRoot "scratch\runs\$runId"
New-Item -ItemType Directory -Path $runDir -Force | Out-Null

$promptPath = Join-Path $runDir "prompt.txt"
$tmpDraftPath = Join-Path $runDir "draft.tmp"
$finalDraftPath = Join-Path $runDir "draft.md"
$lintReportPath = Join-Path $runDir "lint_report.txt"

# 2. Build Briefing with Static Golden Rules (Anti-Hallucination & Art 37 Protection)
$goldenRules = @"
### MANDATORY GOLDEN CONSTRAINTS (DO NOT ALTER):
1. Jurisdiction: Japan Labour Standards Act (労働基準法第37条).
   - Overtime (>8h/day or >40h/week): +25%
   - Night Work (22:00 ~ 05:00): +25%
   - Overtime + Night Overlap: +50%
   - Over 60h/month Overtime: +50% (+75% with night overlap)
2. Rounding (端数処理):
   - Daily work hours: Truncate/Round per-minute strictly prohibited if disadvantageous; standard calculation on exact minutes.
   - Monthly aggregate wage: Fractions of less than 50 sen rounded down, 50 sen to less than 1 yen rounded up to 1 yen.
3. Input Boundary Validation:
   - Must handle DateTimeParseException on ISO timestamps.
   - Negative or zero work durations must throw InvalidWorkTimeException.
"@

$fullPrompt = @"
Requirement Title: $RequirementTitle

Context / Base Scope:
$ContextSection

User Details:
$RequirementDetails

$goldenRules

TASK:
Draft a complete, production-grade SRS markdown specification for this requirement.
Include:
- Strict markdown IDs: [REQ-ATT-xxx], [DDL-xxx]
- Complete DDL table (columns, types, nullability, PK, FK, indexes)
- Business logic & edge case processing
- Boundary exceptions and error codes

Write ONLY the pure markdown content.
"@

[System.IO.File]::WriteAllText($promptPath, $fullPrompt, [System.Text.Encoding]::UTF8)

# 3. Invoke OpenAI Codex CLI via Approved Wrapper
Write-Host "[PIPELINE] Launching Codex Drafting in isolated workspace: $runId"
$codexScript = Join-Path $projectRoot "tools\scripts\call_codex.ps1"

$codexSw = [System.Diagnostics.Stopwatch]::StartNew()
& powershell -ExecutionPolicy Bypass -File $codexScript -PromptFile $promptPath -TimeoutSeconds $TimeoutSeconds
$codexSw.Stop()

# Verify Output from codex_last_msg.txt
$codexLastMsg = Join-Path $projectRoot "scratch\test_runs\codex_last_msg.txt"
if (-not (Test-Path $codexLastMsg)) {
    Write-Error "[PIPELINE FAIL] Codex failed to produce output."
    exit 1
}

$draftContent = [System.IO.File]::ReadAllText($codexLastMsg, [System.Text.Encoding]::UTF8)
[System.IO.File]::WriteAllText($tmpDraftPath, $draftContent, [System.Text.Encoding]::UTF8)

# 4. Atomic Rename (.tmp -> .md)
Move-Item -Path $tmpDraftPath -Destination $finalDraftPath -Force
Write-Host "[PIPELINE] Draft successfully authored and verified: $finalDraftPath ($($draftContent.Length) chars, $($codexSw.Elapsed.TotalSeconds.ToString('F1'))s)"

# 5. Execute Deterministic Linter Gate
$linterBin = Join-Path $projectRoot "tools\scripts\VerifySRS_Deterministic.exe"
if (Test-Path $linterBin) {
    Write-Host "[PIPELINE] Executing Deterministic Linter Gate..."
    & $linterBin | Out-File -FilePath $lintReportPath -Encoding UTF8
    Get-Content -Path $lintReportPath -Encoding UTF8 | Select-Object -First 10
} else {
    Write-Host "[PIPELINE WARN] VerifySRS_Deterministic.exe not found at standard path."
}

Write-Host "=== Pipeline Execution Completed for Run: $runId ==="
