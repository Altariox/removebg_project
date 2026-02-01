#!/usr/bin/env bash
set -euo pipefail

# One-file runner (only this .sh is needed):
# - watches a folder, every N seconds
# - converts any image to JPG
# - removes background with AI (rembg)
# - replaces the original in-place with <stem>.jpg
#
# Defaults:
# - Folder:   /home/altariox/Pictures/removebg
# - Watch:    enabled (every 10s)
# - Quality:  95
# - Min age:  2s (avoid processing half-copied files)

INPUT_DIR="${1:-/home/altariox/Pictures/removebg}"

WATCH_FLAG="${WATCH:-1}"          # 1=continuous, 0=one-shot
INTERVAL_SEC="${INTERVAL:-10}"
MIN_AGE_SEC="${MIN_AGE:-2}"
QUALITY="${QUALITY:-95}"
FORCE_FLAG="${FORCE:-0}"      # 1=reprocess even if state says seen
FIX_PERMS_FLAG="${FIX_PERMS:-0}"  # 1=try to fix ownership/permissions via docker (no sudo)

USE_GPU_FLAG="${USE_GPU:-0}"      # 1=try GPU (needs NVIDIA toolkit)

HOST_UID="$(id -u)"
HOST_GID="$(id -g)"

# Cache for rembg/u2net models on the host (avoid re-downloading)
mkdir -p "$HOME/.u2net"
REBUILD_FLAG="${REBUILD:-0}"      # 1=force rebuild Docker image

if [[ ! -d "$INPUT_DIR" ]]; then
  echo "Input directory not found: $INPUT_DIR" >&2
  exit 2
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is required but not found in PATH." >&2
  exit 3
fi

IMAGE_CPU="removebg-onefile:cpu"
IMAGE_GPU="removebg-onefile:gpu"

IMAGE="$IMAGE_CPU"
DOCKER_RUN_ARGS=(
  --rm -i
  --user "${HOST_UID}:${HOST_GID}"
  -e "HOME=/tmp"
  -e "U2NET_HOME=/models"
)

if [[ "$USE_GPU_FLAG" == "1" ]]; then
  IMAGE="$IMAGE_GPU"
  DOCKER_RUN_ARGS+=(--gpus all)
fi

if [[ "$FIX_PERMS_FLAG" == "1" ]]; then
  echo "Fixing ownership in: $INPUT_DIR (uid=${HOST_UID} gid=${HOST_GID})" >&2
  docker run --rm \
    -v "$INPUT_DIR:/data" \
    alpine:3.19 \
    sh -lc "chown -R ${HOST_UID}:${HOST_GID} /data || true; chmod -R u+rwX /data || true" \
    >/dev/null 2>&1 || true
fi

if [[ "$REBUILD_FLAG" == "1" ]] || ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "Building Docker image: $IMAGE" >&2
  BUILD_CTX="$(mktemp -d)"
  cleanup() {
    rm -rf "$BUILD_CTX" 2>/dev/null || true
  }
  trap cleanup EXIT

  if [[ "$USE_GPU_FLAG" == "1" ]]; then
    docker build -t "$IMAGE" -f - "$BUILD_CTX" <<'DOCKER'
