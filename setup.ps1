<#
.SYNOPSIS
    Installs everything HyperACE needs and adds the right-click menu, in one go.

.DESCRIPTION
    Runs the whole installation from the README automatically:

      1. Finds a supported Python (3.10 to 3.13, 64-bit), or offers to install
         Python 3.12 with winget if none is found
      2. Creates the Python environment in the "venv" folder
      3. Installs PyTorch (GPU build if an NVIDIA card is found, otherwise CPU)
         and the other required packages
      4. Downloads the HyperACE v2 model files (about 550 MB)
      5. Adds the right-click menu by running install_context_menu.ps1

    Steps that are already done are skipped, so it is safe to run again, for
    example to repair an installation or after moving this folder.

.PARAMETER Cpu
    Installs the CPU build of PyTorch even if an NVIDIA graphics card is found.

.PARAMETER Yes
    Doesn't ask for confirmation before installing Python with winget.

.EXAMPLE
    PowerShell -ExecutionPolicy Bypass -File .\setup.ps1
#>
[CmdletBinding()]
param(
    [switch]$Cpu,
    [switch]$Yes
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = $PSScriptRoot
$VenvPython = Join-Path $ProjectRoot 'venv\Scripts\python.exe'
$SupportedPythons = '3.12', '3.11', '3.13', '3.10'   # in order of preference
$ModelBaseUrl = 'https://huggingface.co/pcunwa/BS-Roformer-HyperACE/resolve/main'
$Models = 'v2_voc/bs_roformer_voc_hyperacev2.ckpt', 'v2_inst/bs_roformer_inst_hyperacev2.ckpt'

function Write-Step([string]$Text) { Write-Host "`n$Text" -ForegroundColor Cyan }
function Write-Ok([string]$Text) { Write-Host "  [OK]   $Text" -ForegroundColor Green }
function Write-Info([string]$Text) { Write-Host "         $Text" -ForegroundColor Gray }
function Stop-Setup([string]$Text) {
    Write-Host "`n  [FAIL] $Text" -ForegroundColor Red
    exit 1
}

# Runs a native program and stops the setup if it fails.
function Invoke-Checked([string]$FailureMessage, [scriptblock]$Command) {
    & $Command
    if ($LASTEXITCODE -ne 0) { Stop-Setup "$FailureMessage (exit code $LASTEXITCODE)." }
}

# Returns "3.12" etc. for a python.exe, or $null if it can't be run.
function Get-PythonVersion([string]$Python) {
    if (-not (Test-Path -LiteralPath $Python -PathType Leaf)) { return $null }
    # Piped through stdin because Windows PowerShell strips double quotes from
    # arguments passed to native programs.
    $Version = 'import sys, struct; print("%d.%d" % sys.version_info[:2] if struct.calcsize("P") == 8 else "32-bit")' | & $Python -
    if ($LASTEXITCODE -eq 0) { return "$Version".Trim() }
    return $null
}

# Finds a supported 64-bit python.exe through the py launcher or the default
# per-user install folders.
function Find-Python {
    # The py launcher writes to stderr for versions that aren't installed;
    # don't let that stop the setup.
    $ErrorActionPreference = 'Continue'
    $Launcher = Get-Command py.exe -ErrorAction SilentlyContinue
    foreach ($Version in $SupportedPythons) {
        $Candidates = @(Join-Path $env:LOCALAPPDATA "Programs\Python\Python$($Version.Replace('.', ''))\python.exe")
        if ($Launcher) {
            $FromLauncher = & $Launcher.Source "-$Version" -c 'import sys; print(sys.executable)' 2>$null
            if ($LASTEXITCODE -eq 0 -and $FromLauncher) { $Candidates = @("$FromLauncher".Trim()) + $Candidates }
        }
        foreach ($Candidate in $Candidates) {
            if ((Get-PythonVersion $Candidate) -eq $Version) { return $Candidate }
        }
    }
    return $null
}

Write-Host 'HyperACE Right-Click Vocal Separator - automatic setup' -ForegroundColor White
Write-Host "Folder: $ProjectRoot"

# ---------------------------------------------------------------------------
# 1. Python
# ---------------------------------------------------------------------------
Write-Step '[1/5] Finding Python'

$ExistingVenv = Get-PythonVersion $VenvPython
if ($ExistingVenv -and $SupportedPythons -contains $ExistingVenv) {
    Write-Ok "The venv folder already uses Python $ExistingVenv."
    Write-Step '[2/5] Creating the Python environment'
    Write-Ok 'Already exists; skipping.'
}
else {
    if ($ExistingVenv -or (Test-Path -LiteralPath (Join-Path $ProjectRoot 'venv'))) {
        Write-Info "The existing venv folder uses an unsupported or broken Python; it will be recreated."
    }

    $BasePython = Find-Python
    if (-not $BasePython) {
        Write-Info 'No supported Python (3.10 to 3.13, 64-bit) was found.'
        if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
            Stop-Setup 'Install Python 3.12 from https://www.python.org/downloads/windows/ and run this setup again.'
        }
        if (-not $Yes) {
            $Answer = Read-Host '         Install Python 3.12 for your account with winget now? [Y/n]'
            if ($Answer -and $Answer -notmatch '^(y|yes)$') {
                Stop-Setup 'Python is required. Install Python 3.12 from https://www.python.org/downloads/windows/ and run this setup again.'
            }
        }
        Invoke-Checked 'winget could not install Python' {
            winget install --exact --id Python.Python.3.12 --scope user --accept-package-agreements --accept-source-agreements
        }
        # Pick up the PATH changes made by the Python installer.
        $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
        $BasePython = Find-Python
        if (-not $BasePython) { Stop-Setup 'Python was installed but could not be found. Close this window and run the setup again.' }
    }
    Write-Ok "Found Python $(Get-PythonVersion $BasePython) at $BasePython"

    # -----------------------------------------------------------------------
    # 2. Virtual environment
    # -----------------------------------------------------------------------
    Write-Step '[2/5] Creating the Python environment'
    $VenvFolder = Join-Path $ProjectRoot 'venv'
    if (Test-Path -LiteralPath $VenvFolder) { Remove-Item -LiteralPath $VenvFolder -Recurse -Force }
    Invoke-Checked 'Could not create the Python environment' { & $BasePython -m venv $VenvFolder }
    Write-Ok 'Created the venv folder.'
}

