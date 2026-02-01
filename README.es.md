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
- Python 3
- Paquetes: `Pillow`, `rembg`
- GPU opcional (NVIDIA): `onnxruntime-gpu` + CUDA correctamente instalado

## Uso (recomendado)
```bash
cd /home/altariox/Documents/Code_projects/removebg_project
chmod +x run_removebg.sh

# CPU (por defecto)
./run_removebg.sh

# GPU (si está disponible)
USE_GPU=1 ./run_removebg.sh
```

## Uso (Python)
```bash
python3 removebg_batch.py --input-dir /home/altariox/Videos/removebg --skip-existing
# Intentar GPU (si no, usa CPU)
python3 removebg_batch.py --input-dir /home/altariox/Videos/removebg --skip-existing --prefer-gpu
```

## Notas
- JPEG no tiene transparencia; al convertir, las zonas transparentes se componen sobre blanco.
- El script ignora automáticamente los archivos que no son imágenes.
