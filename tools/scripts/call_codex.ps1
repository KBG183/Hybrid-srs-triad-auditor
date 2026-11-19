<#
.SYNOPSIS
    OpenAI Codex CLI Standard Invocation Wrapper (Token-Saving File Stream Mode)
.DESCRIPTION
    Streams execution logs directly to background files and returns a slim 1-line pointer
    to stdout, preventing context token waste.
#>
param(
    [Parameter(Mandatory = $false, Position = 0)]
    [string]$Prompt = "",

    [Parameter(Mandatory = $false)]
    [string]$PromptFile = "",

    [Parameter(Mandatory = $false)]
    [string]$ContextFile = "",

    [Parameter(Mandatory = $false)]
    [string]$Model = "",

    [Parameter(Mandatory = $false)]
    [int]$TimeoutSeconds = 180,

    [Parameter(Mandatory = $false)]
    [switch]$VerboseOutput = $false
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
if (-not (Test-Path $projectRoot)) { $projectRoot = (Get-Location).Path }

$workspaceDir = Join-Path $projectRoot "scratch\test_runs\codex_workspace"
$outLastMsg = Join-Path $projectRoot "scratch\test_runs\codex_last_msg.txt"
$tempPromptTarget = Join-Path $projectRoot "scratch\test_runs\codex_prompt_temp.txt"
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
if ($PromptFile -and (Test-Path $PromptFile)) {
    $Prompt = [System.IO.File]::ReadAllText($PromptFile, [System.Text.Encoding]::UTF8)
}
$finalPrompt = $Prompt
$contextContent = ""
if ($ContextFile -and (Test-Path $ContextFile)) {
    $contextContent = [System.IO.File]::ReadAllText($ContextFile, [System.Text.Encoding]::UTF8)
    $finalPrompt = "Reference Material:`n`n$contextContent`n`nInstructions:`n$Prompt"
}
[System.IO.File]::WriteAllText($tempPromptTarget, $finalPrompt, [System.Text.Encoding]::UTF8)

# 3. Model Auto-Routing (Fast Sol vs Deep Astra)
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
        $effectiveModel = "gpt-6.2-astra"
        Write-Host "[MODEL AUTO-ROUTING] Deep domain keywords detected -> routing to gpt-6.2-astra (Flagship Reasoning)" -ForegroundColor Yellow
    } else {
        $effectiveModel = "gpt-6.2-sol"
        Write-Host "[MODEL AUTO-ROUTING] Standard verification -> routing to gpt-6.2-sol (Fast Track)" -ForegroundColor Green
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

# 5. Execute with silent file stream and timeout enforcement
Write-Host "[CODEX START] Starting Codex CLI process (File stream mode, Timeout: ${TimeoutSeconds}s)" -ForegroundColor Cyan
$sw = [System.Diagnostics.Stopwatch]::StartNew()

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $codexExe.FullName
$escapedArgs = $execArgs | ForEach-Object {
    if ($_ -match '\s' -and -not ($_ -match '^".*"$')) { "`"$_`"" } else { $_ }
}
$psi.Arguments = ($escapedArgs -join " ")
$psi.StandardOutputEncoding = New-Object System.Text.UTF8Encoding($false)
$psi.StandardErrorEncoding = New-Object System.Text.UTF8Encoding($false)
$psi.UseShellExecute = $false
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true

$proc = [System.Diagnostics.Process]::Start($psi)
$promptBytes = [System.IO.File]::ReadAllBytes($tempPromptTarget)
$proc.StandardInput.BaseStream.Write($promptBytes, 0, $promptBytes.Length)
$proc.StandardInput.BaseStream.Flush()
$proc.StandardInput.Close()

$stdoutTask = $proc.StandardOutput.ReadToEndAsync()
$stderrTask = $proc.StandardError.ReadToEndAsync()

$timeoutMs = $TimeoutSeconds * 1000
$completed = $proc.WaitForExit($timeoutMs)

if (-not $completed) {
    try { $proc.Kill() } catch {}
    $sw.Stop()
    Write-Error "[CODEX TIMEOUT] Codex process exceeded timeout of ${TimeoutSeconds}s and was killed."
    exit 124
}

$stdout = $stdoutTask.Result
$stderr = $stderrTask.Result
$allLogs = $stdout + "`n" + $stderr
[System.IO.File]::WriteAllText($liveLog, $allLogs, [System.Text.Encoding]::UTF8)

$exitCode = $proc.ExitCode
$sw.Stop()

# Verify last message
$lastMsg = ""
if (Test-Path $outLastMsg) {
    $lastMsg = [System.IO.File]::ReadAllText($outLastMsg, [System.Text.Encoding]::UTF8).Trim()
}

if ($exitCode -eq 0 -and (-not [string]::IsNullOrWhiteSpace($lastMsg))) {
    $elapsedSec = $sw.Elapsed.TotalSeconds.ToString('F1')
    $msgLength = $lastMsg.Length
    
    # Auto-archive to permanent audit/runs/ repository (Never rely on manual save)
    $runTimestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $permanentRunDir = Join-Path $projectRoot "audit\runs\${runTimestamp}_codex_${model}"
    if (-not (Test-Path $permanentRunDir)) { New-Item -ItemType Directory -Path $permanentRunDir -Force | Out-Null }
    $permReport = Join-Path $permanentRunDir "codex_report.txt"
    $permLog = Join-Path $permanentRunDir "codex_live.log"
    [System.IO.File]::WriteAllText($permReport, $lastMsg, [System.Text.Encoding]::UTF8)
    [System.IO.File]::WriteAllText($permLog, $allLogs, [System.Text.Encoding]::UTF8)

    # 4.1 Deterministic Sidecar Generation (verdict.json)
    $detectedVerdict = "HOLD"
    if ($lastMsg -match '(?i)(?:Stage\s*\d+\s*)?Verdict[\s—:\*]+(PASS|WARN|HOLD|FAIL)') {
        $detectedVerdict = $matches[1].ToUpperInvariant()
    }

    $extractedFindings = @()
    if ($lastMsg -match '(?s)```json\s*(\{.*?"findings".*?\})\s*```') {
        try {
            $parsedJson = $matches[1] | ConvertFrom-Json
            if ($parsedJson.findings) {
                $extractedFindings = @($parsedJson.findings)
            }
        } catch {}
    }

    $helperModule = Join-Path $scriptDir "AuditVerdictHelper.psm1"
    if (Test-Path $helperModule) {
        Import-Module $helperModule -Force
        try {
            New-AuditVerdictSidecar -OutputDir $permanentRunDir `
                -Auditor "codex" `
                -RunId "${runTimestamp}_codex" `
                -RawResponsePath $permReport `
                -Verdict $detectedVerdict `
                -Findings $extractedFindings | Out-Null
        } catch {
            Write-Warning "Failed to generate verdict sidecar: $_"
        }
    }

    $summary = "[CODEX SUMMARY] Status: SUCCESS | Elapsed: ${elapsedSec}s | Length: ${msgLength} chars | PermanentArchive: $permReport"
    Write-Output $summary
    if ($VerboseOutput) {
        Write-Output $lastMsg
    }
    exit 0
} else {
    Write-Error "[CODEX FAILED] Exit code: $exitCode | LastMsgEmpty: $([string]::IsNullOrWhiteSpace($lastMsg)) | Log: $liveLog"
    if ($exitCode -ne 0) {
        exit $exitCode
    } else {
        exit 3 # Fail-Closed on empty output
    }
}
