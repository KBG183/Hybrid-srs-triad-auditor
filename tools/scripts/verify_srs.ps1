param(
    [Parameter(Mandatory = $true)]
    [string]$TargetFile
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$csFile = Join-Path $scriptDir "VerifySRS_Deterministic.cs"
$exeFile = Join-Path $scriptDir "VerifySRS_Deterministic.exe"

# C# compilation (when missing or updated)
$csc = [System.IO.Path]::Combine($env:WINDIR, "Microsoft.NET\Framework64\v4.0.30319\csc.exe")
if (-not (Test-Path $csc)) {
    $csc = [System.IO.Path]::Combine($env:WINDIR, "Microsoft.NET\Framework\v4.0.30319\csc.exe")
}

if (-not (Test-Path $exeFile) -or ((Get-Item $csFile).LastWriteTime -gt (Get-Item $exeFile).LastWriteTime)) {
    Write-Host "[COMPILE] Compiling C# Deterministic Linter..." -ForegroundColor Cyan
    & $csc /nologo /out:$exeFile $csFile
    if ($LASTEXITCODE -ne 0) {
        Write-Error "C# linter compilation failed"
        exit 1
    }
}

& $exeFile $TargetFile
exit $LASTEXITCODE