# HyperACE Right-Click Vocal Separator

A lightweight Windows Explorer context-menu separator powered directly by
[BS-RoFormer HyperACE](https://huggingface.co/pcunwa/BS-Roformer-HyperACE).
It does not route audio through Ultimate Vocal Remover's MDX, VR, or Demucs
backends.

## What it does

- **Separate vocals** writes `file_name (vocals).wav`.
- **Separate instrumentals** writes `file_name (instrumentals).wav`.
- **Separate both** writes both files beside the original audio.
- Supports common audio formats that Librosa can decode, including MP3, WAV,
  FLAC, M4A, and OGG.

The context-menu entry point is [vocal_remover.pyw](vocal_remover.pyw). It
keeps simultaneous Explorer actions in a small local queue so only one GPU job
runs at a time.

## Setup

1. Create and activate a virtual environment with Python 3.10+.
2. Install a GPU-enabled PyTorch build for your system from
   [pytorch.org](https://pytorch.org/get-started/locally/), then run:

   ```powershell
   pip install -r requirements.txt
   ```

3. Download the model files from the upstream
   [BS-RoFormer HyperACE repository](https://huggingface.co/pcunwa/BS-Roformer-HyperACE/tree/main)
   and keep the model pairs together:

   - `v2_voc/bs_roformer_voc_hyperacev2.ckpt` with `v2_voc/config.yaml`
   - `v2_inst/bs_roformer_inst_hyperacev2.ckpt` with `v2_inst/config.yaml`

The runner automatically selects the v2 vocal or instrumental checkpoint for
the matching action. It falls back to the root v1 model if a v2 pair is absent.
The checkpoints are intentionally not included in this GitHub fork because
they exceed the fork's Git LFS upload allowance.

## Performance

The runner uses mixed precision on CUDA and a 12-second default chunk on 8 GB
GPUs, reducing overlap-add overhead compared with the prior 8-second setting.
Set `HYPERACE_CHUNK_SECONDS` to tune for your available VRAM; use a smaller
value if CUDA runs out of memory.

## Credits and license

This project packages integration code around the model implementation and
weights from [pcunwa/BS-Roformer-HyperACE](https://huggingface.co/pcunwa/BS-Roformer-HyperACE).
Please follow the upstream repository's license, model terms, and attribution
requirements when redistributing or using the weights.

The HyperACE model credits [anvuew/BS-RoFormer](https://huggingface.co/anvuew/BS-RoFormer)
as its base. Its `SegmModel` includes components based on the paper
["Hypergraph-Based High-Order Representation Learning"](https://arxiv.org/abs/2506.17733).
