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
param(
    [Parameter(Mandatory = $false)]
    [switch]$Fix
)

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
Write-Host "`n>>> [Check 1/11] Scanning Git Tracked Files for Leaks & Korean..." -ForegroundColor Yellow
$trackedFiles = git ls-files
if (-not $trackedFiles -or $trackedFiles.Count -eq 0) {
    Write-Host "  [FATAL ERROR] git ls-files returned 0 files! Repository unreadable." -ForegroundColor Red
    exit 1
}

# Generalized private IP ranges (RFC 1918 + Tailscale CGNAT range) & dynamic local user token + local path leaks
$privateIpPattern = '\b(10\.\d{1,3}\.\d{1,3}\.\d{1,3}|192\.168\.\d{1,3}\.\d{1,3}|172\.(1[6-9]|2[0-9]|3[0-1])\.\d{1,3}\.\d{1,3}|100\.(6[4-9]|[7-9]\d|1[01]\d|12[0-7])\.\d{1,3}\.\d{1,3})\b'
$localPathPattern = '([a-zA-Z]:[\\/](Users|dev)[\\/][a-zA-Z0-9_\-]+)'
$userPatterns = @()
if ($env:USERNAME) { $userPatterns += [regex]::Escape($env:USERNAME) }
if ($env:AUDIT_SENSITIVE_KEYWORDS) {
    $env:AUDIT_SENSITIVE_KEYWORDS.Split('|;,') | Where-Object { $_.Trim() } | ForEach-Object { $userPatterns += [regex]::Escape($_.Trim()) }
}
$allPatterns = @($privateIpPattern, $localPathPattern)
if ($userPatterns.Count -gt 0) {
    $allPatterns += ($userPatterns -join '|')
}
$sensitivePattern = "(" + ($allPatterns -join '|') + ")"
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
            if ($f -notmatch 'VerifySRS.*\.cs' -and $f -notmatch 'pre-commit') {
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
Write-Host "`n>>> [Check 2/11] Validating CSV Column Cardinality & Format..." -ForegroundColor Yellow
$integrityExe = Join-Path $scriptDir "VerifySRS.exe"
if (-not (Test-Path $integrityExe)) {
    $integrityExe = Join-Path $scriptDir "VerifySRS_Integrity.exe"
}
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
Write-Host "`n>>> [Check 3/11] Verifying Dashboard Matrix Logical Coherence & SSOT Cardinality..." -ForegroundColor Yellow
$metricsPath = Join-Path $projectRoot "logs\pipeline_metrics.md"
$metricsContent = [System.IO.File]::ReadAllText($metricsPath, [System.Text.Encoding]::UTF8)

$tableLines = $metricsContent -split "`r?`n" | Where-Object { $_ -match '^\|\s*REQ-[A-Z]+-\d+\s*\|' }
$matrixError = $false

# Verify SSOT requirements count matches dashboard matrix rows
$ssotPath = Join-Path $projectRoot "config\srs_specification_ssot.md"
$ssotContent = [System.IO.File]::ReadAllText($ssotPath, [System.Text.Encoding]::UTF8)
$ssotReqMatches = [regex]::Matches($ssotContent, '(?m)^#{3,4}\s*\[(REQ-[A-Z0-9\-]+)\]')
$expectedReqCount = $ssotReqMatches.Count

if ($tableLines.Count -ne $expectedReqCount) {
    Write-Host "  [DASHBOARD DESYNC] Dashboard row count ($($tableLines.Count)) does not match SSOT requirement count ($expectedReqCount)!" -ForegroundColor Red
    $matrixError = $true
}

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
Write-Host "`n>>> [Check 4/11] Verifying Dual-Linter Wiring in hermes_controller.ps1..." -ForegroundColor Yellow
$controllerPath = Join-Path $scriptDir "hermes_controller.ps1"
$controllerText = [System.IO.File]::ReadAllText($controllerPath, [System.Text.Encoding]::UTF8)

$hasIntegrity = $controllerText.Contains("VerifySRS.exe") -or $controllerText.Contains("VerifySRS_Integrity.exe")
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
Write-Host "`n>>> [Check 5/11] Running Deterministic Regression Testbed (11/11)..." -ForegroundColor Yellow
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
Write-Host "`n>>> [Check 6/11] Scanning Tracked Text Files for UTF-8 BOM (0xEF, 0xBB, 0xBF)..." -ForegroundColor Yellow
$bomHits = 0
foreach ($f in $trackedFiles) {
    $fullPath = Join-Path $projectRoot $f
    if (-not (Test-Path $fullPath)) { continue }
    if ($f -match '\.(exe|dll|png|jpg|ico)$') { continue }
    $b = [System.IO.File]::ReadAllBytes($fullPath)
    if ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) {
        if ($Fix) {
            $newBytes = New-Object byte[] ($b.Length - 3)
            [System.Array]::Copy($b, 3, $newBytes, 0, $newBytes.Length)
            [System.IO.File]::WriteAllBytes($fullPath, $newBytes)
            Write-Host "  [AUTO-FIXED] ${f}: Stripped UTF-8 BOM." -ForegroundColor Cyan
        } else {
            Write-Host "  [BOM VIOLATION] $f has UTF-8 BOM!" -ForegroundColor Red
            $bomHits++
        }
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
Write-Host "`n>>> [Check 7/11] Verifying PowerShell Scripts Syntax & Fail-Fast..." -ForegroundColor Yellow
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
Write-Host "`n>>> [Check 8/11] Verifying CURRENT_STATUS.md Bullet Line Integrity..." -ForegroundColor Yellow
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
# Test 8.1: Daily Audit Evidence Dossier Freshness Gate (JA & KO Dual-Gate)
# -------------------------------------------------------------------------
$dossierPath = Join-Path $projectRoot "docs\audit_evidence_dossier.md"
if (Test-Path $dossierPath) {
    $todayStr = (Get-Date).ToString("yyyy-MM-dd")
    $dossierText = [System.IO.File]::ReadAllText($dossierPath, [System.Text.Encoding]::UTF8)
    if ($dossierText -notmatch [regex]::Escape($todayStr)) {
        Write-Host "  [FATAL DOSSIER STALE] audit_evidence_dossier.md is missing today's date ($todayStr) section!" -ForegroundColor Red
        $hasFailure = $true
    } else {
        Write-Host "  -> PASS: audit_evidence_dossier.md firmly contains today's ($todayStr) audit evidence section." -ForegroundColor Green
    }
}

$koDossierPath = Join-Path $projectRoot "docs\audit_evidence_dossier_KO.md"
if (Test-Path $koDossierPath) {
    $todayStr = (Get-Date).ToString("yyyy-MM-dd")
    $koDossierText = [System.IO.File]::ReadAllText($koDossierPath, [System.Text.Encoding]::UTF8)
    if ($koDossierText -notmatch [regex]::Escape($todayStr)) {
        Write-Host "  [FATAL DOSSIER STALE] audit_evidence_dossier_KO.md is missing today's date ($todayStr) section!" -ForegroundColor Red
        $hasFailure = $true
    } else {
        Write-Host "  -> PASS: audit_evidence_dossier_KO.md firmly contains today's ($todayStr) audit evidence section." -ForegroundColor Green
    }
}

# -------------------------------------------------------------------------
# Test 9: Invisible Control Characters Gate (BEL/BS/FF/ESC etc.)
# -------------------------------------------------------------------------
Write-Host "`n>>> [Check 9/11] Scanning Tracked Source & Markdown Files for Control Characters..." -ForegroundColor Yellow
$ctrlScanFiles = $trackedFiles | Where-Object { $_ -match '\.(md|java|json|ps1|csv)$' }
$ctrlHits = 0
foreach ($f in $ctrlScanFiles) {
    $fullPath = Join-Path $projectRoot $f
    if (-not (Test-Path $fullPath)) { continue }
    $bytes = [System.IO.File]::ReadAllBytes($fullPath)
    
    # 1. Guard against UTF-16 BOM (LE: 0xFF 0xFE, BE: 0xFE 0xFF)
    # Avoid stripping 0x00 (NUL) bytes in UTF-16 encoded files
    if ($bytes.Length -ge 2 -and (($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) -or ($bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF))) {
        continue
    }

    $hasCtrl = $false
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        $b = $bytes[$i]
        if ($b -lt 32 -and $b -ne 9 -and $b -ne 10 -and $b -ne 13) {
            $hasCtrl = $true
            break
        }
    }
    if ($hasCtrl) {
        if ($Fix) {
            $cleaned = New-Object System.Collections.Generic.List[byte]
            for ($i = 0; $i -lt $bytes.Length; $i++) {
                $byteVal = $bytes[$i]
                if ($byteVal -ge 32 -or $byteVal -eq 9 -or $byteVal -eq 10 -or $byteVal -eq 13) {
                    $cleaned.Add($byteVal)
                }
            }
            # Atomic file replace (Avoid in-place write corruption)
            $tempPath = "$fullPath.tmp.$([System.Guid]::NewGuid().ToString('N'))"
            try {
                [System.IO.File]::WriteAllBytes($tempPath, $cleaned.ToArray())
                [System.IO.File]::Copy($tempPath, $fullPath, $true)
                Remove-Item -Force $tempPath -ErrorAction SilentlyContinue
                Write-Host "  [AUTO-FIXED] ${f}: Stripped invisible control characters." -ForegroundColor Cyan
            } finally {
                if (Test-Path $tempPath) {
                    Remove-Item -Force $tempPath -ErrorAction SilentlyContinue
                }
            }
        } else {
            Write-Host "  [CONTROL CHAR DETECTED] ${f} has non-printable control characters!" -ForegroundColor Red
            $ctrlHits++
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
Write-Host "`n>>> [Check 10/11] Verifying Relative Hyperlinks Across All Markdown Files..." -ForegroundColor Yellow
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

# -------------------------------------------------------------------------
# Test 11: External Audit Verdict & Sidecar Fail-Closed Gate (Worst Verdict Wins)
# -------------------------------------------------------------------------
Write-Host "`n>>> [Check 11/11] Verifying External Audit Verdicts & Sidecars (Worst Verdict Wins)..." -ForegroundColor Yellow
$auditRunsDirs = @(
    (Join-Path $projectRoot "audit\runs"),
    (Join-Path $projectRoot "docs\audit_runs")
)

$thresholdTime = [System.DateTime]::UtcNow.AddHours(-24)
$recentVerdicts = @()
$sidecarFails = 0

foreach ($ard in $auditRunsDirs) {
    if (-not (Test-Path $ard)) { continue }
    $verdictFiles = Get-ChildItem -Path $ard -Filter "verdict.json" -Recurse
    foreach ($vf in $verdictFiles) {
        if ($vf.LastWriteTimeUtc -ge $thresholdTime) {
            try {
                $vJson = [System.IO.File]::ReadAllText($vf.FullName, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
                if ($vJson.schema -ne "audit-verdict/v1" -or (-not $vJson.verdict)) {
                    Write-Host "  [INVALID SIDECAR] $($vf.FullName) does not conform to audit-verdict/v1 schema." -ForegroundColor Red
                    $sidecarFails++
                    continue
                }

                # Fail-Closed: response_sha256 must be present and valid
                if ([string]::IsNullOrWhiteSpace($vJson.response_sha256) -or $vJson.response_sha256 -eq "NONE") {
                    Write-Host "  [INVALID SIDECAR] $($vf.FullName) has missing or NONE response_sha256! Fail-Closed." -ForegroundColor Red
                    $sidecarFails++
                    continue
                }

                # Find associated raw response artifact
                $runDir = $vf.DirectoryName
                $possibleRaws = Get-ChildItem -Path $runDir | Where-Object { 
                    $_.Name -match '(raw.*\.json|report.*\.txt|raw_response\.txt|codex_report.*\.txt)' -and $_.Name -ne "verdict.json"
                }

                if ($possibleRaws.Count -eq 0) {
                    Write-Host "  [MISSING RAW ARTIFACT] $($vf.FullName) has no associated raw report/response file in $runDir! Fail-Closed." -ForegroundColor Red
                    $sidecarFails++
                    continue
                }

                $matchedRaw = $false
                foreach ($rf in $possibleRaws) {
                    $rawBytes = [System.IO.File]::ReadAllBytes($rf.FullName)
                    $sha = [System.Security.Cryptography.SHA256]::Create()
                    $calcSha = ([BitConverter]::ToString($sha.ComputeHash($rawBytes)) -replace '-', '').ToLowerInvariant()
                    $sha.Dispose()
                    if ($calcSha -eq $vJson.response_sha256.ToString().ToLowerInvariant()) {
                        $matchedRaw = $true
                        break
                    }
                }

                if (-not $matchedRaw) {
                    if ($Fix) {
                        $canHeal = $false
                        $healedSha = $null
                        foreach ($rf in $possibleRaws) {
                            $rawBytes = [System.IO.File]::ReadAllBytes($rf.FullName)
                            $bytesWithBom = if ($rawBytes.Length -ge 3 -and $rawBytes[0] -eq 0xEF -and $rawBytes[1] -eq 0xBB -and $rawBytes[2] -eq 0xBF) {
                                $rawBytes
                            } else {
                                $tempWithBom = New-Object byte[] ($rawBytes.Length + 3)
                                $tempWithBom[0] = 0xEF; $tempWithBom[1] = 0xBB; $tempWithBom[2] = 0xBF
                                [System.Array]::Copy($rawBytes, 0, $tempWithBom, 3, $rawBytes.Length)
                                $tempWithBom
                            }
                            $sha = [System.Security.Cryptography.SHA256]::Create()
                            $shaBom = ([BitConverter]::ToString($sha.ComputeHash($bytesWithBom)) -replace '-', '').ToLowerInvariant()
                            $shaClean = ([BitConverter]::ToString($sha.ComputeHash($rawBytes)) -replace '-', '').ToLowerInvariant()
                            $sha.Dispose()

                            if ($vJson.response_sha256.ToString().ToLowerInvariant() -eq $shaBom) {
                                $canHeal = $true
                                $healedSha = $shaClean
                                break
                            }
                        }

                        if ($canHeal -and $healedSha) {
                            $vJson.response_sha256 = $healedSha
                            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
                            $jsonText = $vJson | ConvertTo-Json -Depth 5
                            [System.IO.File]::WriteAllText($vf.FullName, $jsonText, $utf8NoBom)
                            Write-Host "  [AUTO-HEALED SIDECAR] $($vf.FullName): Synchronized post-canonical SHA-256." -ForegroundColor Cyan
                            $matchedRaw = $true
                        }
                    }

                    if (-not $matchedRaw) {
                        Write-Host "  [TAMPERED ARTIFACT] $($vf.FullName) response_sha256 does not match any raw artifact in $runDir! Fail-Closed." -ForegroundColor Red
                        $sidecarFails++
                        continue
                    }
                }

                $recentVerdicts += [PSCustomObject]@{
                    Auditor = $vJson.auditor
                    Verdict = $vJson.verdict.ToString().ToUpperInvariant()
                    RunId = $vJson.run_id
                    P0P1Count = $vJson.p0_p1_count
                    Path = $vf.FullName
                    Time = $vf.LastWriteTimeUtc
                }
            } catch {
                Write-Host "  [CORRUPT SIDECAR] $($vf.FullName): $_" -ForegroundColor Red
                $sidecarFails++
            }
        }
    }
}

# Group by auditor and evaluate Worst Verdict Wins
$hasAdverseVerdict = $false
$auditorGroups = $recentVerdicts | Group-Object -Property Auditor
$queueFile = Join-Path $projectRoot "queue\srs_pending_findings.json"
$queueObj = $null
if (Test-Path $queueFile) {
    try {
        $queueObj = [System.IO.File]::ReadAllText($queueFile, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        if (-not $queueObj.findings -or $queueObj.declared_count -ne $queueObj.findings.Count) {
            Write-Host "  [QUEUE SCHEMA ERROR] srs_pending_findings.json declared_count ($($queueObj.declared_count)) mismatches actual findings count ($($queueObj.findings.Count))!" -ForegroundColor Red
            $sidecarFails++
            $queueObj = $null
        } else {
            $dupIds = $queueObj.findings | Group-Object -Property id | Where-Object { $_.Count -gt 1 }
            if ($dupIds) {
                Write-Host "  [QUEUE DUPLICATE ID] srs_pending_findings.json contains duplicate finding ID: $($dupIds[0].Name)" -ForegroundColor Red
                $sidecarFails++
                $queueObj = $null
            }
            foreach ($qf in $queueObj.findings) {
                if (-not $qf.id -or -not $qf.status -or -not $qf.evidence -or $qf.evidence.ToString().Trim().Length -lt 10) {
                    Write-Host "  [QUEUE EVIDENCE MISSING] Finding '$($qf.id)' has empty or insufficient physical evidence!" -ForegroundColor Red
                    $sidecarFails++
                    $queueObj = $null
                    break
                }
                if ($qf.closure_predicates) {
                    foreach ($pred in $qf.closure_predicates) {
                        $predFile = Join-Path $projectRoot $pred.file
                        if (-not (Test-Path $predFile)) {
                            Write-Host "  [CLOSURE PREDICATE FAIL] Finding '$($qf.id)' target file missing: $($pred.file)" -ForegroundColor Red
                            $sidecarFails++
                            $queueObj = $null
                            break
                        }
                        $predContent = [System.IO.File]::ReadAllText($predFile, [System.Text.Encoding]::UTF8)
                        if ($pred.must_contain_regex -and ($predContent -notmatch $pred.must_contain_regex)) {
                            Write-Host "  [CLOSURE PREDICATE FAIL] Finding '$($qf.id)' regex '$($pred.must_contain_regex)' not satisfied in $($pred.file)!" -ForegroundColor Red
                            $sidecarFails++
                            $queueObj = $null
                            break
                        }
                    }
                }
            }
        }
    } catch {
        Write-Host "  [QUEUE PARSE ERROR] srs_pending_findings.json is malformed JSON! Fail-Closed." -ForegroundColor Red
        $sidecarFails++
        $queueObj = $null
    }
}

foreach ($ag in $auditorGroups) {
    $latest = $ag.Group | Sort-Object -Property Time -Descending | Select-Object -First 1
    # Check if latest verdict in the active window on this auditor issued HOLD or FAIL
    if ($latest.Verdict -eq "HOLD" -or $latest.Verdict -eq "FAIL") {
        # Check if all adverse findings have been formalized and verified in the central queue
        $allResolvedInQueue = $false
        if ($queueObj -and $queueObj.findings) {
            $unresolvedCount = 0
            try {
                $vData = [System.IO.File]::ReadAllText($latest.Path, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
                if ($vData.findings -and $vData.findings.Count -gt 0) {
                    foreach ($f in $vData.findings) {
                        $fId = if ($f.finding_id) { $f.finding_id } elseif ($f.id) { $f.id } else { "" }
                        if (-not $fId) {
                            $unresolvedCount++
                        } else {
                            $qMatch = $queueObj.findings | Where-Object { $_.id -eq $fId -and ($_.status -eq "VERIFIED" -or $_.status -eq "RESOLVED" -or $_.status -eq "CLOSED") }
                            if (-not $qMatch) {
                                $unresolvedCount++
                            }
                        }
                    }
                    if ($unresolvedCount -eq 0) {
                        $allResolvedInQueue = $true
                    }
                }
            } catch {
                $allResolvedInQueue = $false
            }
        }

        if ($allResolvedInQueue) {
            Write-Host "  [QUEUE-RESOLVED ADVERSE VERDICT] Auditor '$($ag.Name)' adverse verdict in $($latest.Path) is fully VERIFIED in queue. Passing." -ForegroundColor Green
        } else {
            Write-Host "  [UNRESOLVED ADVERSE VERDICT] Auditor '$($ag.Name)' has unresolved $($latest.Verdict) verdict in: $($latest.Path)" -ForegroundColor Red
            $hasAdverseVerdict = $true
        }
    }
}

if ($sidecarFails -gt 0 -or $hasAdverseVerdict) {
    Write-Host "  -> FAIL: Active adverse external audit verdicts exist! Fix defects and obtain a PASS verdict." -ForegroundColor Red
    $hasFailure = $true
} else {
    Write-Host "  -> PASS: All active external audit sidecars ($($recentVerdicts.Count) found) satisfy Fail-Closed clean integrity." -ForegroundColor Green
}

Write-Host "`n=================================================================" -ForegroundColor Cyan
$traceLogPath = Join-Path $projectRoot "logs\incident_execution_trace.log"
$timestampUtc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

if ($hasFailure) {
    if (Test-Path $traceLogPath) {
        $logLine = "[$timestampUtc] [VERIFY_REPO] [STATUS: FAIL] [CODE: ERR-INTEGRITY-FAILED] [MSG: Repository total integrity verification detected violations]"
        [System.IO.File]::AppendAllText($traceLogPath, "$logLine`n", [System.Text.Encoding]::UTF8)
    }
    Write-Host " [VERDICT: FAIL] Repository has integrity violations! Abort release." -ForegroundColor Red
    exit 1
} else {
    if (Test-Path $traceLogPath) {
        $logLine = "[$timestampUtc] [VERIFY_REPO] [STATUS: PASS] [CODE: OK] [MSG: All 10 repository total integrity checks passed cleanly]"
        [System.IO.File]::AppendAllText($traceLogPath, "$logLine`n", [System.Text.Encoding]::UTF8)
    }
    Write-Host " [VERDICT: ALL PASS] Repository is 100% Clean, Consistent & Verified." -ForegroundColor Green
    exit 0
}
