[CmdletBinding()]
param(
    [string]$PythonPath,
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = $PSScriptRoot
$RegistryKey = 'HKCU:\Software\Classes\*\shell\hyperace'

if ($Uninstall) {
    if (Test-Path -LiteralPath $RegistryKey) {
        Remove-Item -LiteralPath $RegistryKey -Recurse -Force
        Write-Host 'HyperACE Explorer menu removed for the current user.'
    }
    else {
        Write-Host 'HyperACE Explorer menu was not installed for the current user.'
    }
    exit 0
}

if (-not $PythonPath) {
    $PythonPath = Join-Path $ProjectRoot 'venv\Scripts\pythonw.exe'
}

$PythonPath = [System.IO.Path]::GetFullPath($PythonPath)
if (-not (Test-Path -LiteralPath $PythonPath -PathType Leaf)) {
    throw "pythonw.exe was not found: $PythonPath`nCreate the virtual environment first, or pass -PythonPath."
}

$TemplatePath = Join-Path $ProjectRoot 'a.reg'
if (-not (Test-Path -LiteralPath $TemplatePath -PathType Leaf)) {
    throw "Registry template not found: $TemplatePath"
}

$RegistryText = Get-Content -LiteralPath $TemplatePath -Raw
$RegistryText = $RegistryText.Replace('__HYPERACE_ROOT__', $ProjectRoot)
$RegistryText = $RegistryText.Replace('__PYTHONW__', $PythonPath)
$TemporaryReg = Join-Path ([System.IO.Path]::GetTempPath()) "hyperace_context_menu_$PID.reg"

try {
    Set-Content -LiteralPath $TemporaryReg -Value $RegistryText -Encoding Unicode
    & reg.exe import $TemporaryReg
    if ($LASTEXITCODE -ne 0) {
        throw "reg.exe import failed with exit code $LASTEXITCODE."
    }
    Write-Host "HyperACE Explorer menu installed for the current user."
}
finally {
    Remove-Item -LiteralPath $TemporaryReg -Force -ErrorAction SilentlyContinue
}
