#!/bin/bash
#
# Wan 2.2 I2V Setup for RunPod
# Base image: runpod/pytorch:1.0.2-cu1281-torch280-ubuntu2404
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/Reuben-Fernandes/runpod-download/main/wan22.sh | HF_TOKEN=hf_yourtoken bash
#

COMFYUI_DIR=/workspace/ComfyUI
VENV_PYTHON="$COMFYUI_DIR/.venv/bin/python"
VENV_PIP="$COMFYUI_DIR/.venv/bin/pip"

echo ""
echo "########################################"
echo "#        Wan 2.2 I2V Setup            #"
echo "########################################"
echo ""

if [[ -z "$HF_TOKEN" ]]; then
    echo "ERROR: No HuggingFace token found."
    echo "       curl -fsSL .../wan22.sh | HF_TOKEN=hf_yourtoken bash"
    exit 1
fi
echo "✓ Token detected"

MODELS_DIR="$COMFYUI_DIR/models"
NODES_DIR="$COMFYUI_DIR/custom_nodes"
MIRROR="ReubenF10/ComfyUI-Models"
export HF_TOKEN

# ── Phase 0: ComfyUI ─────────────────────────────────────────────
echo ""
echo "========================================"
echo "  PHASE 0: ComfyUI"
echo "========================================"

if [[ -d "$COMFYUI_DIR" ]]; then
    echo "  → ComfyUI exists, pulling latest..."
    (cd "$COMFYUI_DIR" && git pull)
else
    echo "  → Cloning ComfyUI..."
    git clone https://github.com/comfyanonymous/ComfyUI.git "$COMFYUI_DIR"
fi

echo "  → Setting up venv..."
python3 -m venv "$COMFYUI_DIR/.venv"
$VENV_PIP install --upgrade pip --quiet
$VENV_PIP install -r "$COMFYUI_DIR/requirements.txt" --quiet
echo "✓ ComfyUI ready"

# ── Phase 1: Dependencies ────────────────────────────────────────
echo ""
echo "========================================"
echo "  PHASE 1: Dependencies"
echo "========================================"
$VENV_PIP install "huggingface_hub[cli]" hf_transfer --quiet
export HF_HUB_ENABLE_HF_TRANSFER=1
echo "✓ Done"

# ── Phase 2: Custom Nodes ────────────────────────────────────────
echo ""
echo "========================================"
echo "  PHASE 2: Custom Nodes"
echo "========================================"
mkdir -p "$NODES_DIR"

for repo in \
    "https://github.com/ltdrdata/ComfyUI-Manager" \
    "https://github.com/city96/ComfyUI-GGUF" \
    "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite" \
    "https://github.com/Fannovel16/ComfyUI-Frame-Interpolation" \
    "https://github.com/kijai/ComfyUI-WanVideoWrapper" \
    "https://github.com/kijai/ComfyUI-KJNodes"
do
    dir="${repo##*/}"
    path="$NODES_DIR/$dir"
    echo "  → $dir"
    if [[ -d "$path" ]]; then
        (cd "$path" && git pull --recurse-submodules)
    else
        git clone "$repo" "$path" --recursive
    fi
    if [[ -f "$path/requirements.txt" ]]; then
        $VENV_PIP install -r "$path/requirements.txt" --quiet || true
    fi
done
echo "✓ Done"

# ── Phase 3: Models ──────────────────────────────────────────────
echo ""
echo "========================================"
echo "  PHASE 3: Models"
echo "========================================"

download_hf() {
    local repo_id="$1" filename="$2" dest_folder="$3" save_name="$4"
    local full_dest="$MODELS_DIR/$dest_folder"
    local dest_file="$full_dest/$save_name"

    echo ""
    echo "  → $save_name"
    if [[ -f "$dest_file" ]]; then echo "  ⏭  Already exists, skipping."; return 0; fi

    mkdir -p "$full_dest"
    local temp_dir; temp_dir=$(mktemp -d)

    $VENV_PYTHON << EOF
import os, shutil, sys
from huggingface_hub import hf_hub_download
try:
    path = hf_hub_download(
        repo_id="$repo_id", filename="$filename",
        token=os.environ["HF_TOKEN"], local_dir="$temp_dir",
        local_dir_use_symlinks=False, force_download=True
    )
    shutil.move(path, os.path.join("$full_dest", "$save_name"))
    print("  ✓ Saved")
    sys.exit(0)
except Exception as e:
    print(f"  ✗ Failed: {e}", file=sys.stderr)
    sys.exit(1)
EOF
    local result=$?; rm -rf "$temp_dir"; return $result
}

