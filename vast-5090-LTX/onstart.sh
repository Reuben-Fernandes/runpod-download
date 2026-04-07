#!/bin/bash
set -e

echo "########################################"
echo "#   LTX 2.3 5090 - Provisioning       #"
echo "########################################"

# ── Install dependencies ─────────────────────────────────────────
echo " → Installing dependencies..."
pip install hf_transfer "huggingface_hub[cli]"

# ── Start model downloads in background ──────────────────────────
echo " → Starting model downloads in background..."
export HF_HUB_ENABLE_HF_TRANSFER=1

python3 << PYEOF &
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
print("✓ All models ready")
PYEOF

MODEL_PID=$!

# ── Install SA3 wheel ────────────────────────────────────────────
echo " → Installing SageAttention3..."
pip install https://huggingface.co/ReubenF10/ComfyUI-Models/resolve/main/wheels/ltx/5090/sageattn3-1.0.0-cp312-cp312-linux_x86_64.whl

# ── Install custom nodes ─────────────────────────────────────────
echo " → Installing custom nodes..."
cd /workspace/ComfyUI/custom_nodes

echo "   Cloning ComfyUI-LTXVideo..."
git clone https://github.com/Lightricks/ComfyUI-LTXVideo || true

echo "   Cloning ComfyUI-KJNodes..."
git clone https://github.com/kijai/ComfyUI-KJNodes || true

echo "   Cloning rgthree-comfy..."
git clone https://github.com/rgthree/rgthree-comfy || true

echo "   Cloning ComfyUI-GGUF..."
git clone https://github.com/city96/ComfyUI-GGUF || true

echo "   Cloning ComfyUI-VideoHelperSuite..."
git clone https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite || true

echo "   Cloning ComfyUI-Easy-Use..."
git clone https://github.com/yolain/ComfyUI-Easy-Use || true

echo "   Cloning ComfyMath..."
git clone https://github.com/evanspearman/ComfyMath || true

echo " → Installing node requirements..."
for dir in /workspace/ComfyUI/custom_nodes/*/; do
    if [ -f "$dir/requirements.txt" ]; then
        echo "   Installing requirements for $(basename $dir)..."
        pip install -r "$dir/requirements.txt" || true
    fi
done

# ── Wait for models to finish ─────────────────────────────────────
echo " → Waiting for model downloads to complete..."
wait $MODEL_PID
echo "✓ Models ready"

# ── Restart ComfyUI ──────────────────────────────────────────────
echo " → Restarting ComfyUI..."
supervisorctl restart comfyui

# ── Print access details ─────────────────────────────────────────
echo ""
echo "########################################"
echo "  ComfyUI Access Details"
echo "  Token: $(echo $OPEN_BUTTON_TOKEN)"
echo "  Direct: http://$(curl -s ifconfig.me):$(echo $VAST_TCP_PORT_8188)"
echo "########################################"
echo ""

echo "✓ Provisioning complete"
