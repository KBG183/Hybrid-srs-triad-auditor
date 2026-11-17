<#
.SYNOPSIS
    OpenAI Codex CLI Standard Invocation Wrapper (Token-Saving File Stream Mode)
.DESCRIPTION
    Streams execution logs directly to background files and returns a slim 1-line pointer
    to stdout, preventing context token waste.
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

# 1. Discover latest codex.exe binary
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
    Write-Error "CODEX_NOT_FOUND: codex.exe binary not found."
    exit 1
}

# 2. Build full prompt
$finalPrompt = $Prompt
$contextContent = ""
if ($ContextFile -and (Test-Path $ContextFile)) {
    $contextContent = [System.IO.File]::ReadAllText($ContextFile, [System.Text.Encoding]::UTF8)
    $finalPrompt = "Reference Material:`n`n$contextContent`n`nInstructions:`n$Prompt"
}
[System.IO.File]::WriteAllText($promptFile, $finalPrompt, [System.Text.Encoding]::UTF8)

# 3. Model Auto-Routing (Luna vs Terra)
$effectiveModel = $Model
if (-not $effectiveModel) {
    $combinedText = "$Prompt $contextContent"
    $deepKeywords = @("Labor", "Statutory", "Lock", "Pessimistic", "Race", "DDL", "Security", "IDOR", "P0", "P1")
    $matched = $false
    foreach ($kw in $deepKeywords) {
        if ($combinedText -match [regex]::Escape($kw)) {
            $matched = $true
            break
        }
    }
    if ($matched) {
        $effectiveModel = "gpt-5.6-terra"
        Write-Host "[MODEL AUTO-ROUTING] Deep domain keywords detected -> routing to gpt-5.6-terra" -ForegroundColor Yellow
    } else {
        $effectiveModel = "gpt-5.6-luna"
        Write-Host "[MODEL AUTO-ROUTING] Standard verification -> routing to gpt-5.6-luna (Token-Saving)" -ForegroundColor Green
    }
}

# 4. Arguments configuration
$execArgs = @(
    "exec",
    "--skip-git-repo-check",
    "--ignore-user-config",
    "--sandbox", "read-only",
    "--cd", $workspaceDir,
    "--ephemeral",
    "--color", "never",
    "-o", $outLastMsg,
    "--model", $effectiveModel,
    "-"
)

# 5. Execute with silent file stream
Write-Host "[CODEX START] Starting Codex CLI process (File stream mode)" -ForegroundColor Cyan
$sw = [System.Diagnostics.Stopwatch]::StartNew()

Get-Content $promptFile -Raw -Encoding UTF8 | & $codexExe.FullName $execArgs 2>&1 | Out-File -FilePath $liveLog -Encoding UTF8

$exitCode = $LASTEXITCODE
$sw.Stop()

# Verify last message
$lastMsg = ""
if (Test-Path $outLastMsg) {
    $lastMsg = [System.IO.File]::ReadAllText($outLastMsg, [System.Text.Encoding]::UTF8).Trim()
}

if ($exitCode -eq 0 -and $lastMsg) {
    $elapsedSec = $sw.Elapsed.TotalSeconds.ToString('F1')
    $msgLength = $lastMsg.Length
    $summary = "[CODEX SUMMARY] Status: SUCCESS | Elapsed: ${elapsedSec}s | Length: ${msgLength} chars | File: $outLastMsg"
    Write-Output $summary
    if ($VerboseOutput) {
        Write-Output $lastMsg
    }
} else {
    Write-Warning "[CODEX FAILED] Exit code: $exitCode | Log: $liveLog"
    if ($exitCode -ne 0) {
        exit $exitCode
    }
}
