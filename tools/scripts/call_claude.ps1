<#
.SYNOPSIS
    Anthropic Claude API Standard Invocation Wrapper Script
.DESCRIPTION
    Loads ANTHROPIC_API_KEY from environment variables (Process/User/Machine),
    invokes Claude Messages API (default: claude-sonnet-5-5), and returns live log path.
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
    [string]$System = "You are a high-performance software architect and business logic/requirements cross-audit engine. Critically evaluate logical ambiguity, missing edge cases, and legal compliance risks.",

    [Parameter(Mandatory = $false)]
    [string]$Model = "claude-sonnet-5-5",

    [Parameter(Mandatory = $false)]
    [int]$MaxTokens = 8192,

    [Parameter(Mandatory = $false)]
    [switch]$Quiet
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
if (-not (Test-Path $projectRoot)) { $projectRoot = (Get-Location).Path }

# 1. Acquire API Key
$apiKey = $env:ANTHROPIC_API_KEY
if (-not $apiKey) {
    $apiKey = [System.Environment]::GetEnvironmentVariable("ANTHROPIC_API_KEY", "User")
}
if (-not $apiKey) {
    $apiKey = [System.Environment]::GetEnvironmentVariable("ANTHROPIC_API_KEY", "Machine")
}

if (-not $apiKey) {
    Write-Error "ANTHROPIC_API_KEY not found in environment variables."
    exit 1
}

# 2. Combine Prompt and Context
$promptText = ""
if ($PromptFile -and (Test-Path -LiteralPath $PromptFile)) {
    $promptText = [System.IO.File]::ReadAllText($PromptFile, [System.Text.Encoding]::UTF8)
} elseif ($Prompt) {
    $promptText = $Prompt
} else {
    Write-Error "Prompt (-Prompt or -PromptFile) not provided."
    exit 1
}

$finalPrompt = $promptText
if ($ContextFile -and (Test-Path -LiteralPath $ContextFile)) {
    $contextContent = [System.IO.File]::ReadAllText($ContextFile, [System.Text.Encoding]::UTF8)
    $finalPrompt = "Reference Specification:`n`n$contextContent`n`nInstructions:`n$promptText"
}

# 3. Construct Request Body (Thinking: between_tools for fast text audit)
$requestBody = @{
    model = $Model
    max_tokens = $MaxTokens
    thinking = @{ type = "between_tools" }
    system = $System
    messages = @(
        @{
            role = "user"
            content = $finalPrompt
        }
    )
}
$requestJson = $requestBody | ConvertTo-Json -Depth 5

$scratchDir = Join-Path $projectRoot "scratch\test_runs"
if (-not (Test-Path $scratchDir)) { New-Item -ItemType Directory -Path $scratchDir -Force | Out-Null }
$liveLog = Join-Path $scratchDir "claude_live.log"

$headers = @{
    "x-api-key" = $apiKey
    "anthropic-version" = "2023-06-01"
    "content-type" = "application/json; charset=utf-8"
}

if (-not $Quiet) {
    Write-Host "[CLAUDE START] Invoking Anthropic Claude API (Model: $Model)" -ForegroundColor Magenta
}

$sw = [System.Diagnostics.Stopwatch]::StartNew()

try {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

    # Windows PowerShell 5.1 Invoke-RestMethod falls back to Latin-1 without explicit charset in Content-Type.
    # We read RawContentStream directly with UTF-8 StreamReader to guarantee lossless CJK decoding.
    $reqBytes = [System.Text.Encoding]::UTF8.GetBytes($requestJson)
    $webResponse = Invoke-WebRequest -Uri "https://api.anthropic.com/v1/messages" -Method Post -Headers $headers -Body $reqBytes -TimeoutSec 120 -UseBasicParsing
    
    $rawStream = $webResponse.RawContentStream
    $streamReader = New-Object System.IO.StreamReader($rawStream, [System.Text.Encoding]::UTF8)
    $rawJson = $streamReader.ReadToEnd()
    $response = $rawJson | ConvertFrom-Json

    $sw.Stop()

    $outputText = ""
    if ($response.content) {
        $textBlocks = @()
        foreach ($block in $response.content) {
            if ($block.type -eq "text" -and $block.text) {
                $textBlocks += $block.text
            } elseif ($block.type -eq "thinking" -and $block.thinking) {
                [System.IO.File]::WriteAllText((Join-Path $projectRoot "scratch\claude_thinking.log"), $block.thinking, [System.Text.Encoding]::UTF8)
            }
        }
        if ($textBlocks.Count -gt 0) {
            $outputText = $textBlocks -join "`n"
        } else {
            $thinkingBlock = $response.content | Where-Object { $_.type -eq "thinking" } | Select-Object -First 1
            if ($thinkingBlock) { $outputText = "[Thinking Summary]`n" + $thinkingBlock.thinking }
        }
    }

    [System.IO.File]::WriteAllText($liveLog, $outputText, [System.Text.Encoding]::UTF8)

    if ($response.stop_reason -eq "max_tokens") {
        Write-Warning "[CLAUDE WARNING] Output truncated due to max_tokens limit ($MaxTokens)."
    }

    $inputTokens = if ($response.usage -and $response.usage.input_tokens) { $response.usage.input_tokens } else { 0 }
    $outputTokens = if ($response.usage -and $response.usage.output_tokens) { $response.usage.output_tokens } else { 0 }
    $elapsedSec = [Math]::Max(0.01, $sw.Elapsed.TotalSeconds)

    $summary = "[CLAUDE SUMMARY] Status: SUCCESS | Elapsed: $($elapsedSec.ToString('F2'))s | Tokens: In $inputTokens / Out $outputTokens | Output: $liveLog"
    Write-Output $summary
    return $liveLog
} catch {
    $sw.Stop()
    Write-Error "Claude API communication failed: $_"
    if ($_.Exception.Response) {
        $stream = $_.Exception.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($stream)
        Write-Error "Response details: $($reader.ReadToEnd())"
    }
    exit 2
}
