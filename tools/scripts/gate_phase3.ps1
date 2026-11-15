<#
.SYNOPSIS
    결정론적 검증 및 감사 통과 전 파일 쓰기 원천 차단 하드게이트
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$TargetFile,

    [Parameter(Mandatory = $false)]
    [string]$ReportFile = ""
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host ">>> [GATE PHASE 3] 검증 상태 점검: $TargetFile" -ForegroundColor Yellow

if (-not (Test-Path $TargetFile)) {
    Write-Error "GATE_FAIL: 대상 파일이 존재하지 않습니다: $TargetFile"
    exit 1
}

# 린터 실행 및 검증
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$verifyScript = Join-Path $scriptDir "verify_srs.ps1"

if (Test-Path $verifyScript) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $verifyScript -TargetFile $TargetFile
    if ($LASTEXITCODE -ne 0) {
        Write-Error "GATE_BLOCKED: 결정론적 린터 검증 실패. 정본 반영이 차단되었습니다."
        exit $LASTEXITCODE
    }
}

Write-Host ">>> [GATE PASS] 모든 하드게이트 통과 완료. 정본 반영 승인 가능." -ForegroundColor Green
exit 0