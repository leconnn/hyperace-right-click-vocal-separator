"""Native inference backend for the bundled BS-Roformer HyperACE checkpoints."""

from __future__ import annotations

import gc
import importlib.util
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

import librosa
import numpy as np
import soundfile as sf
import torch
import yaml


PROJECT_ROOT = Path(__file__).resolve().parent
SAMPLE_RATE = 44_100


@dataclass(frozen=True)
class HyperACEModel:
    checkpoint: Path
    config: Path
    target: str
    name: str


def _checkpoint_for(directory: Path) -> Path | None:
    """Return a checkpoint next to a config, accepting common HF filenames."""
    for name in ("bs_hyperace.ckpt", "model.ckpt", "model.pth", "model.pt"):
        candidate = directory / name
        if candidate.is_file():
            return candidate
    checkpoints = sorted((*directory.glob("*.ckpt"), *directory.glob("*.pth"), *directory.glob("*.pt")))
    return checkpoints[0] if checkpoints else None


def find_model(mode: str) -> HyperACEModel:
    """Pick a mode-specific v2 checkpoint when present, otherwise use v1.

    An instrumental model also yields vocals reliably as ``mix -
    instrumental``.  If a matching v2 checkpoint is present beside either v2
    config, it is selected automatically for the corresponding context-menu
    mode; the root checkpoint is a backwards-compatible fallback.
    """
    choices: list[tuple[Path, str]] = []
    if mode == "vocals":
        choices.append((PROJECT_ROOT / "v2_voc", "HyperACE v2 Vocals"))
    elif mode == "instrumental":
        choices.append((PROJECT_ROOT / "v2_inst", "HyperACE v2 Instrumental"))
    else:
        choices.append((PROJECT_ROOT / "v2_inst", "HyperACE v2 Instrumental"))
    choices.append((PROJECT_ROOT, "HyperACE"))

    for directory, name in choices:
        checkpoint = _checkpoint_for(directory)
        config = directory / "config.yaml"
        if checkpoint and config.is_file():
            with config.open(encoding="utf-8") as stream:
                target = yaml.load(stream, Loader=yaml.FullLoader)["training"]["target_instrument"]
            return HyperACEModel(checkpoint, config, target, name)

    raise FileNotFoundError(
        "HyperACE checkpoint/config pair not found. Expected bs_hyperace.ckpt "
        "and config.yaml in the application directory."
    )


def _device() -> torch.device:
    return torch.device("cuda" if torch.cuda.is_available() else "cpu")


def _load_network(spec: HyperACEModel, device: torch.device):
    # Imported lazily so the small progress window appears before PyTorch loads.
    source_path = spec.config.with_name("bs_roformer.py")
    if source_path.resolve() == (PROJECT_ROOT / "bs_roformer.py").resolve():
        from bs_roformer import BSRoformer
    else:
        module_spec = importlib.util.spec_from_file_location(
            f"hyperace_{spec.name.lower().replace(' ', '_')}", source_path
        )
        if module_spec is None or module_spec.loader is None:
            raise ImportError(f"Cannot load HyperACE architecture: {source_path}")
        module = importlib.util.module_from_spec(module_spec)
        module_spec.loader.exec_module(module)
        BSRoformer = module.BSRoformer

    with spec.config.open(encoding="utf-8") as stream:
        model_args = yaml.load(stream, Loader=yaml.FullLoader)["model"]
    # Checkpointing is only useful during training and slows inference.
    model_args["use_torch_checkpoint"] = False
    model = BSRoformer(**model_args)

    state = torch.load(spec.checkpoint, map_location="cpu", weights_only=True)
    if isinstance(state, dict) and "state_dict" in state:
        state = state["state_dict"]
    model.load_state_dict(state, strict=True)
    return model.to(device).eval()


