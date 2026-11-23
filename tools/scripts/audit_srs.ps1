<#
.SYNOPSIS
    KINTAI SRS Automated AI Audit Adapter for gate_master_srs.ps1 (audit_srs.ps1)
.DESCRIPTION
    Receives -RepoRoot, -BundlePath, and -RunId from gate_master_srs.ps1 (Stage 3).
    1. Independently verifies bundle SHA-256, Article 0 constitution checksum, and finding queue status.
    2. Inspects every target Markdown file in the bundle against its recorded SHA-256 hash,
       Article 0 requirement structure rules, and the 5 mandatory KINTAI domain alignment axes.
    3. Invokes call_ai.ps1 to execute live AI audit against Article 0 and validates the completed
       model response and sidecar receipt (verdict.json).
    4. Writes all diagnostics exclusively to stderr and outputs exactly one JSON object to stdout:
       { "RunId": "...", "BundleSha256": "...", "Verdict": "PASS" }
    Exit codes: 0 = PASS, 3 = REJECT (specification or AI audit rejection), 4 = incomplete/invalid audit.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot,

    [Parameter(Mandatory = $true)]
    [string]$BundlePath,

    [Parameter(Mandatory = $true)]
    [string]$RunId,

    [Parameter(Mandatory = $false)]
    [ValidateSet("Qwen", "Codex", "Claude")]
    [string]$Provider = $(if ($env:SRS_AI_PROVIDER) { $env:SRS_AI_PROVIDER } else { "Qwen" }),

    [Parameter(Mandatory = $false)]
    [int]$TimeoutSeconds = 300
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$utf8NoBom = New-Object System.Text.UTF8Encoding($false, $true)

function Get-BytesSha256([byte[]]$Bytes) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString($sha.ComputeHash($Bytes)) -replace '-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

