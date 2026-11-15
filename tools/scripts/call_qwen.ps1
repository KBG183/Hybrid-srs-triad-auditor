<#
.SYNOPSIS
    Qwen 3.8 27B 고속 호출 스크립트 (실시간 토큰 스트리밍 및 원격 P2P/로컬 2단 폴백)
.DESCRIPTION
    1순위: 환경변수 OLLAMA_REMOTE_HOST 기반 원격 가속 호스트 (qwen3.8:27b)
    2순위: 노트북 로컬 폴백 (http://127.0.0.1:11434, qwen2.5:7b)
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Prompt,

    [Parameter(Mandatory = $false)]
    [string]$PromptFile,

    [Parameter(Mandatory = $false)]
    [string]$System = "당신은 고성능 소프트웨어 아키텍트 및 SRS 분석 AI 엔진입니다. 내부 사고 과정(Thinking)을 생략하고 오직 명확하고 논리적인 한국어 산출물만 즉시 출력하세요.",

    [Parameter(Mandatory = $false)]
    [string]$Model = "",

    [Parameter(Mandatory = $false)]
    [int]$TimeoutSeconds = 300,

    [Parameter(Mandatory = $false)]
    [switch]$Think,

    [Parameter(Mandatory = $false)]
    [switch]$Quiet
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
if (-not (Test-Path $projectRoot)) { $projectRoot = (Get-Location).Path }

# 1. 프롬프트 내용 확보
$finalPrompt = ""
if ($PromptFile -and (Test-Path -LiteralPath $PromptFile)) {
    $finalPrompt = [System.IO.File]::ReadAllText($PromptFile, [System.Text.Encoding]::UTF8)
} elseif ($Prompt) {
    $finalPrompt = $Prompt
} else {
    Write-Error "프롬프트(-Prompt 또는 -PromptFile)가 제공되지 않았습니다."
    exit 1
}

# 2. 엔드포인트 및 모델 결정 (환경변수 OLLAMA_REMOTE_HOST 우선 적용)
$remoteHost = $env:OLLAMA_REMOTE_HOST
$primaryUrl = if ($remoteHost) { "http://${remoteHost}:11434" } else { "" }
$fallbackUrl = "http://127.0.0.1:11434"
$targetUrl = ""
$targetModel = $Model

# 1순위: 원격 가속 엔드포인트 확인 (환경변수 설정 시)
$remoteOk = $false
if ($remoteHost) {
    try {
        $testResult = Test-NetConnection -ComputerName $remoteHost -Port 11434 -WarningAction SilentlyContinue
        if ($testResult.TcpTestSucceeded) {
            $healthCheck = Invoke-RestMethod -Uri "$primaryUrl/api/tags" -Method Get -TimeoutSec 3 -ErrorAction Stop
            $remoteOk = $true
            $targetUrl = $primaryUrl
            if (-not $targetModel) { 
                # 원격 서버 태그 확인 및 매핑
                $hasExact = $healthCheck.models | Where-Object { $_.name -like "qwen3.8:27b*" }
                if ($hasExact) {
                    $targetModel = $hasExact[0].name
                } else {
                    $targetModel = "qwen27b:latest"
                }
            }
            if (-not $Quiet) { Write-Host "[ENDPOINT] 1순위 원격 GPU 가속 연결 성공 ($targetUrl, 모델: $targetModel)" -ForegroundColor Green }
        }
    } catch {
        $remoteOk = $false
    }
}

# 2순위: 로컬 폴백
if (-not $remoteOk) {
    try {
        $localCheck = Invoke-RestMethod -Uri "$fallbackUrl/api/tags" -Method Get -TimeoutSec 2 -ErrorAction Stop
        $targetUrl = $fallbackUrl
        if (-not $targetModel) { $targetModel = "qwen2.5:7b" }
        if (-not $Quiet) { Write-Warning "[ENDPOINT FALLBACK] 원격 미설정/연결실패로 로컬 엔드포인트로 폴백합니다 ($targetUrl, 모델: $targetModel)" }
    } catch {
        Write-Error "Ollama 서버 연결 실패: 원격(<TAILSCALE_OLLAMA_HOST>) 및 로컬(127.0.0.1:11434) 모두 응답이 없습니다."
        exit 2
    }
}

# 3. 요청 바디 구성 (think: false 기본 적용)
$effectiveSystem = $System
$effectivePrompt = $finalPrompt
if (-not $Think) {
    $effectiveSystem = "당신은 고성능 SRS 분석 AI 엔진입니다. <think> 태그나 내부 사고 과정, 영문 혼잣말을 일체 출력하지 마십시오. 오직 요청된 최종 한국어 산출물만 즉시 출력하십시오."
    $effectivePrompt = $finalPrompt + "`n`n[중요 지시: <think> 추론 과정을 생략하고 즉시 최종 답변만 한국어로 출력하세요.]"
}

$requestObj = @{
    model = $targetModel
    system = $effectiveSystem
    prompt = $effectivePrompt
    stream = $true
    options = @{
        temperature = 0.3
        top_p = 0.9
        num_predict = 4096
    }
}
$requestJson = $requestObj | ConvertTo-Json -Depth 5

$scratchDir = Join-Path $projectRoot "scratch"
if (-not (Test-Path $scratchDir)) { New-Item -ItemType Directory -Path $scratchDir -Force | Out-Null }
$liveLog = Join-Path $scratchDir "qwen_live.log"
$streamWriter = New-Object System.IO.StreamWriter($liveLog, $false, [System.Text.Encoding]::UTF8)

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$fullResponse = New-Object System.Text.StringBuilder
$totalTokens = 0
$promptTokens = 0

try {
    $generateUrl = "$targetUrl/api/generate"
    $webRequest = [System.Net.HttpWebRequest]::Create($generateUrl)
    $webRequest.Method = "POST"
    $webRequest.ContentType = "application/json; charset=utf-8"
    $webRequest.Timeout = $TimeoutSeconds * 1000
    $webRequest.ReadWriteTimeout = $TimeoutSeconds * 1000

    $reqBytes = [System.Text.Encoding]::UTF8.GetBytes($requestJson)
    $webRequest.ContentLength = $reqBytes.Length
    $reqStream = $webRequest.GetRequestStream()
    $reqStream.Write($reqBytes, 0, $reqBytes.Length)
    $reqStream.Close()

    $webResponse = $webRequest.GetResponse()
    $respStream = $webResponse.GetResponseStream()
    $reader = New-Object System.IO.StreamReader($respStream, [System.Text.Encoding]::UTF8)

    while (-not $reader.EndOfStream) {
        $line = $reader.ReadLine()
        if ([string]::IsNullOrWhiteSpace($line)) { continue }

        try {
            $chunk = $line | ConvertFrom-Json
            if ($chunk.response) {
                $text = $chunk.response
                [void]$fullResponse.Append($text)
                $streamWriter.Write($text)
                $streamWriter.Flush()
                if (-not $Quiet) {
                    Write-Host -NoNewline $text
                }
            }
            if ($chunk.done) {
                if ($chunk.eval_count) { $totalTokens = $chunk.eval_count }
                if ($chunk.prompt_eval_count) { $promptTokens = $chunk.prompt_eval_count }
                break
            }
        } catch {}
    }
    $reader.Close()
    $respStream.Close()
    $webResponse.Close()
} catch {
    Write-Error "Ollama 통신 실패 ($targetUrl): $_"
    exit 3
} finally {
    $streamWriter.Close()
    $sw.Stop()
}

$elapsedSec = [Math]::Max(0.01, $sw.Elapsed.TotalSeconds)
$tps = [Math]::Round($totalTokens / $elapsedSec, 1)

$metricsOutput = @"

================ [Execution Metrics] ================
Endpoint: $targetUrl
Model: $targetModel
Elapsed: $($elapsedSec.ToString('F2'))s
Prompt Tokens: $promptTokens
Eval Tokens: $totalTokens
Speed: $tps tokens/s
=====================================================
"@

Write-Output $metricsOutput

return $fullResponse.ToString()
