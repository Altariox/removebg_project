# removebg-batch-gpu

Batch tool to convert images to JPG and remove the background using AI (rembg), with optional GPU acceleration.

Quick start (CPU):

```bash
chmod +x run_removebg.sh
./run_removebg.sh /home/altariox/Pictures/removebg
```

Continuous mode (scan every 10s, default):

```bash
WATCH=1 INTERVAL=10 ./run_removebg.sh /home/altariox/Pictures/removebg
```

By default the launcher runs in-place: it replaces originals with `<stem>.jpg`.

One-shot mode:

```bash
WATCH=0 ./run_removebg.sh /home/altariox/Pictures/removebg
```

- English: [README.en.md](README.en.md)
- Français: [README.fr.md](README.fr.md)
- Español: [README.es.md](README.es.md)
