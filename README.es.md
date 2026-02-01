# removebg-batch-gpu

Herramienta por lotes que:
1) convierte todas las imágenes de una carpeta a JPG
2) elimina el fondo con **rembg** (U^2‑Net)
3) guarda un PNG **transparente** (el formato más útil para recortes)

## Entrada / Salida
- Carpeta de entrada (por defecto): `/home/altariox/Videos/removebg`
- Salida JPG: `<entrada>/jpg/*.jpg`
- Salida sin fondo: `<entrada>/output/*_nobg.png`

## Requisitos
- Docker (recomendado; obligatorio si Python 3.14 no puede instalar onnxruntime)
- GPU opcional (NVIDIA): Docker + `nvidia-container-toolkit` + drivers CUDA

## Uso (recomendado, Docker)
```bash
cd /home/altariox/Documents/Code_projects/removebg_project
chmod +x run_removebg.sh

# CPU (por defecto)
./run_removebg.sh

# GPU (si está disponible)
USE_GPU=1 ./run_removebg.sh

# Modo continuo: escanear cada 10 segundos
WATCH=1 INTERVAL=10 ./run_removebg.sh /home/altariox/Videos/removebg
```

## Uso (Python)
Requiere una versión de Python compatible (normalmente 3.10–3.13) y el backend CPU/GPU.

```bash
pip install "rembg[cpu]" Pillow
python3 removebg_batch.py --input-dir /home/altariox/Videos/removebg --skip-existing
# Intentar GPU (si no, usa CPU)
python3 removebg_batch.py --input-dir /home/altariox/Videos/removebg --skip-existing --prefer-gpu
```

## Notas
- JPEG no tiene transparencia; al convertir, las zonas transparentes se componen sobre blanco.
- El script ignora automáticamente los archivos que no son imágenes.
