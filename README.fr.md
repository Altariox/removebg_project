# removebg-batch-gpu

Outil batch qui :
1) convertit toutes les images d’un dossier en JPG
2) supprime l’arrière‑plan via **rembg** (U^2‑Net)
3) écrit un PNG **transparent** (format le plus utile après détourage)

## Entrée / Sortie
- Dossier entrée/sortie (par défaut) : `/home/altariox/Pictures/removebg`
- Comportement par défaut : remplacement in-place en `<entrée>/<nom>.jpg`

## Prérequis
- Docker (recommandé ; requis si Python 3.14 ne peut pas installer onnxruntime)
- GPU optionnel (NVIDIA) : Docker + `nvidia-container-toolkit` + pilotes CUDA

## Utilisation (recommandé, Docker)
```bash
cd /home/altariox/Documents/Code_projects/removebg_project
chmod +x run_removebg.sh

# CPU (par défaut)
./run_removebg.sh

# GPU (si dispo)
USE_GPU=1 ./run_removebg.sh

# Mode continu : scan toutes les 10 secondes
WATCH=1 INTERVAL=10 ./run_removebg.sh /home/altariox/Pictures/removebg

# One-shot
WATCH=0 ./run_removebg.sh /home/altariox/Pictures/removebg
```

## Notes
- Le script est un “one-file runner” (`run_removebg.sh`) : la logique Python est embarquée et exécutée dans Docker.

## Notes
- Le JPEG ne gère pas la transparence : les zones transparentes sont compositées sur blanc lors de la conversion.
- Les fichiers non‑images sont ignorés automatiquement.
