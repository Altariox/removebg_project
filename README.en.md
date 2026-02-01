# removebg-batch-gpu

Batch tool that:
1) converts all images in a folder to JPG
2) removes the background using **rembg** (U^2-Net)
3) writes a transparent **PNG** output (best format for cut-outs)

## Input / Output
- Input folder (default): `/home/altariox/Videos/removebg`
- JPG output: `<input>/jpg/*.jpg`
- No-background output: `<input>/output/*_nobg.png`

## Requirements
- Docker (recommended; required on hosts where Python 3.14 cannot install onnxruntime)
- Optional GPU (NVIDIA): Docker + `nvidia-container-toolkit` + CUDA drivers

## Usage (recommended, Docker)
```bash
cd /home/altariox/Documents/Code_projects/removebg_project
chmod +x run_removebg.sh

# CPU (default)
./run_removebg.sh

# GPU (if available)
USE_GPU=1 ./run_removebg.sh
```

## Usage (Python directly)
This requires a supported Python version (typically 3.10–3.13) and the CPU/GPU backend.

```bash
pip install "rembg[cpu]" Pillow
python3 removebg_batch.py --input-dir /home/altariox/Videos/removebg --skip-existing
# GPU try (falls back to CPU)
python3 removebg_batch.py --input-dir /home/altariox/Videos/removebg --skip-existing --prefer-gpu
```

## Notes
- JPEG has no transparency; during conversion, transparent areas are composited on white.
- The script skips non-image files automatically.
