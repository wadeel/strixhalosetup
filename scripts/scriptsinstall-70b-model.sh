#!/usr/bin/env bash
set -euo pipefail

# Download a large GGUF model for llama.cpp.
#
# Note:
# - llama.cpp does NOT require huggingface-cli to run models.
# - Hugging Face tooling is only used here as a downloader when MODEL_SOURCE=huggingface.
#
# Supported sources:
#   MODEL_SOURCE=huggingface (default)
#   MODEL_SOURCE=url
#
# Defaults target:
#   puwaer/Qwen3-Next-80B-A3B-Thinking-GRPO-Uncensored-gguf
#
# Examples:
#   MODEL_SOURCE=huggingface \
#     MODEL_ID='puwaer/Qwen3-Next-80B-A3B-Thinking-GRPO-Uncensored-gguf' \
#     MODEL_FILE='Qwen3-Next-80B-A3B-Thinking-GRPO-Uncensored-Q4_K_M.gguf' \
#     bash scripts/scriptsinstall-70b-model.sh
#
#   MODEL_SOURCE=huggingface \
#     MODEL_ID='puwaer/Qwen3-Next-80B-A3B-Thinking-GRPO-Uncensored-gguf' \
#     MODEL_PATTERN='*Q4_K_M*.gguf' \
#     bash scripts/scriptsinstall-70b-model.sh
#
#   MODEL_SOURCE=url MODEL_URL='https://host/path/model.gguf' \
#     bash scripts/scriptsinstall-70b-model.sh

model_source="${MODEL_SOURCE:-huggingface}"
model_dir="${MODEL_DIR:-/models}"
hf_cli_venv="${HF_CLI_VENV:-$HOME/.local/share/huggingface-cli-venv}"

mkdir -p "$model_dir"

hf_cli_mode=""
hf_cli_python=""

run_hf_cli() {
  if [[ "$hf_cli_mode" == "binary" ]]; then
    huggingface-cli "$@"
  else
    "$hf_cli_python" -m huggingface_hub.commands.huggingface_cli "$@"
  fi
}

ensure_huggingface_cli() {
  if command -v huggingface-cli >/dev/null 2>&1; then
    hf_cli_mode="binary"
    return 0
  fi

  if [[ -x "$hf_cli_venv/bin/python" ]]; then
    hf_cli_mode="python-module"
    hf_cli_python="$hf_cli_venv/bin/python"
    return 0
  fi

  echo "huggingface-cli not found. Trying virtual environment: $hf_cli_venv"
  if python3 -m venv "$hf_cli_venv"; then
    "$hf_cli_venv/bin/python" -m pip install --upgrade pip huggingface_hub
    hf_cli_mode="python-module"
    hf_cli_python="$hf_cli_venv/bin/python"
    return 0
  fi

  echo "Warning: python3 -m venv failed (python3-venv/ensurepip may be missing)."
  echo "Falling back to system Python install with --break-system-packages."

  if ! python3 -m pip install --upgrade --break-system-packages huggingface_hub; then
    echo "Failed to install huggingface_hub via system Python fallback."
    echo "Install python3-venv (preferred) or install huggingface_hub manually, then retry."
    exit 1
  fi

  hf_cli_mode="python-module"
  hf_cli_python="python3"
}

case "$model_source" in
  huggingface)
    model_id="${MODEL_ID:-puwaer/Qwen3-Next-80B-A3B-Thinking-GRPO-Uncensored-gguf}"
    model_file="${MODEL_FILE:-}"
    model_pattern="${MODEL_PATTERN:-*Q4_K_M*.gguf}"

    ensure_huggingface_cli

    if [[ -n "${HF_TOKEN:-}" ]]; then
      run_hf_cli login --token "$HF_TOKEN" >/dev/null
    fi

    if [[ -n "$model_file" ]]; then
      echo "Downloading exact file $model_file from $model_id into $model_dir"
      run_hf_cli download "$model_id" "$model_file" \
        --local-dir "$model_dir" \
        --local-dir-use-symlinks False
      downloaded_ref="$model_file"
    else
      echo "MODEL_FILE not set; downloading files matching pattern '$model_pattern' from $model_id into $model_dir"
      echo "Set MODEL_FILE to force one exact GGUF filename."
      run_hf_cli download "$model_id" \
        --include "$model_pattern" \
        --local-dir "$model_dir" \
        --local-dir-use-symlinks False
      downloaded_ref="$model_pattern"
    fi
    ;;

  url)
    model_url="${MODEL_URL:-}"
    if [[ -z "$model_url" ]]; then
      echo "MODEL_URL is required when MODEL_SOURCE=url"
      exit 1
    fi

    model_file="${MODEL_FILE:-$(basename "$model_url")}"
    echo "Downloading $model_file from $model_url into $model_dir"
    curl -fL "$model_url" -o "$model_dir/$model_file"
    downloaded_ref="$model_file"
    ;;

  *)
    echo "Unsupported MODEL_SOURCE: $model_source"
    echo "Use MODEL_SOURCE=huggingface or MODEL_SOURCE=url"
    exit 1
    ;;
esac

echo "Model download complete. Reference: $downloaded_ref"
echo "Directory: $model_dir"
