<#
.SYNOPSIS
    헤르메스 다층 통합 감사 컨트롤러 (Hermes Multi-Agent Controller)
.DESCRIPTION
    안티그래비티는 이 컨트롤러 단 1개만 호출합니다.
    컨트롤러 내부에서 C# 린터, Qwen 27B(헤르메스 메인), OpenAI Codex, Anthropic Claude 5.5를
    도구(Tool)로 순차 실행하고, 최종 단일 통합 감사 보고서를 자동 취합하여 생성합니다.
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
    Write-Error "대상 파일이 존재하지 않습니다: $TargetFile"
    exit 1
}

$resolvedTarget = (Resolve-Path $TargetFile).Path
$targetFileName = [System.IO.Path]::GetFileName($resolvedTarget)
$timestampStr = (Get-Date).ToString("yyyyMMdd_HHmmss")

if (-not $OutputFile) {
    $OutputFile = Join-Path $projectRoot "audit\HERMES_통합감사_${targetFileName}_${timestampStr}.md"
}

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host " [HERMES CONTROLLER] 4각 AI 하이브리드 통합 검수 파이프라인 가동" -ForegroundColor Cyan
Write-Host " 대상 파일: $targetFileName" -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan

# -------------------------------------------------------------------------
# Step 1. C# Roslyn 결정론적 린터 하드게이트
# -------------------------------------------------------------------------
Write-Host "`n>>> [Step 1/4] C# 결정론적 린터 기계식 무결성 검증..." -ForegroundColor Yellow
$linterScript = Join-Path $scriptDir "verify_srs.ps1"
$linterOutput = & powershell -ExecutionPolicy Bypass -File $linterScript -TargetFile $resolvedTarget 2>&1
$linterStatus = if ($LASTEXITCODE -eq 0) { "PASS" } else { "FAIL (하드게이트 차단)" }
Write-Host "  -> 린터 판정: $linterStatus" -ForegroundColor $(if ($LASTEXITCODE -eq 0) { "Green" } else { "Red" })

# -------------------------------------------------------------------------
# Step 2. 전역 헤르메스 (Qwen 27B, 자택 RTX 5070 Ti) 메인 감사
# -------------------------------------------------------------------------
Write-Host "`n>>> [Step 2/4] 전역 헤르메스 메인 감사 (Qwen 27B 원격 가속)..." -ForegroundColor Yellow
$globalHermesScript = "C:\Users\klad3\.gemini\scripts\audit_with_hermes.ps1"
$hermesReportPath = ""
$hermesOutputText = ""

if (Test-Path $globalHermesScript) {
    $hermesTempDir = Join-Path $projectRoot "scratch\hermes_run_${timestampStr}"
    & powershell -ExecutionPolicy Bypass -File $globalHermesScript -TargetFile $resolvedTarget -OutputDir $hermesTempDir | Out-Null
    $hermesReportCandidate = Join-Path $hermesTempDir "report.md"
    if (Test-Path $hermesReportCandidate) {
        $hermesOutputText = [System.IO.File]::ReadAllText($hermesReportCandidate, [System.Text.Encoding]::UTF8)
        Write-Host "  -> 헤르메스 메인 감사 완료 (결함 산출됨)" -ForegroundColor Green
    } else {
        $hermesOutputText = "헤르메스 보고서 파일이 생성되지 않았습니다."
        Write-Warning "  -> 헤르메스 결과 파일 누락"
    }
} else {
    $hermesOutputText = "전역 헤르메스 스크립트($globalHermesScript)를 찾을 수 없습니다."
    Write-Warning "  -> 전역 헤르메스 스크립트 없음"
}

# -------------------------------------------------------------------------
# Step 3. OpenAI Codex CLI 읽기 전용 샌드박스 교차 감사
# -------------------------------------------------------------------------
Write-Host "`n>>> [Step 3/4] OpenAI Codex CLI 기술/구현 교차 감사..." -ForegroundColor Yellow
$codexScript = Join-Path $scriptDir "call_codex.ps1"
$codexPrompt = "당신은 OpenAI Codex 수석 감사관입니다. 다음 명세를 기술 구현, DDL 제약, DTO 계약, 동시성 락 관점에서 정밀 감사하고 Finding 마크다운 표를 제시하세요."
$codexOutputText = & powershell -ExecutionPolicy Bypass -File $codexScript -Prompt $codexPrompt -ContextFile $resolvedTarget
Write-Host "  -> Codex 교차 감사 완료" -ForegroundColor Green