# ---------------------------------------------------------------------------
# 3. Packages
# ---------------------------------------------------------------------------
Write-Step '[3/5] Installing PyTorch and the other packages (this can take a while)'

Invoke-Checked 'Could not update pip' { & $VenvPython -m pip install --upgrade pip --quiet --disable-pip-version-check }

# Choose the PyTorch build. cu124 supports GTX 900 through RTX 40 cards;
# RTX 50 cards (compute capability 12) need the newer cu128 build.
$TorchIndex = 'https://download.pytorch.org/whl/cpu'
$WantCuda = $false
$NvidiaSmi = Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue
if ($Cpu) {
    Write-Info 'Using the CPU build of PyTorch (-Cpu was given).'
}
elseif (-not $NvidiaSmi) {
    Write-Info 'No NVIDIA graphics card found; using the CPU build of PyTorch (slower).'
}
else {
    # Older drivers don't know compute_cap; that just selects the cu124 build.
    $GpuInfo = & {
        $ErrorActionPreference = 'Continue'
        & $NvidiaSmi.Source --query-gpu=name,compute_cap --format=csv,noheader 2>$null | Select-Object -First 1
    }
    $GpuName, $ComputeCap = "$GpuInfo".Split(',') | ForEach-Object { $_.Trim() }
    $Capability = 0.0
    [void][double]::TryParse($ComputeCap, [System.Globalization.NumberStyles]::Float,
                             [System.Globalization.CultureInfo]::InvariantCulture, [ref]$Capability)
    if ($Capability -ge 10) {
        $TorchIndex = 'https://download.pytorch.org/whl/cu128'
    }
    else {
        $TorchIndex = 'https://download.pytorch.org/whl/cu124'
    }
    $WantCuda = $true
    Write-Info "NVIDIA graphics card found: $(if ($GpuName) { $GpuName } else { 'unknown model' }); using the GPU build of PyTorch."
}

$TorchState = @'
try:
    import torch
    print("cuda" if torch.cuda.is_available() else "cpu")
except Exception:
    print("missing")
'@ | & $VenvPython -
$TorchState = "$TorchState".Trim()

if ($TorchState -eq 'missing') {
    Write-Info 'Downloading PyTorch (about 2.5 GB for the GPU build)...'
    Invoke-Checked 'Could not install PyTorch' { & $VenvPython -m pip install torch --index-url $TorchIndex --disable-pip-version-check }
}
elseif ($WantCuda -and $TorchState -ne 'cuda') {
    Write-Info 'PyTorch is installed without GPU support; replacing it with the GPU build...'
    Invoke-Checked 'Could not install PyTorch' { & $VenvPython -m pip install torch --index-url $TorchIndex --force-reinstall --disable-pip-version-check }
}
else {
    Write-Ok "PyTorch is already installed ($TorchState build)."
}

Invoke-Checked 'Could not install the required packages' {
    & $VenvPython -m pip install -r (Join-Path $ProjectRoot 'requirements.txt') --quiet --disable-pip-version-check
}
Write-Ok 'All packages are installed.'

# ---------------------------------------------------------------------------
# 4. Models
# ---------------------------------------------------------------------------
Write-Step '[4/5] Downloading the HyperACE models'

foreach ($Model in $Models) {
    $Target = Join-Path $ProjectRoot ($Model.Replace('/', '\'))
    if (Test-Path -LiteralPath $Target -PathType Leaf) {
        Write-Ok "$Model is already downloaded."
        continue
    }
    Write-Info "Downloading $Model (about 275 MB)..."
    # Download to a temporary name so an interrupted download is never mistaken
    # for a finished model; curl resumes a partial .part file on the next run.
    $Partial = "$Target.part"
    Invoke-Checked "Could not download $Model" {
        curl.exe --location --fail --retry 3 --continue-at - --progress-bar --output $Partial "$ModelBaseUrl/$Model"
    }
    Move-Item -LiteralPath $Partial -Destination $Target -Force
    Write-Ok "Downloaded $Model."
}

# ---------------------------------------------------------------------------
# 5. Right-click menu
# ---------------------------------------------------------------------------
Write-Step '[5/5] Adding the right-click menu'
& (Join-Path $ProjectRoot 'install_context_menu.ps1')
exit $LASTEXITCODE
