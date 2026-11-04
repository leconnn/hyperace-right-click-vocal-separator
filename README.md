# HyperACE Right-Click Vocal Separator

Split any song into vocals or instrumentals by right-clicking it in Windows
Explorer. Everything runs locally on your PC using the
[BS-RoFormer HyperACE](https://huggingface.co/pcunwa/BS-Roformer-HyperACE)
AI models.

## How it works

1. Right-click an audio file (or several) in Explorer.
2. Choose **HyperACE**, then **Separate vocals** or **Separate instrumentals**.
   On Windows 11, click **Show more options** first (or press **Shift+F10**).
3. A small progress window appears. When it closes, the result is saved next to
   the original file:

| Menu option | Output file |
| --- | --- |
| Separate vocals | `song (vocals).wav` |
| Separate instrumentals | `song (instrumentals).wav` |

Your original file is never changed. Output is 16-bit, 44.1 kHz stereo WAV.

Supported formats: `.wav` `.mp3` `.flac` `.m4a` `.aac` `.ogg` `.opus` `.wma`
`.aiff` `.alac` `.ape` `.tta` `.amr` `.au` `.ra` `.mp1` `.mp2`

If you select several files, they are processed one after another in the same
window.

## What you need

- Windows 10 or 11
- [Python](https://www.python.org/downloads/windows/) 3.10 to 3.13 (64-bit)
- About 6 GB of free disk space for PyTorch and the models
- An NVIDIA graphics card with 8 GB of memory is recommended. Without one the
  separator still works on the CPU, but a song can take several minutes.

## Installation

Open **PowerShell** in the folder where you downloaded or cloned this
repository, then follow these four steps.

> Tip: in File Explorer, open the folder, click the address bar, type
> `powershell` and press Enter to open PowerShell in that folder.

### Step 1: Create a Python environment

This keeps the separator's packages separate from anything else on your PC.

```powershell
py -3.11 -m venv venv
.\venv\Scripts\python.exe -m pip install --upgrade pip
```

If you have a different Python version installed, change `-3.11` to match it
(for example `-3.12`). Run `py --list` to see which versions you have.

### Step 2: Install PyTorch and the other packages

**With an NVIDIA graphics card** (recommended), install the CUDA build of
PyTorch:

```powershell
.\venv\Scripts\python.exe -m pip install torch --index-url https://download.pytorch.org/whl/cu124
```

If that doesn't work with your card or driver, pick the right command for
your setup on [PyTorch's install page](https://pytorch.org/get-started/locally/).

**Without an NVIDIA graphics card**, install the regular build instead:

```powershell
.\venv\Scripts\python.exe -m pip install torch
```

Then install the remaining packages:

```powershell
.\venv\Scripts\python.exe -m pip install -r requirements.txt
```

### Step 3: Download the AI models

The model files are too large for GitHub, so download them from
[the HyperACE model page](https://huggingface.co/pcunwa/BS-Roformer-HyperACE/tree/main)
and save them in these exact locations inside this folder:

| File on the model page | Save it as |
| --- | --- |
| `v2_voc/bs_roformer_voc_hyperacev2.ckpt` | `v2_voc\bs_roformer_voc_hyperacev2.ckpt` |
| `v2_inst/bs_roformer_inst_hyperacev2.ckpt` | `v2_inst\bs_roformer_inst_hyperacev2.ckpt` |

The `v2_voc` and `v2_inst` folders already contain the matching
`bs_roformer.py` and `config.yaml`. Don't replace them with files from a
different model version.

*Optional:* the older `bs_hyperace.ckpt` from the root of the model page can be
saved in this folder as a backup. It is only used when one of the v2 models
above is missing.

### Step 4: Add the right-click menu

```powershell
PowerShell -ExecutionPolicy Bypass -File .\install_context_menu.ps1
```

The installer checks each of the steps above, tells you exactly what to fix if
something is missing, and then adds the **HyperACE** menu. It only changes
settings for your own Windows account, so you don't need to run it as
Administrator.

If the menu doesn't appear right away, restart Explorer or sign out and back
in.

**Important:** the menu points to this folder. If you move or rename the
folder, create the Python environment again (step 1 and 2) and rerun the
installer.

## Uninstalling

Remove the right-click menu:

```powershell
PowerShell -ExecutionPolicy Bypass -File .\install_context_menu.ps1 -Uninstall
```

Then delete this folder.

## Installer options

| Option | What it does |
| --- | --- |
| `-Uninstall` | Removes the right-click menu. |
| `-PythonPath <path>` | Uses a different Python environment, e.g. `-PythonPath 'D:\envs\hyperace\Scripts\pythonw.exe'`. |
| `-Force` | Installs the menu even if some checks fail. |

## Troubleshooting

**Nothing happens when I click the menu.**
Check the log file at `%TEMP%\hyperace_right_click.log` (paste that into the
Explorer address bar). Rerunning the installer also checks for common
problems.

**"CUDA out of memory" in the log.**
Your graphics card ran out of memory. The separator processes audio in
12-second pieces by default; make them smaller by setting an environment
variable, then restart Explorer (or sign out and back in):

```powershell
setx HYPERACE_CHUNK_SECONDS 8
```

The minimum is 4 seconds. If you have plenty of graphics memory, a larger
value can be a little faster. To go back to the default, remove the variable
from **Edit environment variables for your account** in the Start menu.

**It's very slow.**
Rerun the installer and look at the GPU check. If it says no CUDA GPU was
found but you have an NVIDIA card, reinstall PyTorch with the CUDA command in
step 2.

## Files in this repository

| File | Purpose |
| --- | --- |
| `vocal_remover.pyw` | Runs when you click the menu; shows the progress window. |
| `hyperace_separator.py` | Loads the model and separates the audio. |
| `bs_roformer.py`, `hyperace_attend.py` | The HyperACE model architecture. |
| `v2_voc\`, `v2_inst\` | Architecture and settings for the v2 vocal and instrumental models. |
| `config.yaml` | Settings for the optional older model. |
| `install_context_menu.ps1` | Adds or removes the right-click menu. |

## Credits

The model architecture and weights are from
[pcunwa/BS-Roformer-HyperACE](https://huggingface.co/pcunwa/BS-Roformer-HyperACE).
Follow that repository's license, model terms, and attribution requirements
when using or redistributing the weights.

HyperACE credits [anvuew/BS-RoFormer](https://huggingface.co/anvuew/BS-RoFormer)
as its base. Its `SegmModel` includes components based on
["Hypergraph-Based High-Order Representation Learning"](https://arxiv.org/abs/2506.17733).
