param(
    [string]$Python = "python",
    [string]$VenvPath = ".venv"
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$requirementsDir = Join-Path $repoRoot "requirements/adapters"
$venvPython = Join-Path $repoRoot "$VenvPath/Scripts/python.exe"

if (-not (Test-Path (Join-Path $repoRoot $VenvPath))) {
    & $Python -m venv (Join-Path $repoRoot $VenvPath)
}

& $venvPython -m pip install --upgrade pip

Get-ChildItem -Path $requirementsDir -Filter *.txt | Sort-Object Name | ForEach-Object {
    & $venvPython -m pip install -r $_.FullName
}

Write-Host "Python adapter environment is ready at $VenvPath"
