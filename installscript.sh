#!/bin/bash
#
# ComfyUI Full Setup Script for RunPod
# Includes: Qwen 3 TTS | Z Image Turbo | LTX Video 2.3 GGUF
#
# Usage (one-liner):
#   curl -fsSL https://raw.githubusercontent.com/Reuben-Fernandes/runpod-download/main/installscript.sh | HF_TOKEN=hf_yourtoken bash
#
# HF_TOKEN is passed as an environment variable — never hardcoded.
#
COMFYUI_DIR=/workspace/runpod-slim/ComfyUI

echo ""
echo "########################################"
echo "#    ComfyUI Full Setup Script        #"
echo "#  Qwen TTS | Z Image Turbo | LTX 2.3 #"
echo "########################################"
echo ""

# ── Validate token ──────────────────────────────────────────────
if [[ -z "$HF_TOKEN" ]]; then
    echo "ERROR: No HuggingFace token found."
    echo "       Run with: HF_TOKEN=hf_yourtoken bash setup.sh"
    echo "       Or as a one-liner:"
    echo "       curl -fsSL https://raw.githubusercontent.com/Reuben-Fernandes/runpod-download/main/installscript.sh | HF_TOKEN=hf_yourtoken bash"
    exit 1
fi
echo "✓ Token detected"

# ── Validate ComfyUI ────────────────────────────────────────────
if [[ ! -d "$COMFYUI_DIR" ]]; then
    echo "ERROR: ComfyUI not found at $COMFYUI_DIR"
    exit 1
fi
echo "✓ ComfyUI found at: $COMFYUI_DIR"

MODELS_DIR="$COMFYUI_DIR/models"
NODES_DIR="$COMFYUI_DIR/custom_nodes"

PYTHON_CMD="python3"
PIP_CMD="$PYTHON_CMD -m pip"
export HF_TOKEN

echo ""
echo "Using: $($PYTHON_CMD --version)"


# ════════════════════════════════════════════════════════════════
#  PHASE 1: Dependencies
# ════════════════════════════════════════════════════════════════
echo ""
echo "========================================"
echo "  PHASE 1: Install Dependencies"
echo "========================================"

$PIP_CMD install --upgrade pip
$PIP_CMD install "huggingface_hub[cli]" --break-system-packages
$PIP_CMD install hf_transfer --quiet --break-system-packages
export HF_HUB_ENABLE_HF_TRANSFER=1

# NOTE: transformers pinned to 4.57.3 for Qwen TTS compatibility.
# If LTX 2.3 or Z Image Turbo workflows break, try unpinning this.
$PIP_CMD install "transformers==4.57.3" --break-system-packages

echo "✓ Phase 1 complete"


# ════════════════════════════════════════════════════════════════
#  PHASE 2: Custom Nodes
# ════════════════════════════════════════════════════════════════
echo ""
echo "========================================"
echo "  PHASE 2: Install Custom Nodes"
echo "========================================"

mkdir -p "$NODES_DIR"

NODES=(
    "https://github.com/city96/ComfyUI-GGUF"
    "https://github.com/rgthree/rgthree-comfy"
    "https://github.com/chrisgoringe/cg-use-everywhere"
    "https://github.com/kijai/ComfyUI-KJNodes"
    "https://github.com/LAOGOU-666/ComfyUI-LG_SamplingUtils"
    "https://github.com/flybirdxx/ComfyUI-Qwen-TTS"
    "https://github.com/numz/ComfyUI-SeedVR2_VideoUpscaler"
    "https://github.com/yolain/ComfyUI-Easy-Use"
    "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite"
    "https://github.com/olduvai-jp/ComfyUI-S3-IO"
)

for repo in "${NODES[@]}"; do
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

echo "✓ Phase 2 complete"


# ════════════════════════════════════════════════════════════════
#  PHASE 3: Download Models
#  All models served from ReubenF10/ComfyUI-Models
# ════════════════════════════════════════════════════════════════
echo ""
echo "========================================"
echo "  PHASE 3: Download Models"
echo "========================================"

download_hf() {
    local repo_id="$1"
    local filename="$2"
    local dest_folder="$3"
    local save_name="$4"
    local full_dest="$MODELS_DIR/$dest_folder"
    local dest_file="$full_dest/$save_name"

    echo ""
    echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  → $save_name"

    if [[ -f "$dest_file" ]]; then
        echo "  ⏭  Already exists, skipping."
        echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        return 0
    fi

    mkdir -p "$full_dest"
    local temp_dir
    temp_dir=$(mktemp -d)

    $PYTHON_CMD << EOF
import os, shutil, sys
from huggingface_hub import hf_hub_download

try:
    path = hf_hub_download(
        repo_id="$repo_id",
        filename="$filename",
        token=os.environ["HF_TOKEN"],
        local_dir="$temp_dir",
        local_dir_use_symlinks=False,
        force_download=True
    )
    shutil.move(path, os.path.join("$full_dest", "$save_name"))
    print("  ✓ Saved: $save_name")
    sys.exit(0)
except Exception as e:
    print(f"  ✗ Failed: $save_name — {e}", file=sys.stderr)
    sys.exit(1)
EOF

    local result=$?
    rm -rf "$temp_dir"
    return $result
}

MIRROR="ReubenF10/ComfyUI-Models"
FAILED=0

# ── Qwen TTS ─────────────────────────────────────────────────────
echo ""
echo "  ── Qwen 3 TTS ──"
mkdir -p "$MODELS_DIR/qwen-tts/Qwen"

download_hf "$MIRROR" \
    "qwen-tts/Qwen/Qwen3-TTS-Tokenizer-12Hz/model.safetensors" \
    "qwen-tts/Qwen/Qwen3-TTS-Tokenizer-12Hz" "model.safetensors" || FAILED=1

