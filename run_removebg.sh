#!/usr/bin/env bash
set -euo pipefail

# Batch conversion + remove background.
# Default input folder: /home/altariox/Videos/removebg

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"

INPUT_DIR="${1:-/home/altariox/Videos/removebg}"

# Optional: create venv locally
if [[ ! -d "$PROJECT_DIR/.venv" ]]; then
  python3 -m venv "$PROJECT_DIR/.venv"
fi

source "$PROJECT_DIR/.venv/bin/activate"

python -m pip install --upgrade pip >/dev/null
python -m pip install -r "$PROJECT_DIR/requirements.txt"

# Use GPU if user set USE_GPU=1
EXTRA_ARGS=()
if [[ "${USE_GPU:-0}" == "1" ]]; then
  EXTRA_ARGS+=("--prefer-gpu")
fi

python "$PROJECT_DIR/removebg_batch.py" --input-dir "$INPUT_DIR" --skip-existing "${EXTRA_ARGS[@]}"
