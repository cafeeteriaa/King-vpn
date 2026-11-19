#!/usr/bin/env python3
"""Train a local QLoRA adapter; this creates a candidate, never deploys it."""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import torch
from datasets import load_dataset
from peft import LoraConfig
from transformers import (AutoModelForCausalLM, AutoTokenizer, BitsAndBytesConfig,
                          TrainingArguments)
from trl import SFTTrainer


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-model", required=True, help="Local, already-reviewed model directory")
    parser.add_argument("--dataset-dir", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--max-steps", type=int, default=500)
    args = parser.parse_args()
    if not torch.cuda.is_available():
        raise RuntimeError("A CUDA GPU is required; training is not run on the Android phone")
    if args.max_steps < 10 or args.max_steps > 5000:
        raise ValueError("--max-steps must be between 10 and 5000")

    base_path = Path(args.base_model).expanduser().resolve()
    if not base_path.is_dir() or not (base_path / "config.json").is_file():
        raise ValueError(
            "--base-model must be a local Hugging Face Transformers model directory "
            "containing config.json; GGUF files from the Android app cannot be QLoRA training inputs"
        )
    has_weights = any(base_path.glob("*.safetensors")) or any(base_path.glob("pytorch_model*.bin"))
    if not has_weights:
        raise ValueError("No safetensors or PyTorch model weights found in the base-model directory")

    tokenizer = AutoTokenizer.from_pretrained(str(base_path), local_files_only=True)
    if tokenizer.pad_token is None:
        tokenizer.pad_token = tokenizer.eos_token
    quant = BitsAndBytesConfig(
        load_in_4bit=True,
        bnb_4bit_quant_type="nf4",
        bnb_4bit_compute_dtype=torch.bfloat16 if torch.cuda.is_bf16_supported() else torch.float16,
        bnb_4bit_use_double_quant=True,
    )
    model = AutoModelForCausalLM.from_pretrained(
        str(base_path), quantization_config=quant, device_map="auto",
        local_files_only=True, trust_remote_code=False,
    )
    data = load_dataset("json", data_files={
        "train": str(args.dataset_dir / "train.jsonl"),
        "eval": str(args.dataset_dir / "eval.jsonl"),
    })
    lora = LoraConfig(
        r=16, lora_alpha=32, lora_dropout=0.05, bias="none",
        task_type="CAUSAL_LM",
        target_modules=["q_proj", "k_proj", "v_proj", "o_proj",
                        "gate_proj", "up_proj", "down_proj"],
    )
    training = TrainingArguments(
        output_dir=str(args.output_dir / "checkpoints"),
        max_steps=args.max_steps, per_device_train_batch_size=1,
        per_device_eval_batch_size=1, gradient_accumulation_steps=8,
        learning_rate=2e-4, warmup_ratio=0.05, logging_steps=10,
        evaluation_strategy="steps", eval_steps=50, save_steps=50,
        save_total_limit=2, gradient_checkpointing=True,
        fp16=not torch.cuda.is_bf16_supported(),
        bf16=torch.cuda.is_bf16_supported(), report_to="none",
        load_best_model_at_end=True, metric_for_best_model="eval_loss",
        greater_is_better=False,
    )
    trainer = SFTTrainer(
        model=model, tokenizer=tokenizer,
        train_dataset=data["train"], eval_dataset=data["eval"],
        dataset_text_field="text", max_seq_length=4096,
        peft_config=lora, args=training,
    )
    trainer.train()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    trainer.model.save_pretrained(args.output_dir / "adapter")
    tokenizer.save_pretrained(args.output_dir / "tokenizer")
    metrics = trainer.evaluate()
    report = {
        "status": "candidate_trained",
        "base_model": str(args.base_model),
        "eval_metrics": {key: float(value) for key, value in metrics.items()
                         if isinstance(value, (int, float))},
        "deployment_authorized": False,
        "note": "Adapter requires independent benchmark, security review, conversion and device validation.",
    }
    (args.output_dir / "training_report.json").write_text(
        json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
