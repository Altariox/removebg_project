#!/usr/bin/env python3
"""Batch: convert images to JPG, then remove background (GPU if available).

Default behavior:
- Input:  /home/altariox/Videos/removebg
- Writes JPGs to: <input>/jpg
- Writes background-removed images to: <input>/output (PNG with alpha by default)

Notes:
- If GPU provider isn't available, it falls back to CPU automatically.
- Output PNG is the most useful format for transparency.
"""

from __future__ import annotations

import argparse
import os
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from io import BytesIO

from PIL import Image, ImageOps


def _eprint(*args: object) -> None:
    print(*args, file=sys.stderr)


@dataclass(frozen=True)
class Paths:
    input_dir: Path
    jpg_dir: Path
    output_dir: Path


IMAGE_EXTS = {
    ".png",
    ".jpg",
    ".jpeg",
    ".webp",
    ".bmp",
    ".tif",
    ".tiff",
    ".gif",
}


def is_probably_image(path: Path) -> bool:
    if not path.is_file():
        return False
    if path.suffix.lower() in IMAGE_EXTS:
        return True
    # Fallback: try opening via PIL for files without extension
    try:
        with Image.open(path) as im:
            im.verify()
        return True
    except Exception:
        return False


def convert_to_jpg(input_path: Path, jpg_path: Path, quality: int = 95) -> None:
    jpg_path.parent.mkdir(parents=True, exist_ok=True)

    with Image.open(input_path) as im:
        im = ImageOps.exif_transpose(im)

        # JPEG cannot store alpha; composite on white when needed
        if im.mode in ("RGBA", "LA") or (im.mode == "P" and "transparency" in im.info):
            rgba = im.convert("RGBA")
            background = Image.new("RGBA", rgba.size, (255, 255, 255, 255))
            im = Image.alpha_composite(background, rgba).convert("RGB")
        else:
            im = im.convert("RGB")

        im.save(jpg_path, format="JPEG", quality=quality, optimize=True)


def _png_bytes_to_jpg_bytes(png_bytes: bytes, quality: int = 95) -> bytes:
    with Image.open(BytesIO(png_bytes)) as im:
        im = ImageOps.exif_transpose(im)

        if im.mode not in ("RGBA", "LA"):
            im = im.convert("RGBA")

        background = Image.new("RGBA", im.size, (255, 255, 255, 255))
        rgb = Image.alpha_composite(background, im).convert("RGB")

        out = BytesIO()
        rgb.save(out, format="JPEG", quality=quality, optimize=True)
        return out.getvalue()


def _create_rembg_session(prefer_gpu: bool):
    # rembg uses onnxruntime under the hood; providers are passed to new_session.
    try:
        from rembg import new_session  # type: ignore[import-not-found]
    except Exception as e:
        raise RuntimeError(
            "rembg backend is not available in this Python environment. "
            "On many systems Python 3.14 cannot install onnxruntime yet. "
            "Use the Docker launcher: ./run_removebg.sh"
        ) from e

    if not prefer_gpu:
        return new_session("u2net", providers=["CPUExecutionProvider"])

    # Try GPU first; if not available on the machine, onnxruntime will error and we fallback.
    try:
        return new_session("u2net", providers=["CUDAExecutionProvider", "CPUExecutionProvider"])
    except Exception as e:
        _eprint(f"[WARN] GPU session init failed, falling back to CPU: {e}")
        return new_session("u2net", providers=["CPUExecutionProvider"])


def remove_background(jpg_path: Path, out_path: Path, prefer_gpu: bool) -> None:
    out_path.parent.mkdir(parents=True, exist_ok=True)

    try:
        from rembg import remove  # type: ignore[import-not-found]
    except Exception as e:
        raise RuntimeError(
            "rembg backend is not available in this Python environment. "
            "Use the Docker launcher: ./run_removebg.sh"
        ) from e

    session = _create_rembg_session(prefer_gpu=prefer_gpu)
    data = jpg_path.read_bytes()
    result = remove(data, session=session)
    out_path.write_bytes(result)


def remove_background_to_jpg_bytes(jpg_path: Path, prefer_gpu: bool, quality: int) -> bytes:
    from rembg import remove  # type: ignore[import-not-found]

    session = _create_rembg_session(prefer_gpu=prefer_gpu)
    data = jpg_path.read_bytes()
    png_bytes = remove(data, session=session)
    return _png_bytes_to_jpg_bytes(png_bytes, quality=quality)


def atomic_write(path: Path, data: bytes) -> None:
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_bytes(data)
    os.replace(tmp, path)


