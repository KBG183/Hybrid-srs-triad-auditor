<#
.SYNOPSIS
    KINTAI Repository Total Integrity Master Auditor
.DESCRIPTION
    Runs exhaustive deterministic multi-point verification across all Git tracked files:
    1. Sensitive Pattern & Private IP Scan (Zero tolerance)
    2. Zero-Korean Unicode Hard-Gate (Zero tolerance in public files)
    3. CSV Column Cardinality & RFC 4180 Integrity
    4. Dashboard vs Audit Ledger State Alignment
    5. Dual-Linter Pipeline Hard-Gate Wiring
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
if (-not (Test-Path $projectRoot)) { $projectRoot = (Get-Location).Path }

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host " [MASTER AUDITOR] Running Repository Total Integrity Verification" -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan

$hasFailure = $false

# -------------------------------------------------------------------------
# Test 1: Tracked Files Sensitive Data & Zero-Korean Scan
# -------------------------------------------------------------------------
Write-Host "`n>>> [Check 1/10] Scanning Git Tracked Files for Leaks & Korean..." -ForegroundColor Yellow
$trackedFiles = git ls-files
if (-not $trackedFiles -or $trackedFiles.Count -eq 0) {
    Write-Host "  [FATAL ERROR] git ls-files returned 0 files! Repository unreadable." -ForegroundColor Red
    exit 1
}

# Generalized private IP ranges (RFC 1918 + Tailscale CGNAT range) & dynamic local user token
$privateIpPattern = '\b(10\.\d{1,3}\.\d{1,3}\.\d{1,3}|192\.168\.\d{1,3}\.\d{1,3}|172\.(1[6-9]|2[0-9]|3[0-1])\.\d{1,3}\.\d{1,3}|100\.(6[4-9]|[7-9]\d|1[01]\d|12[0-7])\.\d{1,3}\.\d{1,3})\b'
$userPatterns = @()
if ($env:USERNAME) { $userPatterns += [regex]::Escape($env:USERNAME) }
if ($env:AUDIT_SENSITIVE_KEYWORDS) {
    $env:AUDIT_SENSITIVE_KEYWORDS.Split('|;,') | Where-Object { $_.Trim() } | ForEach-Object { $userPatterns += [regex]::Escape($_.Trim()) }
}
$sensitivePattern = if ($userPatterns.Count -gt 0) {
    "($privateIpPattern|" + ($userPatterns -join '|') + ")"
} else {
    $privateIpPattern
}
$koreanPattern = '[\uAC00-\uD7A3\u1100-\u11FF\u3130-\u318F\uA960-\uA97F\uD7B0-\uD7FF\uFFA0-\uFFDC]'

$sensitiveHits = 0
$koreanHits = 0

foreach ($f in $trackedFiles) {
    $fullPath = Join-Path $projectRoot $f
    if (-not (Test-Path $fullPath)) { continue }
    if ($f -match '\.(exe|dll|png|jpg|ico)$') { continue }
    if ($f -match '_KO\.|_ko\.') { continue }

    $lines = [System.IO.File]::ReadAllLines($fullPath, [System.Text.Encoding]::UTF8)
    for ($i = 0; $i -lt $lines.Length; $i++) {
        $line = $lines[$i]
        if ($line -match $sensitivePattern) {
            if ($f -notmatch 'VerifySRS_Integrity\.cs' -and $f -notmatch 'pre-commit') {
                Write-Host "  [LEAK] ${f}:$($i+1) : $($line.Trim())" -ForegroundColor Red
                $sensitiveHits++
            }
        }
        if ($line -match $koreanPattern) {
            Write-Host "  [KOREAN] ${f}:$($i+1) : $($line.Trim())" -ForegroundColor Red
            $koreanHits++
        }
    }
}

if ($sensitiveHits -eq 0 -and $koreanHits -eq 0) {
    Write-Host "  -> PASS: 0 Sensitive patterns, 0 Korean characters detected across $($trackedFiles.Count) files." -ForegroundColor Green
} else {
    Write-Host "  -> FAIL: Found $sensitiveHits sensitive leaks and $koreanHits Korean characters." -ForegroundColor Red
    $hasFailure = $true
}

