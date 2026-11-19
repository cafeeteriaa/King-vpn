# King AI local-model training pipeline

This pipeline turns only merged, CI-green repairs that pass a dedicated secret scan into a
small supervised fine-tuning dataset and trains a QLoRA adapter on a dedicated
GPU runner. It uses no paid AI API, Gemini, Grok, or hosted inference endpoint.

## Accepted-example format

One JSON object per line in the input JSONL:

- `task`: the repair task without private user data.
- `source_files`: map of repository paths to complete pre-repair source contents.
- `changes`: map of those same paths to complete accepted replacement contents.
- `ci_passed`: boolean, must be true.
- `human_reviewed`: boolean, or `merged`: boolean set only after GitHub confirms the PR was merged.
- `secret_scan_passed`: boolean, set only after the collector's secret-pattern scan passes. This is not a substitute for a full code security audit.

The merged-repair collector obtains the pre-merge source from the merge commit's first parent and the accepted replacement from the merged head. The preparation step removes malformed, duplicate, unreviewed/unmerged, failed, and secret-bearing examples. It creates ChatML samples aligned with the app's JSON full-file repair contract and a deterministic train/evaluation split.
At least five trusted examples are required.

## Run

```bash
python3 tools/king_ai_training/prepare_dataset.py \
  --input data/king_ai_accepted_repairs.jsonl \
  --output-dir build/king-ai-dataset

python3 -m pip install -r tools/king_ai_training/requirements.txt

python3 tools/king_ai_training/train_lora.py \
  --base-model /models/Qwen2.5-Coder-1.5B-Instruct \
  --dataset-dir build/king-ai-dataset \
  --output-dir build/king-ai-adapter
```

Training requires a CUDA GPU and a locally available, reviewed base model.
The base model must be a full Hugging Face Transformers checkpoint (`config.json` plus model weights), not the 1.1 GB GGUF file installed by the Android app. The Android device remains an inference target, not a training machine. The runner preflight requires an NVIDIA CUDA GPU with at least 10 GiB free VRAM and 12 GiB free disk space.

## Automatic training setup

- Register a trusted self-hosted GitHub Actions runner with labels: `self-hosted`, `linux`, `x64`, `gpu`, and `king-ai-training`.
- Set the repository Actions variable `KING_AI_BASE_MODEL_PATH` to the runner-local directory containing the reviewed Transformers checkpoint.
- After five accepted examples exist, the dataset collector dispatches training automatically when it can push the dataset to `main`. If repository policy requires a dataset PR, merge that data-only PR; the main-branch dataset update then triggers training.
- The workflow can also be started manually from Actions using a local checkpoint path and bounded step count.

Without that runner and repository variable, collection still works but GPU training remains queued/skipped; it is not silently run on the Android phone.

## Release safety

The workflow produces a candidate adapter artifact only. It does not publish,
replace, or download a model into the app. Before deployment, the adapter must
pass a held-out code-repair benchmark, security review, format conversion,
SHA-256/signature verification, Android memory/performance checks, and a
rollback test. A lower training loss alone is not proof of better repairs.
