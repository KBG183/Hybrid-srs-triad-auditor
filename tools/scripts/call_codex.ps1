<#
.SYNOPSIS
    OpenAI Codex CLI 전용 프로젝트 표준 호출 래퍼 (안정형 네이티브 파이프라인 & 토큰 절약 모드)
.DESCRIPTION
    긴 프롬프트 및 컨텍스트를 넘겨 백그라운드 파일에만 기록하고,
    콘솔(stdout)에는 슬림 요약(결과 파일 포인터)만 반환하여 안티그래비티 토큰을 99% 절약합니다.
#>
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Prompt,

    [Parameter(Mandatory = $false)]
    [string]$ContextFile = "",

    [Parameter(Mandatory = $false)]
    [string]$Model = "",

    [Parameter(Mandatory = $false)]
    [int]$TimeoutSeconds = 180,

    [Parameter(Mandatory = $false)]
    [switch]$VerboseOutput = $false
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
if (-not (Test-Path $projectRoot)) { $projectRoot = (Get-Location).Path }

$workspaceDir = Join-Path $projectRoot "scratch\test_runs\codex_workspace"
$outLastMsg = Join-Path $projectRoot "scratch\test_runs\codex_last_msg.txt"
$promptFile = Join-Path $projectRoot "scratch\test_runs\codex_prompt_temp.txt"
$liveLog = Join-Path $projectRoot "scratch\test_runs\codex_live.log"

if (-not (Test-Path $workspaceDir)) { New-Item -ItemType Directory -Path $workspaceDir -Force | Out-Null }
if (Test-Path $outLastMsg) { Remove-Item $outLastMsg -Force }
if (Test-Path $liveLog) { Remove-Item $liveLog -Force }

# 1. 최신 codex.exe 탐색
$binDir = Join-Path $env:LOCALAPPDATA "OpenAI\Codex\bin"
$codexExe = $null
if (Test-Path $binDir) {
    $codexExe = Get-ChildItem -Path $binDir -Filter "codex.exe" -Recurse -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

if (-not $codexExe) {
    $codexCmd = Get-Command "codex.exe" -ErrorAction SilentlyContinue
    if ($codexCmd) {
        $codexExe = [PSCustomObject]@{ FullName = $codexCmd.Source }
    }
}

if (-not $codexExe) {
    Write-Error "CODEX_NOT_FOUND: codex.exe를 찾을 수 없습니다."
    exit 1
}

# 2. 프롬프트 및 컨텍스트 결합 후 임시 파일에 UTF-8로 저장
$finalPrompt = $Prompt
if ($ContextFile -and (Test-Path $ContextFile)) {
    $contextContent = [System.IO.File]::ReadAllText($ContextFile, [System.Text.Encoding]::UTF8)
    $finalPrompt = "참고 자료:`n`n$contextContent`n`n지시 사항:`n$Prompt"
}
[System.IO.File]::WriteAllText($promptFile, $finalPrompt, [System.Text.Encoding]::UTF8)

# 3. 모델 결정 및 자동 라우팅 (Luna vs Terra)
$effectiveModel = $Model
if (-not $effectiveModel) {
    # 프롬프트 및 컨텍스트 스캔 기반 난이도 자동 감지
    $combinedText = "$Prompt $contextContent"
    $deepKeywords = @("Labor", "노동법", "37조", "Statutory", "Lock", "Pessimistic", "Race", "비관적", "동시성", "DDL", "Security", "IDOR", "법률", "단수", "회계", "P0", "P1")
    $matched = $false
    foreach ($kw in $deepKeywords) {
        if ($combinedText -match [regex]::Escape($kw)) {
            $matched = $true
            break
        }
    }
    if ($matched) {
        $effectiveModel = "gpt-5.6-terra"
        Write-Host "[MODEL AUTO-ROUTING] 고난도 법률/동시성/보안 키워드 감지 -> gpt-5.6-terra 자동 할당" -ForegroundColor Yellow
    } else {
        $effectiveModel = "gpt-5.6-luna"
        Write-Host "[MODEL AUTO-ROUTING] 일반 검수/경량 작업 감지 -> gpt-5.6-luna 자동 할당 (토큰 절약)" -ForegroundColor Green
    }
}

# 4. 인수 구성
$execArgs = @(
    "exec",
    "--skip-git-repo-check",
    "--sandbox", "read-only",
    "--cd", $workspaceDir,
    "--ephemeral",
    "--color", "never",
    "-o", $outLastMsg,
    "--model", $effectiveModel,
    "-"
)

# 4. 실행 (Out-File 기반 무출력 파일 스트리밍: 화면에 대량 덤프 없이 파일로만 기록)
Write-Host "[CODEX START] 코덱스 프로세스 시작 (토큰 절약 파일 포인터 모드)" -ForegroundColor Cyan
$sw = [System.Diagnostics.Stopwatch]::StartNew()

# Tee-Object 대신 Out-File을 사용하여 화면 출력을 100% 차단하고 파일에만 저장
Get-Content $promptFile -Raw -Encoding UTF8 | & $codexExe.FullName $execArgs 2>&1 | Out-File -FilePath $liveLog -Encoding UTF8

$exitCode = $LASTEXITCODE
$sw.Stop()

# 마지막 메시지 확인
$lastMsg = ""
if (Test-Path $outLastMsg) {
    $lastMsg = [System.IO.File]::ReadAllText($outLastMsg, [System.Text.Encoding]::UTF8).Trim()
}

if ($exitCode -eq 0 -and $lastMsg) {
    $elapsedSec = $sw.Elapsed.TotalSeconds.ToString('F1')
    $msgLength = $lastMsg.Length
    $summary = "[CODEX SUMMARY] 상태: SUCCESS | 소요: ${elapsedSec}s | 산출 크기: ${msgLength}자 | 파일: $outLastMsg"
    Write-Output $summary
    if ($VerboseOutput) {
        Write-Output $lastMsg
    }
} else {
    Write-Warning "[CODEX FAILED] 종료 코드: $exitCode | 로그 파일: $liveLog"
    if ($exitCode -ne 0) {
        exit $exitCode
    }
}