# -------------------------------------------------------------------------
# Test 2: CSV Column Cardinality & RFC 4180 Integrity
# -------------------------------------------------------------------------
Write-Host "`n>>> [Check 2/10] Validating CSV Column Cardinality & Format..." -ForegroundColor Yellow
$integrityExe = Join-Path $scriptDir "VerifySRS_Integrity.exe"
$csvFiles = @("logs\local_token_ledger.csv", "logs\cloud_api_token_ledger.csv", "logs\codex_token_ledger.csv", "logs\pipeline_metrics.csv", "logs\enterprise_audit_ledger.csv")
$csvFail = $false

foreach ($csv in $csvFiles) {
    $fullPath = Join-Path $projectRoot $csv
    $out = & $integrityExe $fullPath 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [CSV ERROR] $csv failed integrity check." -ForegroundColor Red
        $csvFail = $true
    }
}

if (-not $csvFail) {
    Write-Host "  -> PASS: All CSV ledgers strictly conform to column cardinality rules." -ForegroundColor Green
} else {
    $hasFailure = $true
}

# -------------------------------------------------------------------------
# Test 3: Dashboard Matrix Mathematical & Logical Consistency
# -------------------------------------------------------------------------
Write-Host "`n>>> [Check 3/10] Verifying Dashboard Matrix Logical Coherence..." -ForegroundColor Yellow
$metricsPath = Join-Path $projectRoot "logs\pipeline_metrics.md"
$metricsContent = [System.IO.File]::ReadAllText($metricsPath, [System.Text.Encoding]::UTF8)

$tableLines = $metricsContent -split "`r?`n" | Where-Object { $_ -match '^\|\s*REQ-[A-Z]+-\d+\s*\|' }
$matrixError = $false

foreach ($row in $tableLines) {
    $cols = $row.Split('|') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
    if ($cols.Count -ge 7) {
        $id = $cols[0]
        $linter = $cols[2]
        $qwen = $cols[3]
        $codex = $cols[4]
        $claude = $cols[5]
        $finalVerdict = $cols[6]

        $hasAnyFinding = ($linter -ne "PASS") -or ($qwen -like "*FINDINGS*") -or ($codex -like "*FINDINGS*") -or ($claude -like "*FINDINGS*")
        $expectedVerdict = if ($hasAnyFinding) { "**REVISE_PENDING**" } else { "**PASS**" }

        if ($finalVerdict -ne $expectedVerdict) {
            Write-Host "  [DASHBOARD ERROR] Row $id verdict mismatch! Expected: $expectedVerdict, Found: $finalVerdict" -ForegroundColor Red
            $matrixError = $true
        }
    }
}

if ($matrixError) {
    $hasFailure = $true
} elseif ($tableLines.Count -eq 0) {
    Write-Host "  [DASHBOARD ERROR] No requirement verification rows found in pipeline_metrics.md table." -ForegroundColor Red
    $hasFailure = $true
} else {
    Write-Host "  -> PASS: All $($tableLines.Count) requirement matrix rows satisfy Fail-Closed boolean logic coherence." -ForegroundColor Green
}

# -------------------------------------------------------------------------
# Test 4: Dual-Linter Pipeline Hard-Gate Wiring
# -------------------------------------------------------------------------
Write-Host "`n>>> [Check 4/10] Verifying Dual-Linter Wiring in hermes_controller.ps1..." -ForegroundColor Yellow
$controllerPath = Join-Path $scriptDir "hermes_controller.ps1"
$controllerText = [System.IO.File]::ReadAllText($controllerPath, [System.Text.Encoding]::UTF8)

$hasIntegrity = $controllerText.Contains("VerifySRS_Integrity.exe")
$hasDeterministic = $controllerText.Contains("verify_srs.ps1")

if ($hasIntegrity -and $hasDeterministic) {
    Write-Host "  -> PASS: Both VerifySRS_Integrity and VerifySRS_Deterministic are firmly wired in pipeline." -ForegroundColor Green
} else {
    Write-Host "  [WIRING ERROR] hermes_controller.ps1 is missing dual-linter execution logic." -ForegroundColor Red
    $hasFailure = $true
}

# -------------------------------------------------------------------------
# Test 5: C# Deterministic Regression Testbed (11/11)
# -------------------------------------------------------------------------
Write-Host "`n>>> [Check 5/10] Running Deterministic Regression Testbed (11/11)..." -ForegroundColor Yellow
$regExe = Join-Path $scriptDir "TestV52Suite_Regression.exe"
$regOut = & $regExe 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "  -> PASS: All 11 boundary regression test cases deterministically passed." -ForegroundColor Green
} else {
    Write-Host "  [REGRESSION FAIL] Regression suite returned exit code $LASTEXITCODE." -ForegroundColor Red
    $hasFailure = $true
}