try {
    if (-not (Test-Path -LiteralPath $RepoRoot)) {
        [Console]::Error.WriteLine("[AI-ADAPTER ERROR] RepoRoot does not exist: $RepoRoot")
        exit 4
    }
    $rootFull = (Get-Item -LiteralPath $RepoRoot).FullName

    if (-not (Test-Path -LiteralPath $BundlePath)) {
        [Console]::Error.WriteLine("[AI-ADAPTER ERROR] BundlePath does not exist: $BundlePath")
        exit 4
    }

    # 1. Read and hash bundle
    $bundleBytes = [System.IO.File]::ReadAllBytes($BundlePath)
    $bundleHash = Get-BytesSha256 $bundleBytes
    $bundleText = $utf8NoBom.GetString($bundleBytes)
    if ($bundleText.StartsWith([string][char]0xFEFF, [System.StringComparison]::Ordinal)) {
        $bundleText = $bundleText.Substring(1)
    }
    $bundleJson = $bundleText | ConvertFrom-Json

    if (-not $bundleJson -or [string]$bundleJson.RunId -cne $RunId) {
        [Console]::Error.WriteLine("[AI-ADAPTER ERROR] Bundle RunId mismatch. Expected '$RunId', got '$($bundleJson.RunId)'.")
        exit 4
    }

    $files = @($bundleJson.Files)
    if (-not $files -or $files.Count -eq 0) {
        [Console]::Error.WriteLine("[AI-ADAPTER ERROR] Zero target files in bundle.")
        exit 4
    }

    [Console]::Error.WriteLine("[AI-ADAPTER] Auditing bundle $BundlePath (SHA256: $bundleHash, Targets: $($files.Count))")

    # 2. Independently verify Article 0 Constitution & Checksum
    $articlePath = Join-Path $rootFull "governance\ARTICLE_0_SRS.md"
    $checksumPath = Join-Path $rootFull "governance\ARTICLE_0_SRS.sha256"
    if (-not (Test-Path -LiteralPath $articlePath) -or -not (Test-Path -LiteralPath $checksumPath)) {
        [Console]::Error.WriteLine("[AI-ADAPTER ERROR] Article 0 constitution or checksum file missing.")
        exit 4
    }

    $articleBytes = [System.IO.File]::ReadAllBytes($articlePath)
    $articleHash = Get-BytesSha256 $articleBytes
    $checksumLine = ($utf8NoBom.GetString([System.IO.File]::ReadAllBytes($checksumPath))).Trim()

    if ($checksumLine -notmatch '\A([0-9a-fA-F]{64})(?:[ \t]+\*?(?:\./)?ARTICLE_0_SRS\.md)?\z' -or
        $Matches[1].ToLowerInvariant() -ne $articleHash -or
        ([string]$bundleJson.ConstitutionSha256).ToLowerInvariant() -ne $articleHash) {
        [Console]::Error.WriteLine("[AI-ADAPTER ERROR] Article 0 constitution SHA-256 verification failed.")
        exit 4
    }
    $articleText = $utf8NoBom.GetString($articleBytes)

    # 3. Independently verify Finding Queue (Article 0 Section 4)
    $queuePath = Join-Path $rootFull "queue\srs_pending_findings.json"
    if (-not (Test-Path -LiteralPath $queuePath)) {
        [Console]::Error.WriteLine("[AI-ADAPTER ERROR] Finding queue missing: $queuePath")
        exit 4
    }
    $queueDoc = ($utf8NoBom.GetString([System.IO.File]::ReadAllBytes($queuePath))) | ConvertFrom-Json
    $qItems = if ($null -ne $queueDoc.findings) { @($queueDoc.findings) } else { @() }
    foreach ($qi in $qItems) {
        $st = ([string]$qi.status).Trim().ToUpperInvariant()
        if ($st -eq 'PENDING' -or $st -eq 'RESOLVED') {
            [Console]::Error.WriteLine("[AI-ADAPTER REJECT] Unverified finding in queue (status=$st). Article 0 Section 4 violation.")
            exit 3
        }
    }

    # 4. Content & Constitution Cross-Verification across all Bundle Files
    $seenReqIds = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    $combinedSpecBuilder = New-Object System.Text.StringBuilder
    $rejectionReasons = New-Object 'System.Collections.Generic.List[string]'

    foreach ($fileEntry in $files) {
        $relPath = [string]$fileEntry.Path
        $expectedSha = ([string]$fileEntry.Sha256).ToLowerInvariant()
        $fullTarget = [System.IO.Path]::GetFullPath((Join-Path $rootFull $relPath))

        if (-not (Test-Path -LiteralPath $fullTarget)) {
            [Console]::Error.WriteLine("[AI-ADAPTER ERROR] Target file listed in bundle does not exist: $relPath")
            exit 4
        }

        $targetBytes = [System.IO.File]::ReadAllBytes($fullTarget)
        $actualSha = Get-BytesSha256 $targetBytes
        if ($actualSha -ne $expectedSha) {
            [Console]::Error.WriteLine("[AI-ADAPTER ERROR] SHA-256 mismatch for '$relPath'. Expected $expectedSha, got $actualSha.")
            exit 4
        }

        $content = $utf8NoBom.GetString($targetBytes)
        if ($content.Contains([char]0)) {
            [Console]::Error.WriteLine("[AI-ADAPTER ERROR] NUL byte detected in '$relPath'.")
            exit 4
        }

        # Check for unfinalized placeholders (Article 0 Section 5)
        $placeholderMatch = [regex]::Match($content, '(?i)\b(TODO|TBD|FIXME)\b|(未定|未確定|追って決定)')
        if ($placeholderMatch.Success) {
            $rejectionReasons.Add("[$relPath] Unfinalized placeholder detected: '$($placeholderMatch.Value)'")
        }

        # Extract and validate requirements (Article 0 Section 2)
        $reqMatches = [regex]::Matches($content, '(?m)^#{2,4}\s*\[?(REQ-[A-Z0-9_-]+)\]?[^\r\n]*')
        for ($i = 0; $i -lt $reqMatches.Count; $i++) {
            $reqId = $reqMatches[$i].Groups[1].Value
            if (-not $seenReqIds.Add($reqId)) {
                $rejectionReasons.Add("[$relPath] Duplicate requirement ID detected: $reqId")
            }

            $startIdx = $reqMatches[$i].Index
            $endIdx = if ($i + 1 -lt $reqMatches.Count) { $reqMatches[$i + 1].Index } else { $content.Length }
            $reqBlock = $content.Substring($startIdx, $endIdx - $startIdx)

            $hasInputOrDepends = $reqBlock -match '(-\s*\*\*入力.*?\*\*:|DependsOn|先行依存関係)'
            $hasProcessOrBody = $reqBlock -match '(-\s*\*\*処理\*\*:|-\s*\*\*概要\*\*:)'
            $hasAcceptanceOrDod = $reqBlock -match '(-\s*\*\*完了基準\s*\(DoD\)\*\*:|Acceptance Criteria|検証基準)'

            if (-not ($hasInputOrDepends -and $hasProcessOrBody -and $hasAcceptanceOrDod)) {
                $rejectionReasons.Add("[$relPath] Requirement '$reqId' is missing mandatory structure (Input/DependsOn, Process/Body, or DoD/Acceptance Criteria).")
            }

            $digestBlock = if ($reqBlock.Length -gt 900) {
                $reqBlock.Substring(0, 900) + "`n... [Verified full block length: $($reqBlock.Length) chars]"
            } else {
                $reqBlock
            }
            [void]$combinedSpecBuilder.AppendLine($digestBlock.Trim())
            [void]$combinedSpecBuilder.AppendLine("---")
        }
    }

    if ($seenReqIds.Count -eq 0) {
        [Console]::Error.WriteLine("[AI-ADAPTER REJECT] Zero requirement IDs (REQ-*) found across bundle files.")
        exit 3
    }

    $allSpecText = [System.IO.File]::ReadAllText((Join-Path $rootFull $files[0].Path), $utf8NoBom)
    foreach ($fe in ($files | Select-Object -Skip 1)) {
        $allSpecText += "`n" + [System.IO.File]::ReadAllText((Join-Path $rootFull $fe.Path), $utf8NoBom)
    }
    $digestSpecText = $combinedSpecBuilder.ToString()

    # Check Article 0 Section 3: 5 Mandatory KINTAI Domain Alignment Axes
    $domainAxes = @(
        @{ Name = "Axis 1 (Working Hours & Breaks)"; Pattern = '(休憩|30分|60分|労働時間)' },
        @{ Name = "Axis 2 (Labor Standards Act Art. 37 & Rounding)"; Pattern = '(労働基準法第37条|割増|25%|端数)' },
        @{ Name = "Axis 3 (Concurrency & Pessimistic Lock)"; Pattern = '(FOR UPDATE|悲観的ロック)' },
        @{ Name = "Axis 4 (Audit Trail & Immutable History)"; Pattern = '(監査証跡|audit_log|修正理由|変更履歴|原本)' },
        @{ Name = "Axis 5 (IDOR & Multi-Tenant Isolation)"; Pattern = '(SecurityContext|IDOR|ROLE_OWNER|多店舗|テナント)' }
    )
    foreach ($axis in $domainAxes) {
        if ($allSpecText -notmatch $axis.Pattern) {
            $rejectionReasons.Add("Article 0 Section 3 violation: Missing mandatory domain coverage for $($axis.Name).")
        }
    }

    if ($rejectionReasons.Count -gt 0) {
        foreach ($reason in $rejectionReasons) {
            [Console]::Error.WriteLine("[AI-ADAPTER REJECT] $reason")
        }
        exit 3
    }

    # 5. Live AI Audit Execution via call_ai.ps1
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $callAiPath = Join-Path $scriptDir "call_ai.ps1"
    if (-not (Test-Path -LiteralPath $callAiPath)) {
        [Console]::Error.WriteLine("[AI-ADAPTER ERROR] call_ai.ps1 not found at: $callAiPath")
        exit 4
    }

    $scratchDir = Join-Path $rootFull "scratch\runs"
    if (-not (Test-Path -LiteralPath $scratchDir)) {
        New-Item -ItemType Directory -Path $scratchDir -Force | Out-Null
    }
    $promptFile = Join-Path $scratchDir "stage3_audit_prompt_${RunId}.txt"

    $auditPrompt = @"
You are the Stage 3 Constitutional AI Auditor for the KINTAI SRS Approval Gate.
Audit the target SRS specification bundle against the Article 0 Constitution below.

=== ARTICLE 0 CONSTITUTION (SHA256: $articleHash) ===
$articleText

=== AUDIT BUNDLE METADATA ===
RunId: $RunId
BundleSha256: $bundleHash
Total Requirements Extracted: $($seenReqIds.Count)
Requirement IDs: $(($seenReqIds | Sort-Object) -join ', ')

=== TARGET SPECIFICATION CONTENT (ALL $($seenReqIds.Count) REQUIREMENTS) ===
$digestSpecText

=== AUDIT INSTRUCTIONS ===
1. Verify compliance with Article 0 Sections 1 through 5 (Fail-Closed, unique REQ-* IDs, 5 mandatory KINTAI domain axes: working hours/breaks, Labor Standards Act Article 37 overtime/night rates & rounding, SELECT FOR UPDATE pessimistic locking, audit trail preservation, and IDOR/multi-tenant isolation).
2. Keep your analysis concise and deterministic. Output your final structured verdict in a fenced JSON block with keys "verdict" ("PASS" or "FAIL") and "findings" (array of objects with "id", "severity" ["P0","P1","P2","INFO"], and "description"), followed by a final line "Verdict: PASS" or "Verdict: FAIL".
"@

    [System.IO.File]::WriteAllText($promptFile, $auditPrompt, $utf8NoBom)

    try {
        $pwshExe = (Get-Command pwsh, powershell -ErrorAction SilentlyContinue | Select-Object -First 1).Source
        if (-not $pwshExe) {
            [Console]::Error.WriteLine("[AI-ADAPTER ERROR] PowerShell executable not found.")
            exit 4
        }

        [Console]::Error.WriteLine("[AI-ADAPTER] Invoking call_ai.ps1 (Provider: $Provider, RunId: $RunId)...")

        $stage3SystemPrompt = 'You are the Stage 3 Constitutional AI Auditor for the KINTAI SRS Approval Gate. Respond strictly in English. Verify whether the specification satisfies the Article 0 Constitution (Sections 1-5: Fail-Closed rules, unique REQ-* identifiers with Input/Process/Output/Exception/DoD, and the 5 mandatory KINTAI domain axes). Only report a P0 or P1 finding if an explicit requirement violates Article 0 or contains a concrete statutory contradiction. Output a concise verification summary followed by a fenced json code block containing keys verdict (PASS or FAIL) and findings (empty array if clean), and end with the line Verdict: PASS (or Verdict: FAIL).'

        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = $pwshExe
        $pinfo.WorkingDirectory = $rootFull
        $pinfo.UseShellExecute = $false
        $pinfo.RedirectStandardOutput = $true
        $pinfo.RedirectStandardError = $true
        $pinfo.StandardOutputEncoding = $utf8NoBom
        $pinfo.StandardErrorEncoding = $utf8NoBom
        $pinfo.CreateNoWindow = $true
        $pinfo.Arguments = "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$callAiPath`" -Provider $Provider -PromptFile `"$promptFile`" -SystemPrompt `"$stage3SystemPrompt`" -TimeoutSeconds $TimeoutSeconds"

        $auditStartUtc = [System.DateTime]::UtcNow.AddSeconds(-2)
        $proc = [System.Diagnostics.Process]::Start($pinfo)
        $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
        $stderrTask = $proc.StandardError.ReadToEndAsync()

        if (-not $proc.WaitForExit(($TimeoutSeconds + 30) * 1000)) {
            try { $proc.Kill() } catch {}
            [Console]::Error.WriteLine("[AI-ADAPTER ERROR] call_ai.ps1 timed out.")
            exit 4
        }
        [void][System.Threading.Tasks.Task]::WaitAll(@($stdoutTask, $stderrTask), 5000)

        $childOut = $stdoutTask.Result
        $childErr = $stderrTask.Result
        if (-not [string]::IsNullOrWhiteSpace($childOut)) {
            [Console]::Error.WriteLine($childOut.Trim())
        }
        if (-not [string]::IsNullOrWhiteSpace($childErr)) {
            [Console]::Error.WriteLine($childErr.Trim())
        }

        $aiExitCode = $proc.ExitCode
        $proc.Dispose()

        # Locate the newly generated sidecar verdict.json from this audit invocation
        $auditRunsDir = Join-Path $rootFull "audit\runs"
        $latestSidecar = $null
        if (Test-Path -LiteralPath $auditRunsDir) {
            $latestSidecar = Get-ChildItem -Path $auditRunsDir -Filter "verdict.json" -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTimeUtc -ge $auditStartUtc } |
                Sort-Object LastWriteTimeUtc -Descending |
                Select-Object -First 1
        }

        if (-not $latestSidecar) {
            [Console]::Error.WriteLine("[AI-ADAPTER ERROR] AI runner did not produce a fresh verdict.json sidecar (ExitCode: $aiExitCode).")
            exit 4
        }

        $sidecarObj = ($utf8NoBom.GetString([System.IO.File]::ReadAllBytes($latestSidecar.FullName))) | ConvertFrom-Json
        if (-not $sidecarObj -or $sidecarObj.schema -ne "audit-verdict/v1" -or [string]::IsNullOrWhiteSpace($sidecarObj.response_sha256)) {
            [Console]::Error.WriteLine("[AI-ADAPTER ERROR] Invalid or incomplete sidecar schema at: $($latestSidecar.FullName)")
            exit 4
        }

        $aiVerdict = ([string]$sidecarObj.verdict).Trim().ToUpperInvariant()
        $p0p1Count = [int]$sidecarObj.p0_p1_count

        [Console]::Error.WriteLine("[AI-ADAPTER] AI Sidecar verified: $($latestSidecar.FullName) (Verdict: $aiVerdict, P0/P1: $p0p1Count, ResponseSHA256: $($sidecarObj.response_sha256))")

        if ($aiVerdict -eq "FAIL" -or $p0p1Count -gt 0) {
            $rejectOut = ([ordered]@{
                RunId        = $RunId
                BundleSha256 = $bundleHash
                Verdict      = "REJECT"
            }) | ConvertTo-Json -Compress
            [Console]::WriteLine($rejectOut)
            exit 3
        }

        if ($aiExitCode -ne 0 -or ($aiVerdict -ne "PASS" -and $aiVerdict -ne "WARN")) {
            [Console]::Error.WriteLine("[AI-ADAPTER ERROR] AI audit did not reach a determinable PASS verdict (Verdict: $aiVerdict, ExitCode: $aiExitCode).")
            exit 4
        }

        $passOut = ([ordered]@{
            RunId        = $RunId
            BundleSha256 = $bundleHash
            Verdict      = "PASS"
        }) | ConvertTo-Json -Compress
        [Console]::WriteLine($passOut)
        exit 0
    }
    finally {
        if (Test-Path -LiteralPath $promptFile) {
            Remove-Item -LiteralPath $promptFile -Force -ErrorAction SilentlyContinue
        }
    }
}
catch {
    [Console]::Error.WriteLine("[AI-ADAPTER EXCEPTION] $($_.Exception.Message)")
    exit 4
}
