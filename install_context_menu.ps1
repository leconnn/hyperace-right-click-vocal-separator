<#
.SYNOPSIS
    Adds (or removes) the "HyperACE" entry in the Windows Explorer right-click menu.

.DESCRIPTION
    Before touching the registry, this script checks that everything the separator
    needs is in place and tells you exactly how to fix anything that is missing:

      1. The Python environment (venv\Scripts\pythonw.exe by default)
      2. The required Python packages (PyTorch, librosa, ...)
      3. GPU support (optional; CPU works, just slower)
      4. The HyperACE model checkpoints

    It then adds a "HyperACE" submenu with "Separate vocals" and
    "Separate instrumentals" to supported audio files. The menu is installed for
    the current Windows user only, so Administrator rights are not needed.

.PARAMETER PythonPath
    Full path to the pythonw.exe to use. Defaults to venv\Scripts\pythonw.exe in
    this folder.

.PARAMETER Uninstall
    Removes the HyperACE right-click menu.

.PARAMETER Force
    Installs the menu even if some checks fail.

.EXAMPLE
    PowerShell -ExecutionPolicy Bypass -File .\install_context_menu.ps1

.EXAMPLE
    PowerShell -ExecutionPolicy Bypass -File .\install_context_menu.ps1 -Uninstall
