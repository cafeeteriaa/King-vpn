# King AI local-model training pipeline

This pipeline turns only reviewed, security-scanned, CI-green repairs into a
small supervised fine-tuning dataset and trains a QLoRA adapter on a dedicated
GPU runner. It uses no paid AI API, Gemini, Grok, or hosted inference endpoint.

## Accepted-example format

One JSON object per line in the input JSONL:

- `task`: the repair task without private user data.
- `diff`: the accepted unified diff.
- `ci_passed`: boolean, must be true.
- `human_reviewed`: boolean, must be true.
- `security_scan_passed`: boolean, must be true.

The preparation step removes malformed, duplicate, unreviewed, failed, and
secret-bearing examples. It creates a deterministic train/evaluation split.
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
The Android device remains an inference target, not a training machine.

## Release safety

The workflow produces a candidate adapter artifact only. It does not publish,
replace, or download a model into the app. Before deployment, the adapter must
pass a held-out code-repair benchmark, security review, format conversion,
SHA-256/signature verification, Android memory/performance checks, and a
rollback test. A lower training loss alone is not proof of better repairs.