download_hf "$MIRROR" \
    "qwen-tts/Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign/model.safetensors" \
    "qwen-tts/Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign" "model.safetensors" || FAILED=1

download_hf "$MIRROR" \
    "qwen-tts/Qwen/Qwen3-TTS-12Hz-1.7B-Base/model.safetensors" \
    "qwen-tts/Qwen/Qwen3-TTS-12Hz-1.7B-Base" "model.safetensors" || FAILED=1

download_hf "$MIRROR" \
    "qwen-tts/Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice/model.safetensors" \
    "qwen-tts/Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice" "model.safetensors" || FAILED=1

# ── Z Image Turbo ─────────────────────────────────────────────────
echo ""
echo "  ── Z Image Turbo ──"

download_hf "$MIRROR" \
    "diffusion_models/z_image_turbo_bf16.safetensors" \
    "diffusion_models" "z_image_turbo_bf16.safetensors" || FAILED=1

download_hf "$MIRROR" \
    "text_encoders/qwen_3_4b.safetensors" \
    "text_encoders" "qwen_3_4b.safetensors" || FAILED=1

download_hf "$MIRROR" \
    "vae/ae.safetensors" \
    "vae" "ae.safetensors" || FAILED=1

# ── LTX 2.3 ──────────────────────────────────────────────────────
echo ""
echo "  ── LTX Video 2.3 ──"

download_hf "$MIRROR" \
    "diffusion_models/LTX-2.3-distilled-Q4_K_S.gguf" \
    "diffusion_models" "LTX-2.3-distilled-Q4_K_S.gguf" || FAILED=1

download_hf "$MIRROR" \
    "text_encoders/gemma-3-12b-it-Q2_K.gguf" \
    "text_encoders" "gemma-3-12b-it-Q2_K.gguf" || FAILED=1

download_hf "$MIRROR" \
    "text_encoders/ltx-2.3_text_projection_bf16.safetensors" \
    "text_encoders" "ltx-2.3_text_projection_bf16.safetensors" || FAILED=1

download_hf "$MIRROR" \
    "latent_upscale_models/ltx-2.3-spatial-upscaler-x2-1.0.safetensors" \
    "latent_upscale_models" "ltx-2.3-spatial-upscaler-x2-1.0.safetensors" || FAILED=1

download_hf "$MIRROR" \
    "vae/LTX23_video_vae_bf16.safetensors" \
    "vae" "LTX23_video_vae_bf16.safetensors" || FAILED=1

download_hf "$MIRROR" \
    "vae/LTX23_audio_vae_bf16.safetensors" \
    "vae" "LTX23_audio_vae_bf16.safetensors" || FAILED=1

download_hf "$MIRROR" \
    "vae/taeltx2_3.safetensors" \
    "vae" "taeltx2_3.safetensors" || FAILED=1

echo ""
if [[ $FAILED -gt 0 ]]; then
    echo "⚠️  Some downloads failed — check errors above."
else
    echo "✓ Phase 3 complete — all models downloaded"
fi


# ════════════════════════════════════════════════════════════════
#  PHASE 4: SageAttention
# ════════════════════════════════════════════════════════════════
echo ""
echo "========================================"
echo "  PHASE 4: SageAttention"
echo "========================================"

$PIP_CMD install sageattention --break-system-packages 2>/dev/null \
    && echo "✓ SageAttention installed" \
    || echo "⚠️  SageAttention skipped (optional, not critical)"


# ════════════════════════════════════════════════════════════════
#  DONE
# ════════════════════════════════════════════════════════════════
echo ""
echo "########################################"
echo "#          SETUP COMPLETE             #"
echo "########################################"
echo ""
echo "ComfyUI Location:  $COMFYUI_DIR"
echo ""
echo "Models from: huggingface.co/ReubenF10/ComfyUI-Models"
echo ""
echo "  qwen-tts/Qwen/"
echo "    • Qwen3-TTS-Tokenizer-12Hz/"
echo "    • Qwen3-TTS-12Hz-1.7B-VoiceDesign/"
echo "    • Qwen3-TTS-12Hz-1.7B-Base/"
echo "    • Qwen3-TTS-12Hz-1.7B-CustomVoice/"
echo "  diffusion_models/"
echo "    • z_image_turbo_bf16.safetensors"
echo "    • LTX-2.3-distilled-Q4_K_S.gguf"
echo "  text_encoders/"
echo "    • qwen_3_4b.safetensors"
echo "    • gemma-3-12b-it-Q2_K.gguf"
echo "    • ltx-2.3_text_projection_bf16.safetensors"
echo "  latent_upscale_models/"
echo "    • ltx-2.3-spatial-upscaler-x2-1.0.safetensors"
echo "  vae/"
echo "    • ae.safetensors"
echo "    • LTX23_video_vae_bf16.safetensors"
echo "    • LTX23_audio_vae_bf16.safetensors"
echo "    • taeltx2_3.safetensors"
echo ""
echo "Custom Nodes:"
echo "  • ComfyUI-GGUF"
echo "  • rgthree-comfy"
echo "  • cg-use-everywhere"
echo "  • ComfyUI-KJNodes"
echo "  • ComfyUI-LG_SamplingUtils"
echo "  • ComfyUI-Qwen-TTS"
echo "  • ComfyUI-SeedVR2_VideoUpscaler"
echo "  • ComfyUI-Easy-Use"
echo "  • ComfyUI-VideoHelperSuite"
echo "  • ComfyUI-S3-IO"
echo ""
echo "Next: Restart ComfyUI and load your workflows!"
