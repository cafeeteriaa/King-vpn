#!/usr/bin/env python3
"""Fail-fast validation for the isolated local QLoRA runner."""
from __future__ import annotations

import argparse
import json
import shutil
from pathlib import Path


def validate(base_model: Path, dataset: Path) -> dict:
    base_model = base_model.expanduser().resolve()
    dataset = dataset.expanduser().resolve()
    if not base_model.is_dir():
        raise RuntimeError(f"Base model directory does not exist: {base_model}")
    if not (base_model / "config.json").is_file():
        raise RuntimeError("Base model must be a Hugging Face Transformers directory containing config.json; GGUF is not supported")
    if not any(base_model.rglob("*.safetensors")) and not any(base_model.rglob("pytorch_model*.bin")):
        raise RuntimeError("No local safetensors or PyTorch model weights were found")
    if not dataset.is_file() or dataset.suffix.lower() != ".jsonl":
        raise RuntimeError("Training dataset must be an existing JSONL file")
    train = dataset.parent / "train.jsonl"
    evaluation = dataset.parent / "eval.jsonl"
    if not train.is_file() or not evaluation.is_file():
        raise RuntimeError("Prepared train.jsonl and eval.jsonl splits are missing; run prepare_dataset.py first")

    try:
        import torch
    except ImportError as error:
        raise RuntimeError("PyTorch is not installed on the training runner") from error
    if not torch.cuda.is_available():
        raise RuntimeError("No CUDA GPU is available to PyTorch; QLoRA training requires a trusted NVIDIA GPU runner")
    if not torch.cuda.is_bf16_supported():
        precision = "fp16"
    else:
        precision = "bf16"
    device = torch.cuda.get_device_properties(0)
    free_bytes, total_bytes = torch.cuda.mem_get_info(0)
    free_gib = round(free_bytes / (1024 ** 3), 2)
    total_gib = round(total_bytes / (1024 ** 3), 2)
    disk = shutil.disk_usage(dataset.parent)
    return {
        "status": "ready",
        "gpu": device.name,
        "cuda": torch.version.cuda,
        "precision": precision,
        "vram_free_gib": free_gib,
        "vram_total_gib": total_gib,
        "dataset_examples": sum(1 for line in dataset.open(encoding="utf-8") if line.strip()),
        "free_disk_gib": round(disk.free / (1024 ** 3), 2),
        "base_model": str(base_model),
        "training_dataset": str(dataset),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-model", required=True, type=Path)
    parser.add_argument("--dataset", required=True, type=Path)
    args = parser.parse_args()
    print(json.dumps(validate(args.base_model, args.dataset), indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError) as error:
        print(f"Training runner preflight failed: {error}")
        raise SystemExit(1)
