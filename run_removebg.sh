#!/usr/bin/env bash
set -euo pipefail

# Batch conversion + remove background.
# Default input folder: /home/altariox/Videos/removebg
#
# This project uses rembg (onnxruntime). On this machine Python is 3.14, and
# onnxruntime wheels may not be available for 3.14. So this launcher runs the
# pipeline inside Docker with Python 3.12.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"

INPUT_DIR="${1:-/home/altariox/Videos/removebg}"

if [[ ! -d "$INPUT_DIR" ]]; then
  echo "Input directory not found: $INPUT_DIR" >&2
  exit 2
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is required but not found in PATH." >&2
  exit 3
fi

USE_GPU_FLAG="${USE_GPU:-0}"

IMAGE_CPU="removebg-batch-gpu:cpu"
IMAGE_GPU="removebg-batch-gpu:gpu"

DOCKERFILE="$PROJECT_DIR/docker/Dockerfile.cpu"
IMAGE="$IMAGE_CPU"
DOCKER_RUN_ARGS=(--rm)

if [[ "$USE_GPU_FLAG" == "1" ]]; then
  DOCKERFILE="$PROJECT_DIR/docker/Dockerfile.gpu"
  IMAGE="$IMAGE_GPU"
  DOCKER_RUN_ARGS+=(--gpus all)
fi

# Build image if missing
if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "Building Docker image: $IMAGE" >&2
  docker build -f "$DOCKERFILE" -t "$IMAGE" "$PROJECT_DIR"
fi

EXTRA_ARGS=()
if [[ "$USE_GPU_FLAG" == "1" ]]; then
  EXTRA_ARGS+=("--prefer-gpu")
fi

docker run "${DOCKER_RUN_ARGS[@]}" \
  -v "$PROJECT_DIR:/work:ro" \
  -v "$INPUT_DIR:/input" \
  -w /work \
  "$IMAGE" \
  python /work/removebg_batch.py --input-dir /input --skip-existing "${EXTRA_ARGS[@]}"
