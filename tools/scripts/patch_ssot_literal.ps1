<#
.SYNOPSIS
    Deterministic Pure Literal Text Patch Utility (Zero-Escape / Anti-Corruption)
.DESCRIPTION
    Safely replaces an exact, unambiguous substring in a target file without regex evaluation,
    PowerShell variable expansion, or invisible control character contamination.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$TargetFile = "config/srs_specification_ssot.md",

    [Parameter(Mandatory = $false)]
    [string]$TargetText = "",

    [Parameter(Mandatory = $false)]
    [string]$TargetTextFile = "",

    [Parameter(Mandatory = $false)]
    [string]$ReplacementText = "",

    [Parameter(Mandatory = $false)]
    [string]$ReplacementTextFile = "",

    [Parameter(Mandatory = $false)]
    [switch]$AllowMultiple = $false
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
if (-not (Test-Path $projectRoot)) { $projectRoot = (Get-Location).Path }

$resolvedTarget = [System.IO.Path]::GetFullPath((Join-Path $projectRoot $TargetFile))
if (-not $resolvedTarget.StartsWith($projectRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "SECURITY_PATH_TRAVERSAL: Target path escapes repository root: $resolvedTarget"
}
if (-not (Test-Path $resolvedTarget)) {
    throw "TARGET_FILE_NOT_FOUND: $resolvedTarget"
}

# 1. Acquire Target Text
if ($TargetTextFile) {
    $resolvedTargetTextFile = Join-Path $projectRoot $TargetTextFile
    if (-not (Test-Path $resolvedTargetTextFile)) { throw "TARGET_TEXT_FILE_NOT_FOUND: $resolvedTargetTextFile" }
    $TargetText = [System.IO.File]::ReadAllText($resolvedTargetTextFile, [System.Text.Encoding]::UTF8)
}
if ([string]::IsNullOrEmpty($TargetText)) {
    throw "EMPTY_TARGET_TEXT: Target text cannot be empty."
}

# 2. Acquire Replacement Text
if ($ReplacementTextFile) {
    $resolvedReplTextFile = Join-Path $projectRoot $ReplacementTextFile
    if (-not (Test-Path $resolvedReplTextFile)) { throw "REPLACEMENT_TEXT_FILE_NOT_FOUND: $resolvedReplTextFile" }
    $ReplacementText = [System.IO.File]::ReadAllText($resolvedReplTextFile, [System.Text.Encoding]::UTF8)
}

# 3. Validation: Identical check
if ([string]::Equals($TargetText, $ReplacementText, [System.StringComparison]::Ordinal)) {
    throw "IDENTICAL_STRINGS: Target and replacement text are identical. No-op rejected."
}

# 4. Read Target File Content (UTF-8)
$content = [System.IO.File]::ReadAllText($resolvedTarget, [System.Text.Encoding]::UTF8)

# 5. Ordinal Index Verification
$comparison = [System.StringComparison]::Ordinal
$firstIndex = $content.IndexOf($TargetText, $comparison)
if ($firstIndex -lt 0) {
    throw "TARGET_NOT_FOUND: The specified target text was not found in $TargetFile."
}

if (-not $AllowMultiple) {
    $secondIndex = $content.IndexOf($TargetText, $firstIndex + 1, $comparison)
    if ($secondIndex -ge 0) {
        throw "AMBIGUOUS_TARGET: Found multiple occurrences of target text in $TargetFile. Use more context or -AllowMultiple."
    }
    $newContent = $content.Remove($firstIndex, $TargetText.Length).Insert($firstIndex, $ReplacementText)
} else {
    $newContent = $content.Replace($TargetText, $ReplacementText)
}

# 6. Post-Patch Integrity Scan (Control characters check)
$bytes = [System.Text.Encoding]::UTF8.GetBytes($newContent)
for ($i = 0; $i -lt $bytes.Length; $i++) {
    $b = $bytes[$i]
    if ($b -lt 32 -and $b -ne 9 -and $b -ne 10 -and $b -ne 13) {
        throw "CONTROL_CHARACTER_CORRUPTION_DETECTED: Replacement introduced byte 0x$($b.ToString('X2')) at offset $i."
    }
}

# 7. Atomic Write Back with Explicit UTF-8 No BOM via Temporary File
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$tempPath = "${resolvedTarget}.tmp.$([System.Guid]::NewGuid().ToString('N'))"
try {
    [System.IO.File]::WriteAllText($tempPath, $newContent, $utf8NoBom)
    [System.IO.File]::Replace($tempPath, $resolvedTarget, $null)
} finally {
    if (Test-Path $tempPath) { Remove-Item $tempPath -Force -ErrorAction SilentlyContinue }
}

Write-Host "=== [LITERAL PATCH SUCCESS] ===" -ForegroundColor Green
Write-Host "Target: $TargetFile"
Write-Host "Replaced bytes: $($TargetText.Length) -> $($ReplacementText.Length)"