FAILED=0

download_hf "$MIRROR" "unet/Wan2.2-I2V-A14B-HighNoise-Q4_K_S.gguf" \
    "unet" "Wan2.2-I2V-A14B-HighNoise-Q4_K_S.gguf" || FAILED=1

download_hf "$MIRROR" "unet/Wan2.2-I2V-A14B-LowNoise-Q4_0.gguf" \
    "unet" "Wan2.2-I2V-A14B-LowNoise-Q4_0.gguf" || FAILED=1

download_hf "$MIRROR" "vae/Wan2.1_VAE.safetensors" \
    "vae" "Wan2.1_VAE.safetensors" || FAILED=1

download_hf "$MIRROR" "loras/Wan21_I2V_14B_lightx2v_cfg_step_distill_lora_rank64.safetensors" \
    "loras" "Wan21_I2V_14B_lightx2v_cfg_step_distill_lora_rank64.safetensors" || FAILED=1

download_hf "$MIRROR" "text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors" \
    "text_encoders" "umt5_xxl_fp8_e4m3fn_scaled.safetensors" || FAILED=1

echo ""
[[ $FAILED -eq 0 ]] && echo "✓ Phase 3 complete" || echo "⚠️  Some downloads failed"

# ── Phase 4: SageAttention ───────────────────────────────────────
echo ""
echo "========================================"
echo "  PHASE 4: SageAttention"
echo "========================================"

SA_WHEEL="sageattention-2.2.0-cp312-cp312-linux_x86_64.whl"
SA_WHEEL_PATH="/tmp/$SA_WHEEL"

if $VENV_PYTHON -c "from sageattention import sageattn_qk_int8_pv_fp16_cuda" 2>/dev/null; then
    echo "✓ SageAttention 2.2.0 already installed"
else
    echo "  → Downloading precompiled wheel from Kijai/PrecompiledWheels..."

    $VENV_PYTHON << EOF
import os, sys
from huggingface_hub import hf_hub_download
try:
    path = hf_hub_download(
        repo_id="Kijai/PrecompiledWheels",
        filename="$SA_WHEEL",
        token=os.environ["HF_TOKEN"],
        local_dir="/tmp",
        local_dir_use_symlinks=False,
        force_download=False
    )
    print(f"  ✓ Downloaded to {path}")
    sys.exit(0)
except Exception as e:
    print(f"  ✗ Download failed: {e}", file=sys.stderr)
    sys.exit(1)
EOF

    if [[ $? -eq 0 ]]; then
        $VENV_PIP install "$SA_WHEEL_PATH" \
            && echo "✓ SageAttention 2.2.0 installed" \
            || echo "⚠️  SageAttention install failed — continuing without it"
    else
        echo "⚠️  SageAttention download failed — continuing without it"
    fi
fi

# ── Phase 5: Start ComfyUI ───────────────────────────────────────
echo ""
echo "========================================"
echo "  PHASE 5: Start ComfyUI"
echo "========================================"
echo "  → Launching ComfyUI on port 8188..."
nohup $VENV_PYTHON "$COMFYUI_DIR/main.py" --listen 0.0.0.0 --port 8188 \
    > /workspace/comfyui.log 2>&1 &
echo "✓ ComfyUI started (logs at /workspace/comfyui.log)"

echo ""
echo "########################################"
echo "#      Wan 2.2 Setup Complete         #"
echo "########################################"
echo ""
echo "Access ComfyUI at: http://localhost:8188"
echo ""
echo "Recommended Settings:"
echo "  Steps:      4-8 (with Lightning LoRA)"
echo "  CFG:        1.0-1.5"
echo "  Resolution: 720x1280 (9:16)"
echo "  Frames:     49 (or 33 for faster iteration)"
echo "  VRAM:       ~16-18GB (GGUF Q4)"
echo ""
echo "SageAttention Node Settings (Kijai):"
echo "  Mode:       sageattn_qk_int8_pv_fp16_cuda"
echo "  Allow compile: true"
echo ""
