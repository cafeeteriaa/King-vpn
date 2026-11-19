# King AI local QLoRA runner setup

The training workflow does not call a hosted AI API and does not train on the Android phone. It creates a review-only adapter candidate on a dedicated machine that you control.

## One-time GitHub runner setup

1. Prepare a trusted Linux x64 machine with an NVIDIA GPU, a compatible NVIDIA driver/CUDA runtime, Python 3, and enough free disk space for the base checkpoint, dependencies, and checkpoints.
2. In the repository, open **Settings → Actions → Runners → New self-hosted runner** and follow GitHub's Linux x64 installation/configuration commands on that machine.
3. Add the custom runner labels **gpu** and **king-ai-training** (keep the default self-hosted, linux, and x64 labels). The workflow targets all five labels.
4. Keep this runner dedicated to this repository and do not allow untrusted pull-request code to execute on it. The workflow only trains from the default branch or an explicit manual dispatch.
5. Place a reviewed Hugging Face Transformers checkpoint on the runner. It must contain config.json, tokenizer files, and .safetensors or PyTorch weight files. A GGUF inference file from the Android app is not a training checkpoint.
6. In **Settings → Secrets and variables → Actions → Variables**, add KING_AI_BASE_MODEL_PATH with the absolute local path to that checkpoint. This is a path on the runner, not a downloadable URL or secret.
7. Ensure at least five accepted examples exist in data/king_ai_accepted_repairs.jsonl. Examples are collected only from merged, CI-green, allowlisted repair PRs and are screened for secrets.

## Run and verify

- Once the runner and variable exist, the dataset workflow can dispatch QLoRA training after the accepted dataset reaches five examples.
- You can also start **Actions → King AI Local QLoRA Training → Run workflow** and provide the local model path, dataset path, and bounded step count.
- The workflow prepares deterministic train/evaluation splits, performs a CUDA/model/dataset preflight, trains an isolated adapter, verifies its SHA-256 manifest, and uploads a candidate artifact.
- The artifact is not installed in King VPN. Conversion to the app's GGUF format, held-out repair benchmarks, security review, signature verification, device testing, and rollback validation remain mandatory before a model update.

## Why this cannot be fully provisioned by a repository commit

GitHub does not provide a GPU machine merely because a workflow requests the gpu label. A repository maintainer must attach a trusted GPU runner and place the model checkpoint on its local disk. The workflow now checks these prerequisites early and reports actionable failures instead of reaching the expensive training step with an unusable environment.
