<#
.SYNOPSIS
    Anthropic Claude API 표준 호출 래퍼 스크립트
.DESCRIPTION
    환경변수(User/Machine/Process)의 ANTHROPIC_API_KEY를 자동으로 로드하여
    Claude Messages API(기본: claude-3-5-sonnet-latest)를 호출하고 결과를 반환합니다.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, Position = 0)]
    [string]$Prompt,

    [Parameter(Mandatory = $false)]
    [string]$PromptFile,

    [Parameter(Mandatory = $false)]
    [string]$ContextFile,

    [Parameter(Mandatory = $false)]
    [string]$System = "당신은 고성능 소프트웨어 아키텍트 및 비즈니스 로직/요구사항 정밀 교차 감사 AI 엔진입니다. 논리적 모호성, 엣지 케이스 누락, 법적/규정 위반 리스크를 날카롭게 비판하세요.",

    [Parameter(Mandatory = $false)]
    [string]$Model = "claude-sonnet-5-5",

    [Parameter(Mandatory = $false)]
    [int]$MaxTokens = 4096,

    [Parameter(Mandatory = $false)]
    [switch]$Quiet
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
if (-not (Test-Path $projectRoot)) { $projectRoot = (Get-Location).Path }

# 1. API 키 획득
$apiKey = $env:ANTHROPIC_API_KEY
if (-not $apiKey) {
    $apiKey = [System.Environment]::GetEnvironmentVariable("ANTHROPIC_API_KEY", "User")
}
if (-not $apiKey) {
    $apiKey = [System.Environment]::GetEnvironmentVariable("ANTHROPIC_API_KEY", "Machine")
}

if (-not $apiKey) {
    Write-Error "ANTHROPIC_API_KEY를 찾을 수 없습니다. 환경변수 설정을 확인하세요."
    exit 1
}

# 2. 프롬프트 및 컨텍스트 결합
$promptText = ""
if ($PromptFile -and (Test-Path -LiteralPath $PromptFile)) {
    $promptText = [System.IO.File]::ReadAllText($PromptFile, [System.Text.Encoding]::UTF8)
} elseif ($Prompt) {
    $promptText = $Prompt
} else {
    Write-Error "프롬프트(-Prompt 또는 -PromptFile)가 제공되지 않았습니다."
    exit 1
}

$finalPrompt = $promptText
if ($ContextFile -and (Test-Path -LiteralPath $ContextFile)) {
    $contextContent = [System.IO.File]::ReadAllText($ContextFile, [System.Text.Encoding]::UTF8)
    $finalPrompt = "참고 자료 (명세서 본문):`n`n$contextContent`n`n지시 사항:`n$promptText"
}

# 3. 요청 바디 구성
$requestBody = @{
    model = $Model
    max_tokens = $MaxTokens
    system = $System
    messages = @(
        @{
            role = "user"
            content = $finalPrompt
        }
    )
}
$requestJson = $requestBody | ConvertTo-Json -Depth 5

$scratchDir = Join-Path $projectRoot "scratch"
if (-not (Test-Path $scratchDir)) { New-Item -ItemType Directory -Path $scratchDir -Force | Out-Null }
$liveLog = Join-Path $scratchDir "claude_live.log"

$headers = @{
    "x-api-key" = $apiKey
    "anthropic-version" = "2023-06-01"
    "content-type" = "application/json; charset=utf-8"
}

if (-not $Quiet) {
    Write-Host "[CLAUDE START] Anthropic API 호출 시작 (모델: $Model)" -ForegroundColor Magenta
}

$sw = [System.Diagnostics.Stopwatch]::StartNew()

try {
    # TLS 1.2 강제
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

    $response = Invoke-RestMethod -Uri "https://api.anthropic.com/v1/messages" -Method Post -Headers $headers -Body ([System.Text.Encoding]::UTF8.GetBytes($requestJson)) -TimeoutSec 120

    $sw.Stop()

    $outputText = ""
    if ($response.content) {
        $textBlocks = @()
        foreach ($block in $response.content) {
            if ($block.type -eq "text" -and $block.text) {
                $textBlocks += $block.text
            } elseif ($block.type -eq "thinking" -and $block.thinking) {
                # thinking 블록이 있을 경우 로그에 기록하되 텍스트가 없으면 thinking 본문도 활용
                [System.IO.File]::WriteAllText((Join-Path $projectRoot "scratch\claude_thinking.log"), $block.thinking, [System.Text.Encoding]::UTF8)
            }
        }
        if ($textBlocks.Count -gt 0) {
            $outputText = $textBlocks -join "`n"
        } else {
            # text 블록이 max_tokens로 인해 아직 안 나왔을 경우 thinking 내용으로 대체
            $thinkingBlock = $response.content | Where-Object { $_.type -eq "thinking" } | Select-Object -First 1
            if ($thinkingBlock) { $outputText = "[추론 요약 및 분석]`n" + $thinkingBlock.thinking }
        }
    }

    [System.IO.File]::WriteAllText($liveLog, $outputText, [System.Text.Encoding]::UTF8)

    $inputTokens = if ($response.usage -and $response.usage.input_tokens) { $response.usage.input_tokens } else { 0 }
    $outputTokens = if ($response.usage -and $response.usage.output_tokens) { $response.usage.output_tokens } else { 0 }
    $elapsedSec = [Math]::Max(0.01, $sw.Elapsed.TotalSeconds)

    $summary = "[CLAUDE SUMMARY] 상태: SUCCESS | 소요: $($elapsedSec.ToString('F2'))s | 토큰: In $inputTokens / Out $outputTokens | 산출 파일: $liveLog"
    Write-Output $summary
    return $liveLog
} catch {
    $sw.Stop()
    Write-Error "Claude API 통신 실패: $_"
    if ($_.Exception.Response) {
        $stream = $_.Exception.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($stream)
        Write-Error "상세 응답: $($reader.ReadToEnd())"
    }
    exit 2
}
