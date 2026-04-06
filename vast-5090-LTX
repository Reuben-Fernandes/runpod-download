#!/bin/bash

# ── Install dependencies ─────────────────────────────────────────
pip install huggingface_hub hf_transfer --quiet

# ── Install SA3 wheel ────────────────────────────────────────────
pip install https://huggingface.co/ReubenF10/ComfyUI-Models/resolve/main/wheels/ltx/5090/sageattn3-1.0.0-cp312-cp312-linux_x86_64.whl --quiet

# ── Download models ──────────────────────────────────────────────
export HF_HUB_ENABLE_HF_TRANSFER=1

python3 << PYEOF
import os, shutil
from huggingface_hub import hf_hub_download

token = os.environ["HF_TOKEN"]
base = "/workspace/ComfyUI/models"

models = [
    ("Lightricks/LTX-2.3-fp8", "ltx-2.3-22b-dev-fp8.safetensors",             "checkpoints"),
    ("Lightricks/LTX-2.3",     "ltx-2.3-22b-distilled-lora-384.safetensors",  "loras"),
    ("Lightricks/LTX-2.3",     "ltx-2.3-spatial-upscaler-x2-1.1.safetensors", "latent_upscale_models"),
]

for repo_id, filename, dest_folder in models:
    save_name = filename.split("/")[-1]
    dest = os.path.join(base, dest_folder, save_name)
    if os.path.exists(dest):
        print(f"  ⏭  Already exists: {save_name}")
        continue
    os.makedirs(os.path.join(base, dest_folder), exist_ok=True)
    print(f"  → Downloading: {save_name}")
    path = hf_hub_download(repo_id=repo_id, filename=filename, token=token, local_dir="/tmp/hf_dl", local_dir_use_symlinks=False)
    shutil.move(path, dest)
    print(f"  ✓ Saved: {save_name}")
PYEOF

# ── Download custom nodes ────────────────────────────────────────
cd /workspace/ComfyUI/custom_nodes
git clone https://github.com/Lightricks/ComfyUI-LTXVideo --quiet
pip install -r /workspace/ComfyUI/custom_nodes/ComfyUI-LTXVideo/requirements.txt --quiet

# ── Restart ComfyUI ──────────────────────────────────────────────
supervisorctl restart comfyui