# -------------------------------------------------------------------------
# Test 6: UTF-8 BOM Zero Tolerance Hard-Gate
# -------------------------------------------------------------------------
Write-Host "`n>>> [Check 6/10] Scanning Tracked Text Files for UTF-8 BOM (0xEF, 0xBB, 0xBF)..." -ForegroundColor Yellow
$bomHits = 0
foreach ($f in $trackedFiles) {
    $fullPath = Join-Path $projectRoot $f
    if (-not (Test-Path $fullPath)) { continue }
    if ($f -match '\.(exe|dll|png|jpg|ico)$') { continue }
    $b = [System.IO.File]::ReadAllBytes($fullPath)
    if ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) {
        Write-Host "  [BOM VIOLATION] $f has UTF-8 BOM!" -ForegroundColor Red
        $bomHits++
    }
}
if ($bomHits -eq 0) {
    Write-Host "  -> PASS: 0 UTF-8 BOM bytes detected across all tracked text files." -ForegroundColor Green
} else {
    Write-Host "  -> FAIL: Found $bomHits files with UTF-8 BOM." -ForegroundColor Red
    $hasFailure = $true
}

# -------------------------------------------------------------------------
# Test 7: PowerShell Scripts Syntax & Fail-Fast Gate
# -------------------------------------------------------------------------
Write-Host "`n>>> [Check 7/10] Verifying PowerShell Scripts Syntax & Fail-Fast..." -ForegroundColor Yellow
$ps1Files = Get-ChildItem -Path (Join-Path $projectRoot "tools\scripts") -Filter "*.ps1"
$ps1Fail = 0
foreach ($ps in $ps1Files) {
    # 1. AST Syntax Parse
    $parseErrors = $null
    $parseTokens = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($ps.FullName, [ref]$parseTokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        Write-Host "  [SYNTAX ERROR] $($ps.Name): $($parseErrors[0].Message)" -ForegroundColor Red
        $ps1Fail++
        continue
    }

    # 2. Fail-Fast Declaration Check
    $psContent = [System.IO.File]::ReadAllText($ps.FullName, [System.Text.Encoding]::UTF8)
    if ($psContent -notmatch "\`$ErrorActionPreference\s*=\s*['""]Stop['""]") {
        Write-Host "  [FAIL-FAST MISSING] $($ps.Name) is missing `$ErrorActionPreference = 'Stop' declaration." -ForegroundColor Red
        $ps1Fail++
    }
}
if ($ps1Fail -eq 0) {
    Write-Host "  -> PASS: All $($ps1Files.Count) PowerShell scripts are syntax-valid and enforce Fail-Fast (`$ErrorActionPreference = 'Stop')." -ForegroundColor Green
} else {
    Write-Host "  -> FAIL: Found $ps1Fail scripts with syntax or Fail-Fast defects." -ForegroundColor Red
    $hasFailure = $true
}

# -------------------------------------------------------------------------
# Test 8: Status Ledger Duplicate Bullet & Integrity Gate
# -------------------------------------------------------------------------
Write-Host "`n>>> [Check 8/10] Verifying CURRENT_STATUS.md Bullet Line Integrity..." -ForegroundColor Yellow
$csPath = Join-Path $projectRoot "logs\CURRENT_STATUS.md"
if (-not (Test-Path $csPath)) {
    Write-Host "  [INTEGRITY ERROR] CURRENT_STATUS.md does not exist at: $csPath" -ForegroundColor Red
    $hasFailure = $true
} else {
    $csLines = [System.IO.File]::ReadAllLines($csPath, [System.Text.Encoding]::UTF8)
    $healthLineCount = 0
    $jaHealthLabel = [System.Text.Encoding]::UTF8.GetString(@(0xE6, 0x9C, 0x80, 0xE6, 0x96, 0xB0, 0xE3, 0x83, 0x98, 0xE3, 0x83, 0xAB, 0xE3, 0x82, 0xB9, 0xE3, 0x83, 0x81, 0xE3, 0x82, 0xA7, 0xE3, 0x83, 0x83, 0xE3, 0x82, 0xAF, 0xE5, 0x88, 0xA4, 0xE5, 0xAE, 0x9A))
    $healthPattern = "^- \*\*" + [regex]::Escape($jaHealthLabel) + "\*\*:"
    foreach ($line in $csLines) {
        if ($line -match $healthPattern) {
            $healthLineCount++
        }
    }
    if ($healthLineCount -ne 1) {
        Write-Host "  [INTEGRITY ERROR] CURRENT_STATUS.md expected exactly 1 health check line, but found: $healthLineCount!" -ForegroundColor Red
        $hasFailure = $true
    } else {
        Write-Host "  -> PASS: CURRENT_STATUS.md has exactly $healthLineCount health check line (Zero duplication, Valid structure)." -ForegroundColor Green
    }
}