def _chunk_samples(device: torch.device) -> int:
    """Use a conservative default for common 8 GB GPUs; permit an override."""
    configured = os.environ.get("HYPERACE_CHUNK_SECONDS")
    if configured:
        try:
            return int(max(4, float(configured)) * SAMPLE_RATE)
        except ValueError:
            pass

    # Time attention grows quickly with longer chunks. Twelve seconds uses
    # less than half of the 8 GB GTX 1080's VRAM while cutting the number of
    # overlap-add passes by about a third versus the former 8-second default.
    return 12 * SAMPLE_RATE if device.type == "cuda" else 4 * SAMPLE_RATE


def _overlap_add(model, audio: np.ndarray, device: torch.device, progress: Callable[[str], None] | None) -> np.ndarray:
    chunk_size = int(_chunk_samples(device))
    overlap = chunk_size // 4
    stride = chunk_size - overlap
    total_samples = audio.shape[1]
    starts = [0]
    while starts[-1] + chunk_size < total_samples:
        starts.append(starts[-1] + stride)
    if starts[-1] + chunk_size < total_samples or (total_samples > chunk_size and starts[-1] != total_samples - chunk_size):
        starts.append(max(0, total_samples - chunk_size))
    starts = list(dict.fromkeys(starts))

    output = np.zeros_like(audio, dtype=np.float32)
    weights = np.zeros(total_samples, dtype=np.float32)
    amp_enabled = device.type == "cuda"

    for index, start in enumerate(starts, start=1):
        end = min(start + chunk_size, total_samples)
        valid = end - start
        piece = audio[:, start:end]
        if valid < chunk_size:
            piece = np.pad(piece, ((0, 0), (0, chunk_size - valid)))

        if progress:
            progress(f"Separating chunk {index}/{len(starts)}…")
        tensor = torch.from_numpy(piece).unsqueeze(0).to(device)
        with torch.inference_mode(), torch.autocast(device_type=device.type, enabled=amp_enabled):
            predicted = model(tensor).squeeze(0).float().cpu().numpy()[:, :valid]

        # Cross-fade only at joins. The first and final real samples retain a
        # weight of one, avoiding an artificial fade at the song boundaries.
        window = np.ones(valid, dtype=np.float32)
        fade = min(overlap, valid)
        if start:
            window[:fade] = np.linspace(0.0, 1.0, fade, dtype=np.float32)
        if end < total_samples:
            window[-fade:] = np.minimum(window[-fade:], np.linspace(1.0, 0.0, fade, dtype=np.float32))
        output[:, start:end] += predicted * window
        weights[start:end] += window

    return output / np.maximum(weights, 1e-8)


def separate_file(path: str | os.PathLike[str], mode: str = "both", progress: Callable[[str], None] | None = None) -> list[Path]:
    """Separate one audio file and return the generated WAV paths."""
    input_path = Path(path)
    spec = find_model(mode)
    if progress:
        progress(f"Loading {spec.name}…")

    audio, _ = librosa.load(input_path, sr=SAMPLE_RATE, mono=False)
    if audio.ndim == 1:
        audio = np.stack((audio, audio))
    audio = np.asarray(audio[:2], dtype=np.float32)

    device = _device()
    model = _load_network(spec, device)
    try:
        target = _overlap_add(model, audio, device, progress)
    finally:
        del model
        gc.collect()
        if device.type == "cuda":
            torch.cuda.empty_cache()

    # The repository's shipped checkpoint predicts the configured target.
    target_name = spec.target.lower()
    vocals = target if target_name == "vocals" else audio - target
    instrumental = target if target_name in {"instrument", "instrumental"} else audio - target

    selections = {
        "vocals": (("Vocals", vocals),),
        "instrumental": (("Instrumentals", instrumental),),
        "both": (("Vocals", vocals), ("Instrumentals", instrumental)),
    }[mode]
    outputs: list[Path] = []
    for label, stem in selections:
        output = input_path.with_name(f"{input_path.stem} ({label.lower()}).wav")
        sf.write(output, np.clip(stem.T, -1.0, 1.0), SAMPLE_RATE, subtype="PCM_16")
        outputs.append(output)
    return outputs