#>
[CmdletBinding()]
param(
    [string]$PythonPath,
    [switch]$Uninstall,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = $PSScriptRoot
$MenuKey = 'Software\Classes\*\shell\hyperace'
$AudioExtensions = '.wav', '.mp3', '.aac', '.flac', '.ogg', '.wma', '.m4a', '.aiff', '.opus',
                   '.alac', '.mp2', '.mp1', '.amr', '.ape', '.au', '.ra', '.tta'

function Write-Step([string]$Text) { Write-Host "`n$Text" -ForegroundColor Cyan }
function Write-Ok([string]$Text) { Write-Host "  [OK]   $Text" -ForegroundColor Green }
function Write-Warn([string]$Text) { Write-Host "  [WARN] $Text" -ForegroundColor Yellow }
function Write-Fail([string]$Text) { Write-Host "  [FAIL] $Text" -ForegroundColor Red }
function Write-Hint([string]$Text) { Write-Host "         $Text" -ForegroundColor Gray }

Write-Host 'HyperACE Right-Click Vocal Separator - context menu installer' -ForegroundColor White
Write-Host "Folder: $ProjectRoot"

# ---------------------------------------------------------------------------
# Uninstall
# ---------------------------------------------------------------------------
if ($Uninstall) {
    if ([Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($MenuKey)) {
        [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($MenuKey)
        Write-Ok 'The HyperACE right-click menu was removed.'
    }
    else {
        Write-Ok 'The HyperACE right-click menu was not installed; nothing to remove.'
    }
    exit 0
}

$Problems = 0

# ---------------------------------------------------------------------------
# 1. Python environment
# ---------------------------------------------------------------------------
Write-Step '[1/4] Checking the Python environment'

if (-not $PythonPath) {
    $PythonPath = Join-Path $ProjectRoot 'venv\Scripts\pythonw.exe'
}
$PythonPath = [System.IO.Path]::GetFullPath($PythonPath)
# pythonw.exe runs without a console window (used by the menu); python.exe in
# the same folder is used here so the checks can print their results.
$PythonConsole = Join-Path (Split-Path $PythonPath) 'python.exe'

if (-not (Test-Path -LiteralPath $PythonPath -PathType Leaf)) {
    Write-Fail "pythonw.exe was not found at: $PythonPath"
    Write-Hint 'Create the virtual environment first (README step 1):'
    Write-Hint '  py -3.11 -m venv venv'
    Write-Hint 'Or point to another environment with -PythonPath <path to pythonw.exe>.'
    exit 1
}
Write-Ok "Found $PythonPath"

if (-not (Test-Path -LiteralPath $PythonConsole -PathType Leaf)) {
    Write-Warn "python.exe was not found next to pythonw.exe; skipping the package and GPU checks."
    $Problems++
}
else {
    # Python snippets are piped through stdin because Windows PowerShell strips
    # double quotes from arguments passed to native programs.
    $Version = 'import sys; print("%d.%d" % sys.version_info[:2])' | & $PythonConsole -
    Write-Ok "Python $Version"

    # -----------------------------------------------------------------------
    # 2. Python packages
    # -----------------------------------------------------------------------
    Write-Step '[2/4] Checking the required Python packages'

    $Packages = [ordered]@{
        torch                  = 'torch'
        numpy                  = 'numpy'
        librosa                = 'librosa'
        soundfile              = 'SoundFile'
        yaml                   = 'PyYAML'
        einops                 = 'einops'
        beartype               = 'beartype'
        rotary_embedding_torch = 'rotary-embedding-torch'
    }
    $MissingPackages = @()
    foreach ($Module in $Packages.Keys) {
        # find_spec checks for the package without importing it and never writes
        # to stderr, which Windows PowerShell would otherwise treat as an error.
        & $PythonConsole -c "import importlib.util, sys; sys.exit(importlib.util.find_spec('$Module') is None)"
        if ($LASTEXITCODE -eq 0) {
            Write-Ok $Packages[$Module]
        }
        else {
            Write-Fail "$($Packages[$Module]) is not installed"
            $MissingPackages += $Packages[$Module]
        }
    }
    if ($MissingPackages) {
        $Problems++
        if ($MissingPackages -contains 'torch') {
            Write-Hint 'Install PyTorch first (README step 2), for example for an NVIDIA GPU:'
            Write-Hint "  & '$PythonConsole' -m pip install torch --index-url https://download.pytorch.org/whl/cu124"
        }
        Write-Hint 'Then install the rest:'
        Write-Hint "  & '$PythonConsole' -m pip install -r requirements.txt"
    }

    # -----------------------------------------------------------------------
    # 3. GPU
    # -----------------------------------------------------------------------
    Write-Step '[3/4] Checking for GPU acceleration'

    if ($MissingPackages -contains 'torch') {
        Write-Warn 'Skipped because PyTorch is not installed.'
    }
    else {
        $GpuCheck = @'
try:
    import torch
    print(torch.cuda.get_device_name(0) if torch.cuda.is_available() else "")
except Exception:
    print("")
'@
        $Gpu = $GpuCheck | & $PythonConsole -
        if ($Gpu) {
            Write-Ok "CUDA GPU detected: $Gpu"
        }
        else {
            Write-Warn 'No CUDA GPU is available to PyTorch; separation will run on the CPU (much slower).'
            Write-Hint 'If you have an NVIDIA GPU, reinstall PyTorch with the CUDA command from README step 2.'
        }
    }
}

# ---------------------------------------------------------------------------
# 4. Model checkpoints
# ---------------------------------------------------------------------------
Write-Step '[4/4] Checking the HyperACE model files'

$Fallback = Join-Path $ProjectRoot 'bs_hyperace.ckpt'
$HasFallback = Test-Path -LiteralPath $Fallback -PathType Leaf
$Models = @(
    @{ Name = 'Separate vocals';        Path = 'v2_voc\bs_roformer_voc_hyperacev2.ckpt' },
    @{ Name = 'Separate instrumentals'; Path = 'v2_inst\bs_roformer_inst_hyperacev2.ckpt' }
)
foreach ($Model in $Models) {
    if (Test-Path -LiteralPath (Join-Path $ProjectRoot $Model.Path) -PathType Leaf) {
        Write-Ok "$($Model.Path)  (used by `"$($Model.Name)`")"
    }
    elseif ($HasFallback) {
        Write-Warn "$($Model.Path) is missing; `"$($Model.Name)`" will use the older bs_hyperace.ckpt instead."
    }
    else {
        Write-Fail "$($Model.Path) is missing; `"$($Model.Name)`" will not work."
        $Problems++
    }
}
if ($Problems -and -not $HasFallback) {
    Write-Hint 'Download the checkpoints from https://huggingface.co/pcunwa/BS-Roformer-HyperACE/tree/main'
    Write-Hint 'and place them at the paths shown above (README step 3).'
}

# ---------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------
if ($Problems -and -not $Force) {
    Write-Host "`n$Problems problem(s) found. Fix them and run this installer again," -ForegroundColor Red
    Write-Host 'or add -Force to install the menu anyway.' -ForegroundColor Red
    exit 1
}

Write-Step 'Installing the right-click menu'

$Runner = Join-Path $ProjectRoot 'vocal_remover.pyw'
$Root = [Microsoft.Win32.Registry]::CurrentUser
# Start from a clean key so entries from older versions do not linger.
if ($Root.OpenSubKey($MenuKey)) {
    $Root.DeleteSubKeyTree($MenuKey)
}

$Menu = $Root.CreateSubKey($MenuKey)
$Menu.SetValue('MUIVerb', 'HyperACE')
$Menu.SetValue('AppliesTo', ($AudioExtensions -join ' OR '))
$Menu.SetValue('MultiSelectModel', 'Document')
# An empty SubCommands value tells Explorer to build a submenu from the "shell" subkey.
$Menu.SetValue('SubCommands', '')
$Menu.Close()

$Commands = [ordered]@{
    vocals        = @{ Label = 'Separate vocals';        Mode = 'vocals' }
    instrumentals = @{ Label = 'Separate instrumentals'; Mode = 'instrumental' }
}
foreach ($Name in $Commands.Keys) {
    $Entry = $Root.CreateSubKey("$MenuKey\shell\$Name")
    $Entry.SetValue('', $Commands[$Name].Label)
    $Entry.Close()

    $Command = $Root.CreateSubKey("$MenuKey\shell\$Name\command")
    $Command.SetValue('', "`"$PythonPath`" `"$Runner`" `"$($Commands[$Name].Mode)`" `"%1`"")
    $Command.Close()
    Write-Ok "Added `"$($Commands[$Name].Label)`""
}

Write-Host "`nDone! Right-click an audio file in Explorer and choose HyperACE." -ForegroundColor Green
Write-Hint 'On Windows 11, the menu is under "Show more options" (or press Shift+F10).'
Write-Hint 'If it does not appear, restart Explorer or sign out and back in.'
Write-Hint "Errors are written to $([System.IO.Path]::GetTempPath())hyperace_right_click.log"
Write-Hint 'If you move this folder, run this installer again.'