FROM nvidia/cuda:12.4.1-cudnn-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl bzip2 \
    libglib2.0-0 libgl1 \
  && rm -rf /var/lib/apt/lists/*

ENV MAMBA_ROOT_PREFIX=/opt/micromamba
RUN curl -Ls https://micro.mamba.pm/api/micromamba/linux-64/latest | tar -xvj bin/micromamba \
  && mv bin/micromamba /usr/local/bin/micromamba \
  && rm -rf bin

RUN micromamba create -y -n app -c conda-forge python=3.12 pip \
  && micromamba run -n app python -m pip install --no-cache-dir -U pip \
  && micromamba run -n app python -m pip install --no-cache-dir "rembg[gpu,cli]" Pillow \
  && apt-get update && apt-get install -y --no-install-recommends imagemagick \
  && rm -rf /var/lib/apt/lists/*

ENTRYPOINT ["micromamba", "run", "-n", "app"]
DOCKER
  else
    docker build -t "$IMAGE" -f - "$BUILD_CTX" <<'DOCKER'
FROM python:3.12-slim

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    bash \
    libglib2.0-0 \
    libgl1 \
    imagemagick \
  && rm -rf /var/lib/apt/lists/*

RUN python -m pip install --no-cache-dir -U pip \
  && python -m pip install --no-cache-dir "rembg[cpu,cli]" Pillow
DOCKER
  fi

  trap - EXIT
  cleanup
fi

docker run "${DOCKER_RUN_ARGS[@]}" \
  -v "$INPUT_DIR:/data" \
  -v "$HOME/.u2net:/models" \
  "$IMAGE" \
  bash -s -- "$WATCH_FLAG" "$INTERVAL_SEC" "$MIN_AGE_SEC" "$QUALITY" "$FORCE_FLAG" <<'BASH'
set -eo pipefail
shopt -s nullglob

WATCH_FLAG="$1"
INTERVAL_SEC="$2"
MIN_AGE_SEC="$3"
QUALITY="$4"
FORCE_FLAG="$5"

DIR="/data"
STATE_FILE="$DIR/.removebg_state.tsv"

touch "$STATE_FILE"

declare -A SEEN
while IFS=$'\t' read -r name mtime; do
  [[ -n "${name:-}" ]] || continue
  SEEN["$name"]="$mtime"
done < "$STATE_FILE"

save_state() {
  : > "$STATE_FILE.tmp"
  for k in "${!SEEN[@]}"; do
    printf '%s\t%s\n' "$k" "${SEEN[$k]}" >> "$STATE_FILE.tmp"
  done
  mv -f "$STATE_FILE.tmp" "$STATE_FILE"
}

is_stable() {
  local p="$1"
  local m
  m="$(stat -c %Y "$p" 2>/dev/null || true)"
  [[ -n "$m" ]] || return 1
  local now
  now="$(date +%s)"
  (( now - m >= MIN_AGE_SEC ))
}

process_one() {
  local src="$1"
  local base stem ext mtime key

  base="$(basename -- "$src")"
  key="$base"

  mtime="$(stat -c %Y "$src" 2>/dev/null || true)"
  [[ -n "$mtime" ]] || return 0

  if [[ "$FORCE_FLAG" != "1" && "${SEEN[$key]:-}" == "$mtime" ]]; then
    return 0
  fi

  # Skip the state file and temp artifacts
  if [[ "$base" == ".removebg_state.tsv" ]] || [[ "$base" == *.tmp ]] || [[ "$base" == .tmp_removebg_* ]]; then
    SEEN["$key"]="$mtime"
    return 0
  fi

  # Only files that are likely images
  ext="${base##*.}"
  ext="${ext,,}"
  case "$ext" in
    jpg|jpeg|png|webp|bmp|tif|tiff|gif|ppm) : ;;
    *)
      SEEN["$key"]="$mtime"
      return 0
      ;;
  esac

  if ! is_stable "$src"; then
    return 0
  fi

  stem="${base%.*}"
  local target="$DIR/$stem.jpg"
  local tmp_jpg="$DIR/.tmp_removebg_${stem}_$$.jpg"
  local tmp_png="$DIR/.tmp_removebg_${stem}_$$.png"
  local tmp_out="$DIR/.tmp_removebg_${stem}_$$.out.jpg"

  cleanup_tmps() {
    rm -f "$tmp_jpg" "$tmp_png" "$tmp_out" 2>/dev/null || true
  }

  # Convert/normalize to JPG (flatten alpha to white)
  if ! magick "$src" -auto-orient -background white -alpha remove -quality "$QUALITY" "$tmp_jpg"; then
    echo "[FAIL] $base (magick->jpg)" >&2
    cleanup_tmps
    return 1
  fi

  # Remove background (outputs PNG with alpha)
  local rembg_err
  rembg_err="$(rembg i "$tmp_jpg" "$tmp_png" 2>&1)" || {
    echo "[FAIL] $base (rembg)" >&2
    printf '%s\n' "$rembg_err" | tail -n 40 >&2
    cleanup_tmps
    return 1
  }
  if [[ ! -s "$tmp_png" ]]; then
    echo "[FAIL] $base (rembg produced empty output)" >&2
    cleanup_tmps
    return 1
  fi

  # Convert output PNG to final JPG (flatten on white)
  if ! magick "$tmp_png" -background white -alpha remove -quality "$QUALITY" "$tmp_out"; then
    echo "[FAIL] $base (magick png->jpg)" >&2
    cleanup_tmps
    return 1
  fi
  if [[ ! -s "$tmp_out" ]]; then
    echo "[FAIL] $base (magick produced empty output)" >&2
    cleanup_tmps
    return 1
  fi

  mv -f "$tmp_out" "$target"

  rm -f "$tmp_jpg" "$tmp_png" 2>/dev/null || true

  # Delete original if it wasn't already the target
  if command -v realpath >/dev/null 2>&1; then
    if [[ "$(realpath "$src")" != "$(realpath "$target")" ]]; then
      rm -f -- "$src" || true
    fi
  else
    if [[ "$src" != "$target" ]]; then
      rm -f -- "$src" || true
    fi
  fi

  # Update state for both names
  SEEN["$key"]="$mtime"
  SEEN["$(basename -- "$target")"]="$(stat -c %Y "$target" 2>/dev/null || echo 0)"

  echo "[OK] $base -> $(basename -- "$target") (replaced)"
}

echo "Folder:   $DIR"
echo "Mode:     in-place (replaces originals with .jpg)"
echo "Watch:    $WATCH_FLAG (interval=${INTERVAL_SEC}s)"
echo "Min age:  ${MIN_AGE_SEC}s"
echo "Quality:  $QUALITY"
echo "Force:    $FORCE_FLAG"

while true; do
  changed=0
  for f in "$DIR"/*; do
    [[ -f "$f" ]] || continue
    before_count="${#SEEN[@]}"
    if [[ "$WATCH_FLAG" == "0" ]]; then
      process_one "$f"
    else
      process_one "$f" || true
    fi
    after_count="${#SEEN[@]}"
    if [[ "$before_count" != "$after_count" ]]; then
      changed=1
    fi
  done

  save_state

  if [[ "$WATCH_FLAG" == "0" ]]; then
    exit 0
  fi
  sleep "$INTERVAL_SEC"
done
BASH
