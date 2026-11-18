<#
.SYNOPSIS
    SRS テキスト整合性・ヒューマンエラー遮断リンター (VerifySRS_Integrity) 実行スクリプト
.DESCRIPTION
    UTF-8バイト無欠性、不可視文字（Zero-Width）、未確定プレースホルダー（TBD/TODO）、
    重複ブロック、波線エスケープ違反をFail-Closed原則に基づき検証します。
#>
param(
    [Parameter(Mandatory = $false, Position = 0)]
    [string]$TargetFile = "README.md"
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$exePath = Join-Path $scriptDir "VerifySRS_Integrity.exe"
$csPath = Join-Path $scriptDir "VerifySRS_Integrity.cs"

# Check compilation status and rebuild if needed
if (-not (Test-Path $exePath) -or ((Get-Item $csPath).LastWriteTime -gt (Get-Item $exePath).LastWriteTime)) {
    $csc = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
    if (-not (Test-Path $csc)) { $csc = "C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe" }
    & $csc /target:exe /out:$exePath $csPath | Out-Null
}

if (-not (Test-Path $TargetFile)) {
    Write-Error "Target file not found: $TargetFile"
    exit 3
}

& $exePath $TargetFile
exit $LASTEXITCODE
