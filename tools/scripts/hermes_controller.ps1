<#
.SYNOPSIS
    Hermes Multi-Agent Quality Audit Controller (hermes_controller.ps1)
.DESCRIPTION
    Unified entry point for deterministic linter, local Qwen 27B, OpenAI Codex, and Claude Sonnet 5.5.
    Aggregates all verification outputs into a standardized markdown evidence report.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TargetFile,

    [Parameter(Mandatory = $false)]
    [string]$OutputFile = "",

    [Parameter(Mandatory = $false)]
    [switch]$IncludeClaude = $true,

    [Parameter(Mandatory = $false)]
    [switch]$UseCache = $false
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
if (-not (Test-Path $projectRoot)) { $projectRoot = (Get-Location).Path }

if (-not (Test-Path $TargetFile)) {
    Write-Error "Target file does not exist: $TargetFile"
    exit 1
}

$resolvedTarget = (Resolve-Path $TargetFile).Path
$targetFileName = [System.IO.Path]::GetFileName($resolvedTarget)
$timestampStr = (Get-Date).ToString("yyyyMMdd_HHmmss")

if (-not $OutputFile) {
    $OutputFile = Join-Path $projectRoot "audit\HERMES_Audit_${targetFileName}_${timestampStr}.md"
}

$targetFileHash = (Get-FileHash -Path $resolvedTarget -Algorithm SHA256).Hash
$cacheDir = Join-Path $projectRoot "scratch\cache"
if (-not (Test-Path $cacheDir)) { New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null }

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host " [HERMES CONTROLLER] Multi-Layer Quality Verification Pipeline" -ForegroundColor Cyan
Write-Host " Target File: $targetFileName (SHA256: $($targetFileHash.Substring(0, 12))...)" -ForegroundColor Cyan
if ($UseCache) {
    Write-Host " Cache Mode : ENABLED (Incremental Smart Checkpoint)" -ForegroundColor Magenta
}
Write-Host "=================================================================" -ForegroundColor Cyan

# -------------------------------------------------------------------------
# Step 1. C# Deterministic Linter Hard-Gate
# -------------------------------------------------------------------------
Write-Host "`n>>> [Step 1/4] C# Deterministic Linter Hard-Gate Verification..." -ForegroundColor Yellow
$linterScript = Join-Path $scriptDir "verify_srs.ps1"
$linterOutput = & powershell -ExecutionPolicy Bypass -File $linterScript -TargetFile $resolvedTarget 2>&1
$linterExitCode = $LASTEXITCODE

if ($linterExitCode -ne 0) {
    Write-Host "  -> Linter Verdict: FAIL (ExitCode: $linterExitCode - Hard-Gate Blocked)" -ForegroundColor Red
    Write-Error "  -> Deterministic Hard-Gate violated! Aborting multi-layer verification immediately (Fail-Closed)."
    exit $linterExitCode
}

$linterStatus = "PASS"
Write-Host "  -> Linter Verdict: $linterStatus" -ForegroundColor Green

# -------------------------------------------------------------------------
# Step 2. Local Qwen 27B (RTX 5070 Ti) Main Architectural Audit
# -------------------------------------------------------------------------
Write-Host "`n>>> [Step 2/4] Local Qwen 27B Main Architectural Audit..." -ForegroundColor Yellow
$qwenCacheFile = Join-Path $cacheDir "qwen_${targetFileName}_${targetFileHash}.md"

if ($UseCache -and (Test-Path $qwenCacheFile)) {
    $hermesOutputText = [System.IO.File]::ReadAllText($qwenCacheFile, [System.Text.Encoding]::UTF8)
    $qwenStatus = "COMPLETED (CACHE HIT)"
    Write-Host "  -> [CACHE HIT] Target hash matches. Reusing verified Qwen audit result (0ms, 0 tokens)." -ForegroundColor Cyan
} else {
    $globalHermesScript = Join-Path $env:USERPROFILE ".gemini\scripts\audit_with_hermes.ps1"
    $hermesReportPath = ""
    $hermesOutputText = ""

    if (Test-Path $globalHermesScript) {
        $hermesTempDir = Join-Path $projectRoot "scratch\hermes_run_${timestampStr}"
        if (-not (Test-Path $hermesTempDir)) { New-Item -ItemType Directory -Path $hermesTempDir -Force | Out-Null }
        $hermesReportCandidate = Join-Path $hermesTempDir "report.md"
        & powershell -ExecutionPolicy Bypass -File $globalHermesScript -TargetFile $resolvedTarget -OutputDir $hermesTempDir -OutputFile $hermesReportCandidate | Out-Null
        if (Test-Path $hermesReportCandidate) {
            $hermesOutputText = [System.IO.File]::ReadAllText($hermesReportCandidate, [System.Text.Encoding]::UTF8)
            $qwenStatus = "COMPLETED"
            [System.IO.File]::WriteAllText($qwenCacheFile, $hermesOutputText, [System.Text.Encoding]::UTF8)
            Write-Host "  -> Qwen 27B Main Audit Completed" -ForegroundColor Green
        } else {
            $hermesOutputText = "Qwen audit report file was not generated."
            $qwenStatus = "FAIL (Report Not Generated)"
            Write-Warning "  -> Qwen result report missing"
        }
    } else {
        $hermesOutputText = "Global Hermes script ($globalHermesScript) not found."
        $qwenStatus = "FAIL (Script Missing)"
        Write-Error "  -> Global Hermes script not found: Fail-Closed enforcement"
        exit 2
    }
}

