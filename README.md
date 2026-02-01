# removebg-batch-gpu

Batch tool to convert images to JPG and remove the background using AI (rembg), with optional GPU acceleration.

Quick start (CPU):

```bash
chmod +x run_removebg.sh
./run_removebg.sh /home/altariox/Pictures/removebg
```

Continuous mode (scan every 10s):

```bash
chmod +x watch_removebg.sh
./watch_removebg.sh /home/altariox/Pictures/removebg
```

By default the launcher runs in-place: it replaces originals with `<stem>.jpg`.

- English: [README.en.md](README.en.md)
- Français: [README.fr.md](README.fr.md)
- Español: [README.es.md](README.es.md)
