# removebg-batch-gpu

Outil batch qui :
1) convertit toutes les images d’un dossier en JPG
2) supprime l’arrière‑plan via **rembg** (U^2‑Net)
3) écrit un PNG **transparent** (format le plus utile après détourage)

## Entrée / Sortie
- Dossier d’entrée (par défaut) : `/home/altariox/Videos/removebg`
- Sortie JPG : `<entrée>/jpg/*.jpg`
- Sortie sans fond : `<entrée>/output/*_nobg.png`

## Prérequis
- Python 3
- Paquets : `Pillow`, `rembg`
- GPU optionnel (NVIDIA) : `onnxruntime-gpu` + CUDA correctement installé

## Utilisation (recommandé)
```bash
cd /home/altariox/Documents/Code_projects/removebg_project
chmod +x run_removebg.sh

# CPU (par défaut)
./run_removebg.sh

# GPU (si dispo)
USE_GPU=1 ./run_removebg.sh
```

## Utilisation (Python)
```bash
python3 removebg_batch.py --input-dir /home/altariox/Videos/removebg --skip-existing
# Tentative GPU (retombe sur CPU si indisponible)
python3 removebg_batch.py --input-dir /home/altariox/Videos/removebg --skip-existing --prefer-gpu
```

## Notes
- Le JPEG ne gère pas la transparence : les zones transparentes sont compositées sur blanc lors de la conversion.
- Les fichiers non‑images sont ignorés automatiquement.