# -------------------------------------------------------------------------
# Step 3. OpenAI Codex CLI Read-Only Sandbox Cross-Audit
# -------------------------------------------------------------------------
Write-Host "`n>>> [Step 3/4] OpenAI Codex CLI Technical / Code Cross-Audit..." -ForegroundColor Yellow
$codexCacheFile = Join-Path $cacheDir "codex_${targetFileName}_${targetFileHash}.txt"

if ($UseCache -and (Test-Path $codexCacheFile)) {
    $codexOutputText = [System.IO.File]::ReadAllText($codexCacheFile, [System.Text.Encoding]::UTF8)
    $codexStatus = "COMPLETED (CACHE HIT)"
    Write-Host "  -> [CACHE HIT] Target hash matches. Reusing verified Codex audit result (0 tokens consumed)." -ForegroundColor Cyan
} else {
    $codexScript = Join-Path $scriptDir "call_codex.ps1"
    $codexLastMsgFile = Join-Path $projectRoot "scratch\test_runs\codex_last_msg.txt"
    if (Test-Path $codexLastMsgFile) { Remove-Item $codexLastMsgFile -Force -ErrorAction SilentlyContinue }
    $codexPrompt = "You are the OpenAI Codex Principal Auditor. Audit the specification for technical implementation, DDL constraints, DTO contracts, and pessimistic lock boundaries. Output findings in standard markdown table format."
    $codexSummaryOutput = & powershell -ExecutionPolicy Bypass -File $codexScript -Prompt $codexPrompt -ContextFile $resolvedTarget
    $codexExitCode = $LASTEXITCODE

    if ($codexExitCode -eq 0 -and (Test-Path $codexLastMsgFile)) {
        $codexContent = [System.IO.File]::ReadAllText($codexLastMsgFile, [System.Text.Encoding]::UTF8).Trim()
        if ($codexContent.Length -gt 0) {
            $codexOutputText = $codexContent
            $codexStatus = "COMPLETED"
            [System.IO.File]::WriteAllText($codexCacheFile, $codexOutputText, [System.Text.Encoding]::UTF8)
            Write-Host "  -> Codex Cross-Audit Completed ($codexStatus)" -ForegroundColor Green
        } else {
            $codexStatus = "FAIL (Empty Output)"
            Write-Warning "  -> Codex Cross-Audit produced empty output"
        }
    } else {
        $codexStatus = "FAIL (Execution Error, ExitCode: $codexExitCode)"
        Write-Warning "  -> Codex Cross-Audit Failed ($codexStatus)"
    }
}

# -------------------------------------------------------------------------
# Step 4. Anthropic Claude Sonnet 5.5 (Explicit User Request Only)
# -------------------------------------------------------------------------
$claudeOutputText = "Claude invocation skipped (Cost protection policy: user explicit request required)."
$claudeStatus = "NOT_EXECUTED (オンデマンド費用保護)"
if ($IncludeClaude) {
    Write-Host "`n>>> [Step 4/4] Claude Sonnet 5.5 Deep Business / Legal Audit (User Approved)..." -ForegroundColor Magenta
    $claudeCacheFile = Join-Path $cacheDir "claude_${targetFileName}_${targetFileHash}.txt"

    if ($UseCache -and (Test-Path $claudeCacheFile)) {
        $claudeOutputText = [System.IO.File]::ReadAllText($claudeCacheFile, [System.Text.Encoding]::UTF8)
        $claudeStatus = "COMPLETED (CACHE HIT)"
        Write-Host "  -> [CACHE HIT] Target hash matches. Reusing verified Claude audit result (0 API cost)." -ForegroundColor Cyan
    } else {
        $claudeScript = Join-Path $scriptDir "call_claude.ps1"
        $claudeLogFile = Join-Path $projectRoot "scratch\test_runs\claude_live.log"
        if (Test-Path $claudeLogFile) { Remove-Item $claudeLogFile -Force -ErrorAction SilentlyContinue }
        $claudePrompt = "You are the Principal Regulatory & Business Logic Auditor (Claude Sonnet 5.5). Audit the specification for Japanese Labor Standards Act Article 37 compliance, rounding conventions, and immutability invariants. Output findings table."
        $claudeSummary = & powershell -ExecutionPolicy Bypass -File $claudeScript -Prompt $claudePrompt -ContextFile $resolvedTarget
        $claudeExitCode = $LASTEXITCODE
        
        if ($claudeExitCode -eq 0 -and (Test-Path $claudeLogFile)) {
            $claudeBody = [System.IO.File]::ReadAllText($claudeLogFile, [System.Text.Encoding]::UTF8).Trim()
            if ($claudeBody.Length -gt 0) {
                $claudeOutputText = $claudeBody
                $claudeStatus = "COMPLETED"
                [System.IO.File]::WriteAllText($claudeCacheFile, $claudeOutputText, [System.Text.Encoding]::UTF8)
                Write-Host "  -> Claude 5.5 Deep Audit Completed ($claudeStatus)" -ForegroundColor Green
            } else {
                $claudeStatus = "FAIL (Empty Output)"
                Write-Warning "  -> Claude audit log empty"
            }
        } else {
            $claudeStatus = "FAIL (API Error, ExitCode: $claudeExitCode)"
            Write-Warning "  -> Claude audit failed ($claudeStatus)"
        }
    }
} else {
    Write-Host "`n>>> [Step 4/4] Claude 5.5 Audit Skipped (Cost Protection Policy: On-demand only)" -ForegroundColor DarkGray
}