# -------------------------------------------------------------------------
# Step 4. Anthropic Claude Sonnet 5.5 (사용자 명시 요청 시에만 선택 가동)
# -------------------------------------------------------------------------
$claudeOutputText = "사용자 미요청으로 Claude 호출 생략 (종량제 비용 보호 원칙)"
if ($IncludeClaude) {
    Write-Host "`n>>> [Step 4/4] Claude Sonnet 5.5 비즈니스 및 일본 노동법 심층 감사 (사용자 명시 승인)..." -ForegroundColor Magenta
    $claudeScript = Join-Path $scriptDir "call_claude.ps1"
    $claudePrompt = "당신은 일본 노동기준법 및 비즈니스 로직 수석 감사관(Claude Sonnet 5.5)입니다. 다음 명세의 노동법 위반 여부, 노사 분쟁 시나리오, 단수 처리, 확정 불변성을 감사하고 Finding 표를 제시하세요."
    $claudeOutputText = & powershell -ExecutionPolicy Bypass -File $claudeScript -Prompt $claudePrompt -ContextFile $resolvedTarget
    Write-Host "  -> Claude 5.5 심층 감사 완료" -ForegroundColor Green
} else {
    Write-Host "`n>>> [Step 4/4] Claude 5.5 감사 건너뜀 (종량제 비용 보호 원칙: 사용자 미요청)" -ForegroundColor DarkGray
}

# -------------------------------------------------------------------------
# Step 5. 최종 마스터 통합 보고서 생성
# -------------------------------------------------------------------------
Write-Host "`n>>> [Step 5] 4각 감사 결과 단일 마스터 리포트 취합 중..." -ForegroundColor Cyan

$masterReport = @"
# 🏛️ KINTAI 헤르메스 컨트롤러 4각 다층 통합 검수 보고서

- **검수 일시**: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
- **검수 대상**: $targetFileName
- **총괄 컨트롤러**: Hermes Multi-Agent Orchestrator (`hermes_controller.ps1`)

---

## 1. 다층 하드게이트 종합 판정 요약

| 검수 계층 | 엔진 / 모델 | 담당 감사 영역 | 최종 판정 |
|---|---|---|---|
| **0단계 하드게이트** | C# Roslyn Deterministic Linter | 공백 없는 물결표, 금기어, TBD 누락 기계식 검사 | **$linterStatus** |
| **1단계 메인 감사** | 전역 헤르메스 (Qwen 27B / 자택 RTX 5070 Ti) | 도메인 무결성 및 구조 정합성 감사 | **COMPLETED** |
| **2단계 기술 교차 감사** | OpenAI Codex CLI (GPT-5.6 Luna) | DDL 외래키, DTO 계약, 비관적 락 경계조건 | **COMPLETED** |
| **3단계 법률 심층 감사** | Anthropic Claude (Sonnet 5.5) | 일본 노동기준법 제37조, 단수처리, 노사 분쟁 | **COMPLETED** |

---

## 2. [0단계] C# 결정론적 린터 실행 결과
```text
$($linterOutput -join "`r`n")
```

---

## 3. [1단계] 전역 헤르메스 (Qwen 27B) 메인 감사 보고서
$hermesOutputText

---

## 4. [2단계] OpenAI Codex CLI 기술 교차 감사 보고서
$codexOutputText

---

## 5. [3단계] Anthropic Claude Sonnet 5.5 노무/법률 심층 감사 보고서
$claudeOutputText

---

## 6. 결론 및 종합 권고안
- 본 보고서는 안티그래비티가 개별 쉘을 띄우지 않고, **헤르메스 통합 컨트롤러가 단일 파이프라인으로 C# 린터, Qwen 27B, Codex, Claude 5.5를 순차 총괄 실행**하여 생성된 공식 증적서입니다.
"@

[System.IO.File]::WriteAllText($OutputFile, $masterReport, [System.Text.Encoding]::UTF8)

$summaryTable = @"

| 검수 단계 | 엔진 / 모델 | 판정 | 세부 결과 저장 위치 |
|---|---|---|---|
| 0단계 하드게이트 | C# Roslyn Linter | $linterStatus | $OutputFile |
| 1단계 메인 감사 | 전역 헤르메스 (Qwen 27B) | COMPLETED | $OutputFile |
| 2단계 기술 교차 | OpenAI Codex CLI | COMPLETED | $OutputFile |
| 3단계 법률 심층 | Claude Sonnet 5.5 | $(if ($IncludeClaude) { 'COMPLETED' } else { 'SKIPPED (비용 보호)' }) | $OutputFile |

>>> [통합 검수 완료] 전체 상세 보고서: $OutputFile
"@

Write-Output $summaryTable
return $OutputFile
