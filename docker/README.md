# Docker

This project runs best via Docker because the host Python is 3.14 and `onnxruntime` wheels may not be available.

- CPU image: built from `docker/Dockerfile.cpu`
- GPU image: built from `docker/Dockerfile.gpu` (requires NVIDIA + `nvidia-container-toolkit`)

Build examples:

```bash
docker build -f docker/Dockerfile.cpu -t removebg-batch-gpu:cpu .

docker build -f docker/Dockerfile.gpu -t removebg-batch-gpu:gpu .
```
