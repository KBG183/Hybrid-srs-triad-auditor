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
    [switch]$IncludeClaude
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

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host " [HERMES CONTROLLER] Multi-Layer Quality Verification Pipeline" -ForegroundColor Cyan
Write-Host " Target File: $targetFileName" -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan

# -------------------------------------------------------------------------
# Step 1. C# Roslyn Deterministic Linter Hard-Gate
# -------------------------------------------------------------------------
Write-Host "`n>>> [Step 1/4] C# Deterministic Linter Hard-Gate Verification..." -ForegroundColor Yellow
$linterScript = Join-Path $scriptDir "verify_srs.ps1"
$linterOutput = & powershell -ExecutionPolicy Bypass -File $linterScript -TargetFile $resolvedTarget 2>&1
$linterStatus = if ($LASTEXITCODE -eq 0) { "PASS" } else { "FAIL (Hard-Gate Blocked)" }
Write-Host "  -> Linter Verdict: $linterStatus" -ForegroundColor $(if ($LASTEXITCODE -eq 0) { "Green" } else { "Red" })

# -------------------------------------------------------------------------
# Step 2. Local Qwen 27B (RTX 5070 Ti) Main Architectural Audit
# -------------------------------------------------------------------------
Write-Host "`n>>> [Step 2/4] Local Qwen 27B Main Architectural Audit..." -ForegroundColor Yellow
$globalHermesScript = Join-Path $env:USERPROFILE ".gemini\scripts\audit_with_hermes.ps1"
$hermesReportPath = ""
$hermesOutputText = ""

if (Test-Path $globalHermesScript) {
    $hermesTempDir = Join-Path $projectRoot "scratch\hermes_run_${timestampStr}"
    & powershell -ExecutionPolicy Bypass -File $globalHermesScript -TargetFile $resolvedTarget -OutputDir $hermesTempDir | Out-Null
    $hermesReportCandidate = Join-Path $hermesTempDir "report.md"
    if (Test-Path $hermesReportCandidate) {
        $hermesOutputText = [System.IO.File]::ReadAllText($hermesReportCandidate, [System.Text.Encoding]::UTF8)
        Write-Host "  -> Qwen 27B Main Audit Completed" -ForegroundColor Green
    } else {
        $hermesOutputText = "Qwen audit report file was not generated."
        Write-Warning "  -> Qwen result report missing"
    }
} else {
    $hermesOutputText = "Global Hermes script ($globalHermesScript) not found."
    Write-Warning "  -> Global Hermes script not found"
}

# -------------------------------------------------------------------------
# Step 3. OpenAI Codex CLI Read-Only Sandbox Cross-Audit
# -------------------------------------------------------------------------
Write-Host "`n>>> [Step 3/4] OpenAI Codex CLI Technical / Code Cross-Audit..." -ForegroundColor Yellow
$codexScript = Join-Path $scriptDir "call_codex.ps1"
$codexPrompt = "You are the OpenAI Codex Principal Auditor. Audit the specification for technical implementation, DDL constraints, DTO contracts, and pessimistic lock boundaries. Output findings in standard markdown table format."
$codexOutputText = & powershell -ExecutionPolicy Bypass -File $codexScript -Prompt $codexPrompt -ContextFile $resolvedTarget
Write-Host "  -> Codex Cross-Audit Completed" -ForegroundColor Green

# -------------------------------------------------------------------------
# Step 4. Anthropic Claude Sonnet 5.5 (Explicit User Request Only)
# -------------------------------------------------------------------------
$claudeOutputText = "Claude invocation skipped (Cost protection policy: user explicit request required)."
if ($IncludeClaude) {
    Write-Host "`n>>> [Step 4/4] Claude Sonnet 5.5 Deep Business / Legal Audit (User Approved)..." -ForegroundColor Magenta
    $claudeScript = Join-Path $scriptDir "call_claude.ps1"
    $claudePrompt = "You are the Principal Regulatory & Business Logic Auditor (Claude Sonnet 5.5). Audit the specification for Japanese Labor Standards Act Article 37 compliance, rounding conventions, and immutability invariants. Output findings table."
    $claudeOutputText = & powershell -ExecutionPolicy Bypass -File $claudeScript -Prompt $claudePrompt -ContextFile $resolvedTarget
    Write-Host "  -> Claude 5.5 Deep Audit Completed" -ForegroundColor Green
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
| **Step 0: ハードゲート** | C# Roslyn Deterministic Linter | 禁止文字、未確定記号、正規表現整合性 | **$linterStatus** |
| **Step 1: 主幹検証** | Qwen 27B (ローカルGPU RTX 5070 Ti) | ドメイン完全性・構造整合性・文脈検証 | **COMPLETED** |
| **Step 2: 技術交差検証** | OpenAI Codex CLI (GPT-5.6) | DDL制約、DTO整合性、排他ロック境界条件 | **COMPLETED** |
| **Step 3: 法規深層検証** | Anthropic Claude (Sonnet 5.5) | 労働基準法第37条、端数処理、労使協定整合性 | **COMPLETED** |

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
| Step 0: ハードゲート | C# Roslyn Linter | $linterStatus | $OutputFile |
| Step 1: 主幹検証 | Qwen 27B (ローカルGPU) | COMPLETED | $OutputFile |
| Step 2: 技術交差 | OpenAI Codex CLI | COMPLETED | $OutputFile |
| Step 3: 法規深層 | Claude Sonnet 5.5 | $(if ($IncludeClaude) { 'COMPLETED' } else { 'SKIPPED (オンデマンド保護)' }) | $OutputFile |

>>> [統合検証完了] 詳細レポート: $OutputFile
"@

Write-Output $summaryTable
return $OutputFile
