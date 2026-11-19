<#
.SYNOPSIS
    Fast-Track Editorial Patch Script for SRS SSOT (patch_ssot_editorial.ps1)
.DESCRIPTION
    Applies minor editorial patches (typos, markdown formatting, whitespace normalization).
    Strictly enforces:
    1. Single exact-match ordinal splicing (prevents multiple accidental replacements).
    2. Zero-delta rejection (no-op prevention).
    3. Structural Invariance: Requirement [REQ-...] and [DDL-...] total counts MUST be 100% identical before and after.
    4. Heavy Track pattern blocking on both target and replacement text.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TargetText,

    [Parameter(Mandatory = $true)]
    [string]$ReplacementText
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
if (-not (Test-Path $projectRoot)) { $projectRoot = (Get-Location).Path }

# 1. Strict Canonical Path Binding (No Path Traversal)
$resolvedSSOT = [System.IO.Path]::GetFullPath((Join-Path $projectRoot "config/srs_specification_ssot.md"))
if (-not (Test-Path $resolvedSSOT)) {
    Write-Error "[FAIL-CLOSED] Canonical SSOT not found at: $resolvedSSOT"
    exit 1
}

# 2. No-op prevention
$comparison = [System.StringComparison]::Ordinal
if ([string]::Equals($TargetText, $ReplacementText, $comparison)) {
    Write-Error "[FAIL-CLOSED] TargetText and ReplacementText are identical (No-op patch rejected)."
    exit 1
}

# 3. Structural Guard: Forbid Heavy-Track intrusions inside editorial patches (Both Target & Replacement)
$heavyTrackPatterns = @(
    "\[REQ-[A-Z]+-[0-9]+\]",
    "\[DDL-[0-9]+\]",
    "CREATE\s+TABLE",
    "ALTER\s+TABLE",
    "DROP\s+TABLE",
    "BigDecimal\s+[a-zA-Z0-9_]+\s*=",
    "SELECT\s+.*FOR\s+UPDATE"
)

foreach ($pattern in $heavyTrackPatterns) {
    if ($ReplacementText -match $pattern -or $TargetText -match $pattern) {
        Write-Error "[FATAL] [PROC-007-CHOKEPOINT] Heavy Track intrusion detected in editorial patch! Pattern matched: '$pattern'. New requirements and DDL changes MUST go through pipeline_draft_and_integrate.ps1 with OpenAI Codex. Direct orchestrator insertion blocked."
        exit 1
    }
}

# 4. Read original content with strict UTF-8
$content = [System.IO.File]::ReadAllText($resolvedSSOT, [System.Text.Encoding]::UTF8)

# 5. Exactly-one-occurrence verification (Codex & Qwen recommendation)
$firstIndex = $content.IndexOf($TargetText, $comparison)
if ($firstIndex -lt 0) {
    Write-Error "[FAIL-CLOSED] Target text not found in SSOT. Exact character-sequence match required."
    exit 1
}
$secondIndex = $content.IndexOf($TargetText, $firstIndex + 1, $comparison)
if ($secondIndex -ge 0) {
    Write-Error "[FAIL-CLOSED] Target text is ambiguous (found multiple occurrences in SSOT). More specific context required."
    exit 1
}

# 6. Apply single-match splicing
$candidate = $content.Remove($firstIndex, $TargetText.Length).Insert($firstIndex, $ReplacementText)

# 7. Structural Invariance Gate: REQ and DDL count check (Claude recommendation)
$origReqCount = ([regex]::Matches($content, "\[REQ-[A-Z]+-[0-9]+\]")).Count
$newReqCount = ([regex]::Matches($candidate, "\[REQ-[A-Z]+-[0-9]+\]")).Count
if ($origReqCount -ne $newReqCount) {
    Write-Error "[FATAL] [PROC-007-INVARIANCE] Requirement count mismatch! Original: $origReqCount, Candidate: $newReqCount. Editorial patches cannot add or delete requirements."
    exit 1
}

$origDdlCount = ([regex]::Matches($content, "\[DDL-[0-9]+\]")).Count
$newDdlCount = ([regex]::Matches($candidate, "\[DDL-[0-9]+\]")).Count
if ($origDdlCount -ne $newDdlCount) {
    Write-Error "[FATAL] [PROC-007-INVARIANCE] DDL count mismatch! Original: $origDdlCount, Candidate: $newDdlCount. Editorial patches cannot add or delete DDL sections."
    exit 1
}

# 8. Atomic replacement with UTF-8 without BOM
$tempFile = [System.IO.Path]::Combine($projectRoot, "config", "srs_ssot_temp.md")
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($tempFile, $candidate, $utf8NoBom)
[System.IO.File]::Copy($tempFile, $resolvedSSOT, $true)
Remove-Item -Force $tempFile -ErrorAction SilentlyContinue

Write-Host ">>> [EDITORIAL PATCH APPLIED] SSOT updated successfully via hardened single-chokepoint." -ForegroundColor Green
exit 0
