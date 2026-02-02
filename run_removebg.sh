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

# Performance throttling (lower impact on your PC; slower processing).
CPU_LIMIT="${CPU_LIMIT:-0.5}"         # Docker CPU quota, e.g. 0.5, 1, 2. Use 0 to disable.
CPU_SHARES="${CPU_SHARES:-128}"       # Relative CPU weight (1024 is default).
THREADS="${THREADS:-1}"               # Limit threads used by numpy/onnx/imagemagick.
INITIAL_SCAN="${INITIAL_SCAN:-1}"     # 1=process existing files on start, 0=only new/changed.

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
  -e "OMP_NUM_THREADS=${THREADS}"
  -e "OPENBLAS_NUM_THREADS=${THREADS}"
  -e "MKL_NUM_THREADS=${THREADS}"
  -e "NUMEXPR_NUM_THREADS=${THREADS}"
  -e "MAGICK_THREAD_LIMIT=${THREADS}"
  -e "INITIAL_SCAN=${INITIAL_SCAN}"
)

if [[ "${CPU_LIMIT}" != "0" && -n "${CPU_LIMIT}" ]]; then
  DOCKER_RUN_ARGS+=(--cpus "${CPU_LIMIT}")
fi
if [[ -n "${CPU_SHARES}" ]]; then
  DOCKER_RUN_ARGS+=(--cpu-shares "${CPU_SHARES}")
fi

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
LAST_SCAN_FILE="$DIR/.removebg_last_scan"

read_last_scan() {
  if [[ -f "$LAST_SCAN_FILE" ]]; then
    cat "$LAST_SCAN_FILE" 2>/dev/null || echo 0
  else
    echo 0
  fi
}

write_last_scan() {
  printf '%s\n' "$1" > "$LAST_SCAN_FILE" 2>/dev/null || true
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
  local src_mtime_raw="$2"
  local base stem ext mtime key

  base="$(basename -- "$src")"
  mtime="${src_mtime_raw%.*}"
  [[ -n "$mtime" ]] || mtime="$(stat -c %Y "$src" 2>/dev/null || true)"
  [[ -n "$mtime" ]] || return 0

  # Skip the state file and temp artifacts
  if [[ "$base" == ".removebg_state.tsv" ]] || [[ "$base" == ".removebg_last_scan" ]] || [[ "$base" == *.tmp ]] || [[ "$base" == .tmp_removebg_* ]]; then
    return 0
  fi

  # Only files that are likely images
  ext="${base##*.}"
  ext="${ext,,}"
  case "$ext" in
    jpg|jpeg|png|webp|bmp|tif|tiff|gif|ppm) : ;;
    *)
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

  # Preserve original mtime so the watcher doesn't reprocess the same file.
  touch -d "@${mtime}" "$target" 2>/dev/null || true

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

  echo "[OK] $base -> $(basename -- "$target") (replaced)"
}

echo "Folder:   $DIR"
echo "Mode:     in-place (replaces originals with .jpg)"
echo "Watch:    $WATCH_FLAG (interval=${INTERVAL_SEC}s)"
echo "Min age:  ${MIN_AGE_SEC}s"
echo "Quality:  $QUALITY"
echo "Force:    $FORCE_FLAG"

last_scan="$(read_last_scan)"
if [[ "$WATCH_FLAG" != "0" && "$INITIAL_SCAN" == "0" && "$last_scan" == "0" ]]; then
  last_scan="$(date +%s)"
  write_last_scan "$last_scan"
fi

while true; do
  now="$(date +%s)"

  # In one-shot mode, we process all candidate files.
  # In watch mode, we only consider files modified since last_scan.
  cutoff="0"
  if [[ "$WATCH_FLAG" != "0" && "$FORCE_FLAG" != "1" ]]; then
    cutoff="$last_scan"
  fi

  if [[ "$cutoff" == "0" ]]; then
    while IFS= read -r -d '' p && IFS= read -r -d '' mt; do
      if [[ "$WATCH_FLAG" == "0" ]]; then
        process_one "$p" "$mt"
      else
        process_one "$p" "$mt" || true
      fi
    done < <(find "$DIR" -maxdepth 1 -type f -print0 -printf '%p\0%T@\0')
  else
    while IFS= read -r -d '' p && IFS= read -r -d '' mt; do
      if [[ "$WATCH_FLAG" == "0" ]]; then
        process_one "$p" "$mt"
      else
        process_one "$p" "$mt" || true
      fi
    done < <(find "$DIR" -maxdepth 1 -type f -newermt "@${cutoff}" -print0 -printf '%p\0%T@\0')
  fi

  if [[ "$WATCH_FLAG" != "0" ]]; then
    last_scan="$now"
    write_last_scan "$last_scan"
  fi

  if [[ "$WATCH_FLAG" == "0" ]]; then
    exit 0
  fi
  sleep "$INTERVAL_SEC"
done
BASH