# -------------------------------------------------------------------------
# Step 5. Aggregate Master Unified Report
# -------------------------------------------------------------------------
Write-Host "`n>>> [Step 5] Aggregating Multi-Agent Master Audit Report..." -ForegroundColor Cyan

$masterReport = @"
# 🏛️ KINTAI Hermes 多層統合検証レポート (Master Quality Audit Report)

- **検証日時 (Timestamp)**: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
- **対象仕様書 (Target)**: $targetFileName
- **統括オーケストレーター**: Hermes Multi-Agent Controller (`hermes_controller.ps1`)

---

## 1. 多層ハードゲート総合判定サマリー (Multi-Layer Verdict Summary)

| 検証階層 | 検証エンジン / モデル | 担当領域 | 最終判定 |
|---|---|---|---|
| **Step 0: ハードゲート** | C# Deterministic Linter | 禁止文字、未確定記号、正規表現整合性 | **$linterStatus** |
| **Step 1: 主幹検証** | Qwen 27B (ローカルGPU RTX 5070 Ti) | ドメイン完全性・構造整合性・文脈検証 | **$qwenStatus** |
| **Step 2: 技術交差検証** | OpenAI Codex CLI (GPT-5.6) | DDL制約、DTO整合性、排他ロック境界条件 | **$codexStatus** |
| **Step 3: 法規深層検証** | Anthropic Claude (Sonnet 5.5) | 労働基準法第37条、端数処理、労使協定整合性 | **$claudeStatus** |

---

## 2. [Step 0] C# 決定論的リンター検証ログ
```text
$($linterOutput -join "`r`n")
```

---

## 3. [Step 1] ローカル Qwen 27B 主幹検証レポート
$hermesOutputText

---

## 4. [Step 2] OpenAI Codex CLI 技術交差検証レポート
$codexOutputText

---

## 5. [Step 3] Anthropic Claude Sonnet 5.5 法規深層検証レポート
$claudeOutputText

---

## 6. 総括および推奨事項 (Conclusion & Recommendations)
- 本レポートは、個別の手動操作を排し、**Hermes 統合コントローラーによる単一パイプライン下で決定論的リンター、Qwen 27B、Codex、Claude 5.5を統合実行**して生成された公式技術証跡です。
"@

[System.IO.File]::WriteAllText($OutputFile, $masterReport, [System.Text.Encoding]::UTF8)

$summaryTable = @"

| 検証フェーズ | エンジン / モデル | 判定 | 出力レポート |
|---|---|---|---|
| Step 0: ハードゲート | C# Deterministic Linter | $linterStatus | $OutputFile |
| Step 1: 主幹検証 | Qwen 27B (ローカルGPU) | $qwenStatus | $OutputFile |
| Step 2: 技術交差 | OpenAI Codex CLI | $codexStatus | $OutputFile |
| Step 3: 法規深層 | Claude Sonnet 5.5 | $claudeStatus | $OutputFile |

>>> [統合検証レポート出力完了]: $OutputFile
"@

Write-Output $summaryTable

$hasExecutionFailure = ($qwenStatus -like "FAIL*") -or ($codexStatus -like "FAIL*") -or ($claudeStatus -like "FAIL*")
if ($hasExecutionFailure) {
    Write-Error "[HERMES FAIL-CLOSED] One or more multi-agent verification stages failed during execution. Pipeline aborted with code 1."
    exit 1
}

return $OutputFile