# -------------------------------------------------------------------------
# Test 9: Invisible Control Characters Gate (BEL/BS/FF/ESC etc.)
# -------------------------------------------------------------------------
Write-Host "`n>>> [Check 9/10] Scanning Tracked Source & Markdown Files for Control Characters..." -ForegroundColor Yellow
$ctrlScanFiles = $trackedFiles | Where-Object { $_ -match '\.(md|java|json|ps1|csv)$' }
$ctrlHits = 0
foreach ($f in $ctrlScanFiles) {
    $fullPath = Join-Path $projectRoot $f
    if (-not (Test-Path $fullPath)) { continue }
    $bytes = [System.IO.File]::ReadAllBytes($fullPath)
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        $b = $bytes[$i]
        if ($b -lt 32 -and $b -ne 9 -and $b -ne 10 -and $b -ne 13) {
            Write-Host "  [CONTROL CHAR DETECTED] ${f} byte offset $($i): 0x$($b.ToString('X2'))" -ForegroundColor Red
            $ctrlHits++
            break
        }
    }
}
if ($ctrlHits -eq 0) {
    Write-Host "  -> PASS: 0 Invisible control characters detected across $($ctrlScanFiles.Count) text/source files." -ForegroundColor Green
} else {
    Write-Host "  -> FAIL: Found $ctrlHits files contaminated with non-printable control characters." -ForegroundColor Red
    $hasFailure = $true
}

# -------------------------------------------------------------------------
# Test 10: Markdown Relative Link Physical Integrity Gate
# -------------------------------------------------------------------------
Write-Host "`n>>> [Check 10/10] Verifying Relative Hyperlinks Across All Markdown Files..." -ForegroundColor Yellow
$allMdFiles = Get-ChildItem -Path $projectRoot -Filter "*.md" -Recurse | Where-Object { $_.FullName -notmatch '\\\.git\\' -and $_.FullName -notmatch '\\scratch\\' }
$brokenCount = 0
$checkedLinkCount = 0

foreach ($mf in $allMdFiles) {
    $content = [System.IO.File]::ReadAllText($mf.FullName, [System.Text.Encoding]::UTF8)
    $dir = $mf.DirectoryName
    $linkMatches = [regex]::Matches($content, '\[([^\]]+)\]\(([^)]+)\)')
    foreach ($m in $linkMatches) {
        $linkPath = $m.Groups[2].Value.Trim()
        if ($linkPath -match '^(http|https|mailto|ftp):' -or $linkPath -match '^#') { continue }
        $checkedLinkCount++
        $cleanPath = $linkPath.Split('#')[0]
        if (-not $cleanPath) { continue }
        
        $resolved = [System.IO.Path]::Combine($dir, $cleanPath)
        if (-not (Test-Path $resolved)) {
            Write-Host "  [BROKEN LINK] $($mf.Name) -> '$linkPath' (Cannot resolve: $resolved)" -ForegroundColor Red
            $brokenCount++
        }
    }
}
if ($brokenCount -eq 0) {
    Write-Host "  -> PASS: All $checkedLinkCount relative hyperlinks across $($allMdFiles.Count) markdown files physically exist." -ForegroundColor Green
} else {
    Write-Host "  -> FAIL: Found $brokenCount broken relative hyperlinks in repository." -ForegroundColor Red
    $hasFailure = $true
}

Write-Host "`n=================================================================" -ForegroundColor Cyan
if ($hasFailure) {
    Write-Host " [VERDICT: FAIL] Repository has integrity violations! Abort release." -ForegroundColor Red
    exit 1
} else {
    Write-Host " [VERDICT: ALL PASS] Repository is 100% Clean, Consistent & Verified." -ForegroundColor Green
    exit 0
}
