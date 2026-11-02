# HyperACE Right-Click Vocal Separator

Fast, local vocal and instrumental separation from the Windows Explorer
right-click menu, powered directly by
[BS-RoFormer HyperACE](https://huggingface.co/pcunwa/BS-Roformer-HyperACE).

This repository contains only the HyperACE runner and its required Python
architecture/configuration files. It no longer uses Ultimate Vocal Remover,
Demucs, MDX-Net, or VR models.

## Output

Right-click a supported audio file and choose **HyperACE**:

- **Separate vocals** creates `file_name (vocals).wav`.
- **Separate instrumentals** creates `file_name (instrumentals).wav`.

The source audio remains unchanged. Output is stereo 44.1 kHz PCM WAV and is
written next to the source file.

## Requirements

- Windows 10 or later
- Python 3.10–3.13 (64-bit)
- NVIDIA GPU recommended; CPU inference works but is considerably slower
- 8 GB of GPU VRAM recommended for the included v2 models

## Setup

Run these commands in PowerShell from the cloned repository directory.

### 1. Create the virtual environment

```powershell
py -3.11 -m venv venv
.\venv\Scripts\python.exe -m pip install --upgrade pip
```

If Python 3.11 is not installed, replace `-3.11` with an available supported
version, for example `-3.12`.

### 2. Install PyTorch and the application dependencies

For an NVIDIA GPU, select the command for your CUDA version on
[PyTorch's installation page](https://pytorch.org/get-started/locally/). For
example, a CUDA 12.4 installation is:

```powershell
.\venv\Scripts\python.exe -m pip install torch --index-url https://download.pytorch.org/whl/cu124
```

Then install the remaining dependencies:

```powershell
.\venv\Scripts\python.exe -m pip install -r requirements.txt
```

For CPU-only use, omit the CUDA index URL when installing `torch`.

### 3. Download the HyperACE model weights

The checkpoints are not committed to this fork because GitHub does not allow
new LFS uploads to public forks. Download them from the upstream
[BS-RoFormer HyperACE file list](https://huggingface.co/pcunwa/BS-Roformer-HyperACE/tree/main).

Download these two files and put them in these exact locations:

| Download from upstream | Place in this repository |
| --- | --- |
| `v2_voc/bs_roformer_voc_hyperacev2.ckpt` | `v2_voc/bs_roformer_voc_hyperacev2.ckpt` |
| `v2_inst/bs_roformer_inst_hyperacev2.ckpt` | `v2_inst/bs_roformer_inst_hyperacev2.ckpt` |

The `v2_voc` and `v2_inst` folders already include the matching
`bs_roformer.py` and `config.yaml`; do not replace those files with a different
model version. The first model is used for **Separate vocals** and the second
for **Separate instrumentals**.

Optional fallback: download the root `bs_hyperace.ckpt` from upstream and place
it at `bs_hyperace.ckpt`. It is used only when a v2 checkpoint is unavailable.

### 4. Install the Explorer context menu

Run the installer from the repository root:

```powershell
PowerShell -ExecutionPolicy Bypass -File .\install_context_menu.ps1
```

It validates the local `venv\Scripts\pythonw.exe`, substitutes your checkout's
absolute path into [a.reg](a.reg), and installs the menu under your current
Windows user account—no Administrator access is needed. Restart Explorer or
sign out/in if the **HyperACE** menu does not appear immediately.

To use a Python environment somewhere else:

```powershell
PowerShell -ExecutionPolicy Bypass -File .\install_context_menu.ps1 -PythonPath 'D:\PythonEnvs\hyperace\Scripts\pythonw.exe'
```

To remove the context menu:

```powershell
PowerShell -ExecutionPolicy Bypass -File .\install_context_menu.ps1 -Uninstall
```

## Performance tuning

The runner uses CUDA mixed precision and defaults to 12-second chunks on CUDA.
This is tuned for approximately 8 GB VRAM. Set `HYPERACE_CHUNK_SECONDS` before
launching Explorer to override it; use a smaller value for out-of-memory errors
and a larger one only if your GPU has sufficient VRAM.

## Credits

The model implementation and weights are from
[pcunwa/BS-Roformer-HyperACE](https://huggingface.co/pcunwa/BS-Roformer-HyperACE).
Follow the upstream repository's license, model terms, and attribution
requirements when using or redistributing the weights.

HyperACE credits [anvuew/BS-RoFormer](https://huggingface.co/anvuew/BS-RoFormer)
as its base. Its `SegmModel` includes components based on
["Hypergraph-Based High-Order Representation Learning"](https://arxiv.org/abs/2506.17733).