def main() -> int:
    parser = argparse.ArgumentParser(description="Convert images to JPG then remove background (GPU if available).")
    parser.add_argument(
        "--input-dir",
        default="/home/altariox/Videos/removebg",
        help="Folder containing files to process",
    )
    parser.add_argument(
        "--jpg-dir",
        default=None,
        help="Where to write converted JPGs (default: <input>/jpg)",
    )
    parser.add_argument(
        "--output-dir",
        default=None,
        help="Where to write background-removed outputs (default: <input>/output)",
    )
    parser.add_argument("--quality", type=int, default=95, help="JPEG quality (default: 95)")
    parser.add_argument(
        "--prefer-gpu",
        action="store_true",
        help="Try to use GPU (requires onnxruntime-gpu + CUDA). Falls back to CPU automatically.",
    )
    parser.add_argument(
        "--skip-existing",
        action="store_true",
        help="Skip files that already have outputs",
    )
    parser.add_argument(
        "--inplace-jpg",
        action="store_true",
        help=(
            "Replace originals in the input folder. Always writes <stem>.jpg with background removed "
            "and deletes the original if it had a different extension."
        ),
    )
    parser.add_argument(
        "--watch",
        action="store_true",
        help="Continuously scan the folder for new images.",
    )
    parser.add_argument(
        "--interval",
        type=float,
        default=10.0,
        help="Watch mode scan interval in seconds (default: 10).",
    )
    parser.add_argument(
        "--min-age",
        type=float,
        default=2.0,
        help="Skip files modified within the last N seconds to avoid partial writes (default: 2).",
    )

    args = parser.parse_args()

    input_dir = Path(args.input_dir).expanduser().resolve()
    if not input_dir.exists() or not input_dir.is_dir():
        _eprint(f"Input dir not found or not a directory: {input_dir}")
        return 2

    jpg_dir = Path(args.jpg_dir).expanduser().resolve() if args.jpg_dir else (input_dir / "jpg")
    output_dir = Path(args.output_dir).expanduser().resolve() if args.output_dir else (input_dir / "output")

    paths = Paths(input_dir=input_dir, jpg_dir=jpg_dir, output_dir=output_dir)

    def is_stable_file(path: Path) -> bool:
        try:
            st = path.stat()
        except FileNotFoundError:
            return False
        return (time.time() - st.st_mtime) >= float(args.min_age)

    def iter_candidate_files() -> list[Path]:
        # Avoid re-processing generated folders if they live under input.
        ignore_dirs = {paths.jpg_dir.resolve(), paths.output_dir.resolve()}
        out: list[Path] = []
        for p in paths.input_dir.iterdir():
            if not p.is_file():
                continue
            parent = p.parent.resolve()
            if parent in ignore_dirs:
                continue
            out.append(p)
        return sorted(out)

    processed = 0
    skipped = 0
    errors = 0

    # Fast info for user
    print(f"Input:  {paths.input_dir}")
    if args.inplace_jpg:
        print("Output: in-place (overwrite originals with .jpg)")
    else:
        print(f"JPG:    {paths.jpg_dir}")
        print(f"Output: {paths.output_dir} (PNG transparent)")
    print(f"GPU:    {'requested' if args.prefer_gpu else 'not requested'}")
    if args.watch:
        print(f"Watch:  enabled (interval={args.interval}s, min_age={args.min_age}s)")

    # In-memory state to avoid reprocessing the same files repeatedly in watch mode.
    seen: dict[Path, float] = {}

    def process_once() -> tuple[int, int, int]:
        nonlocal processed, skipped, errors

        files = iter_candidate_files()
        if not files and not args.watch:
            print(f"No files found in {paths.input_dir}")
            return processed, skipped, errors

        for src in files:
            if not is_stable_file(src):
                skipped += 1
                continue

            if not is_probably_image(src):
                skipped += 1
                continue

            stem = src.stem

            # In-place mode: always produce <input>/<stem>.jpg and replace/delete originals.
            if args.inplace_jpg:
                target_jpg = paths.input_dir / f"{stem}.jpg"

                # Skip if we've already processed this file in this run
                last = seen.get(src)
                try:
                    now_mtime = src.stat().st_mtime
                except FileNotFoundError:
                    skipped += 1
                    continue
                if last is not None and now_mtime <= last:
                    skipped += 1
                    continue

                try:
                    # Create/refresh the JPG used for background removal.
                    # If source already is the target jpg, this overwrites it (normalization step).
                    convert_to_jpg(src, target_jpg, quality=args.quality)
                except Exception as e:
                    errors += 1
                    _eprint(f"[ERR] JPG conversion failed for {src.name}: {e}")
                    continue

                try:
                    jpg_bytes = remove_background_to_jpg_bytes(
                        target_jpg, prefer_gpu=args.prefer_gpu, quality=args.quality
                    )
                    atomic_write(target_jpg, jpg_bytes)
                except Exception as e:
                    errors += 1
                    _eprint(f"[ERR] Background removal failed for {target_jpg.name}: {e}")
                    continue

                # If original wasn't the jpg target, delete the original file.
                if src.resolve() != target_jpg.resolve():
                    try:
                        src.unlink(missing_ok=True)
                    except Exception as e:
                        _eprint(f"[WARN] Could not delete original {src.name}: {e}")

                try:
                    seen[target_jpg] = target_jpg.stat().st_mtime
                except Exception:
                    pass
                seen[src] = now_mtime

                processed += 1
                print(f"[OK] {src.name} -> {target_jpg.name} (replaced)")
                continue

            # Classic mode (separate folders)
            jpg_path = paths.jpg_dir / f"{stem}.jpg"
            out_path = paths.output_dir / f"{stem}_nobg.png"

            if args.skip_existing and out_path.exists() and jpg_path.exists():
                skipped += 1
                continue

            try:
                convert_to_jpg(src, jpg_path, quality=args.quality)
            except Exception as e:
                errors += 1
                _eprint(f"[ERR] JPG conversion failed for {src.name}: {e}")
                continue

            try:
                remove_background(jpg_path, out_path, prefer_gpu=args.prefer_gpu)
            except Exception as e:
                errors += 1
                _eprint(f"[ERR] Background removal failed for {jpg_path.name}: {e}")
                continue

            processed += 1
            print(f"[OK] {src.name} -> {jpg_path.name} -> {out_path.name}")

        return processed, skipped, errors

    if not args.watch:
        process_once()
        print(f"Done. processed={processed} skipped={skipped} errors={errors}")
        return 0 if errors == 0 else 1

    # Watch loop
    while True:
        process_once()
        time.sleep(float(args.interval))


if __name__ == "__main__":
    raise SystemExit(main())
