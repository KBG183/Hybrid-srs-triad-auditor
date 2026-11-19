<#
.SYNOPSIS
    High-speed invocation script for Qwen 3.8 27B / Qwen 2.5 7B (Token streaming and fallback)
.DESCRIPTION
    Priority 1: Remote accelerated host via OLLAMA_REMOTE_HOST environment variable
    Priority 2: Local fallback (http://127.0.0.1:11434, qwen2.5:7b)
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Prompt,

    [Parameter(Mandatory = $false)]
    [string]$PromptFile,

    [Parameter(Mandatory = $false)]
    [string]$System = "You are an enterprise software architect and SRS verification AI engine. Provide clear, structured Japanese output directly without internal thinking tags.",

    [Parameter(Mandatory = $false)]
    [string]$Model = "",

    [Parameter(Mandatory = $false)]
    [int]$TimeoutSeconds = 300,

    [Parameter(Mandatory = $false)]
    [double]$Temperature = 0.1,

    [Parameter(Mandatory = $false)]
    [int]$Seed = 42,

    [Parameter(Mandatory = $false)]
    [switch]$AllowFallback,

    [Parameter(Mandatory = $false)]
    [switch]$Think,

    [Parameter(Mandatory = $false)]
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
if (-not (Test-Path $projectRoot)) { $projectRoot = (Get-Location).Path }

# 1. Acquire prompt content
$finalPrompt = ""
if ($PromptFile -and (Test-Path -LiteralPath $PromptFile)) {
    $finalPrompt = [System.IO.File]::ReadAllText($PromptFile, [System.Text.Encoding]::UTF8)
} elseif ($Prompt) {
    $finalPrompt = $Prompt
} else {
    Write-Error "Prompt (-Prompt or -PromptFile) is required."
    exit 1
}

# 2. Endpoint and model resolution
$remoteHost = if ($env:OLLAMA_REMOTE_HOST) { $env:OLLAMA_REMOTE_HOST } else { $env:OLLAMA_HOST_OVERRIDE }
$primaryUrl = "http://${remoteHost}:11434"
$fallbackUrl = "http://127.0.0.1:11434"
$targetUrl = ""
$targetModel = $Model
$isFallbackActive = $false

# Priority 1: Remote accelerated host (qwen3.8:27b on RTX 5070 Ti)
$remoteOk = $false
try {
    $testResult = Test-NetConnection -ComputerName $remoteHost -Port 11434 -WarningAction SilentlyContinue
    if ($testResult.TcpTestSucceeded) {
        $healthCheck = Invoke-RestMethod -Uri "$primaryUrl/api/tags" -Method Get -TimeoutSec 3 -ErrorAction Stop
        $remoteOk = $true
        $targetUrl = $primaryUrl
        if (-not $targetModel) { 
            $hasExact = $healthCheck.models | Where-Object { $_.name -like "qwen3.8:27b*" }
            if ($hasExact) {
                $targetModel = $hasExact[0].name
            } else {
                $targetModel = "qwen27b:latest"
            }
        }
        if (-not $Quiet) { Write-Host "[ENDPOINT] Priority 1 Remote GPU connected ($targetUrl, Model: $targetModel)" -ForegroundColor Green }
    }
} catch {
    $remoteOk = $false
}

# Priority 2: Controlled Emergency Fallback
if (-not $remoteOk) {
    if (-not $AllowFallback) {
        Write-Error "[FAIL-CLOSED] Remote accelerated host ($primaryUrl) unreachable. Automatic silent downgrade to 7B is blocked. Pass -AllowFallback to permit emergency local fallback."
        exit 2
    }
    try {
        $localCheck = Invoke-RestMethod -Uri "$fallbackUrl/api/tags" -Method Get -TimeoutSec 2 -ErrorAction Stop
        $targetUrl = $fallbackUrl
        $isFallbackActive = $true
        if (-not $targetModel) { $targetModel = "qwen2.5:7b" }
        if (-not $Quiet) { Write-Warning "[ENDPOINT FALLBACK - EXPLICIT] Remote unavailable. Using local fallback ($targetUrl, Model: $targetModel)" }
    } catch {
        Write-Error "Ollama connection failed: Both remote ($primaryUrl) and local fallback ($fallbackUrl) endpoints are unreachable."
        exit 2
    }
}

# 3. Build request body
$effectiveSystem = $System
$effectivePrompt = $finalPrompt
if (-not $Think) {
    $effectiveSystem = "You are an enterprise software architect and SRS verification AI engine. Do not output <think> tags or reasoning. Provide only the final Japanese verification report directly."
    $effectivePrompt = $finalPrompt + "`n`n[Instruction: Skip internal thinking and provide final verification output directly in Japanese.]"
}

$requestObj = @{
    model = $targetModel
    system = $effectiveSystem
    prompt = $effectivePrompt
    stream = $true
    options = @{
        temperature = $Temperature
        seed = $Seed
        top_p = 0.9
        num_predict = 4096
    }
}
$requestJson = $requestObj | ConvertTo-Json -Depth 5

# Validate JSON serialization integrity (Pre-flight Schema Guard)
try {
    $null = $requestJson | ConvertFrom-Json
} catch {
    Write-Error "[FATAL] Request JSON serialization failed: $_"
    exit 1
}

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
    Write-Error "Ollama communication failure ($targetUrl): $_"
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
Seed: $Seed
Temperature: $Temperature
Elapsed: $($elapsedSec.ToString('F2'))s
Prompt Tokens: $promptTokens
Eval Tokens: $totalTokens
Speed: $tps tokens/s
=====================================================
"@

Write-Output $metricsOutput

return $fullResponse.ToString()
