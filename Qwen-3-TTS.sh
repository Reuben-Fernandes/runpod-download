#!/bin/bash
#
# Qwen 3 TTS Setup for RunPod
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/Reuben-Fernandes/runpod-download/main/qwen-tts.sh | HF_TOKEN=hf_yourtoken bash
#

COMFYUI_DIR=/workspace/runpod-slim/ComfyUI

echo ""
echo "########################################"
echo "#        Qwen 3 TTS Setup             #"
echo "########################################"
echo ""

if [[ -z "$HF_TOKEN" ]]; then
    echo "ERROR: No HuggingFace token found."
    echo "       curl -fsSL .../qwen-tts.sh | HF_TOKEN=hf_yourtoken bash"
    exit 1
fi
echo "✓ Token detected"

if [[ ! -d "$COMFYUI_DIR" ]]; then
    echo "ERROR: ComfyUI not found at $COMFYUI_DIR"
    exit 1
fi
echo "✓ ComfyUI found at: $COMFYUI_DIR"

MODELS_DIR="$COMFYUI_DIR/models"
NODES_DIR="$COMFYUI_DIR/custom_nodes"
PYTHON_CMD="python3"
PIP_CMD="$PYTHON_CMD -m pip"
MIRROR="ReubenF10/ComfyUI-Models"
export HF_TOKEN

# ── Phase 1: Dependencies ────────────────────────────────────────
echo ""
echo "========================================"
echo "  PHASE 1: Dependencies"
echo "========================================"
$PIP_CMD install --upgrade pip
$PIP_CMD install "huggingface_hub[cli]" hf_transfer --break-system-packages --quiet
# NOTE: pinned for Qwen TTS compatibility
$PIP_CMD install "transformers==4.57.3" --break-system-packages
export HF_HUB_ENABLE_HF_TRANSFER=1
echo "✓ Done"

# ── Phase 2: Custom Nodes ────────────────────────────────────────
echo ""
echo "========================================"
echo "  PHASE 2: Custom Nodes"
echo "========================================"
mkdir -p "$NODES_DIR"

for repo in \
    "https://github.com/city96/ComfyUI-GGUF" \
    "https://github.com/kijai/ComfyUI-KJNodes" \
    "https://github.com/LAOGOU-666/ComfyUI-LG_SamplingUtils" \
    "https://github.com/flybirdxx/ComfyUI-Qwen-TTS"
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
        $PIP_CMD install -r "$path/requirements.txt" --break-system-packages --quiet || true
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

    $PYTHON_CMD << EOF
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
mkdir -p "$MODELS_DIR/qwen-tts/Qwen"

download_hf "$MIRROR" "qwen-tts/Qwen/Qwen3-TTS-Tokenizer-12Hz/model.safetensors" \
    "qwen-tts/Qwen/Qwen3-TTS-Tokenizer-12Hz" "model.safetensors" || FAILED=1

download_hf "$MIRROR" "qwen-tts/Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign/model.safetensors" \
    "qwen-tts/Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign" "model.safetensors" || FAILED=1

download_hf "$MIRROR" "qwen-tts/Qwen/Qwen3-TTS-12Hz-1.7B-Base/model.safetensors" \
    "qwen-tts/Qwen/Qwen3-TTS-12Hz-1.7B-Base" "model.safetensors" || FAILED=1

download_hf "$MIRROR" "qwen-tts/Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice/model.safetensors" \
    "qwen-tts/Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice" "model.safetensors" || FAILED=1

echo ""
[[ $FAILED -eq 0 ]] && echo "✓ Phase 3 complete" || echo "⚠️  Some downloads failed"

# ── Phase 4: SageAttention ───────────────────────────────────────
echo ""
echo "========================================"
echo "  PHASE 4: SageAttention"
echo "========================================"
$PIP_CMD install sageattention --break-system-packages 2>/dev/null \
    && echo "✓ Installed" || echo "⚠️  Skipped (optional)"

echo ""
echo "########################################"
echo "#       Qwen TTS Setup Complete       #"
echo "########################################"
echo ""
