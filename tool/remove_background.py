"""Remove the background from modifier (ek malzeme) photos.

Local, developer-only asset tool, not part of the Flutter app or its build.
It turns each input photo into a transparent PNG with rembg, so ingredient
photos sit cleanly on any card background.

Setup (once):
    python -m pip install rembg onnxruntime pillow

Usage:
    python tool/remove_background.py <input> [<input> ...] -o <output_dir>

    <input> is an image file or a folder (every .jpg/.jpeg/.png/.webp inside
    it is processed, not recursively). Each result is written to
    <output_dir>/<same name>.png. Inputs are never modified or overwritten.

Options:
    --model NAME     rembg model (default: isnet-general-use; alternatives:
                     u2net, birefnet-general). The first run downloads the
                     model (~170 MB) into ~/.u2net.
    --trim           Crop the transparent border, keeping --padding pixels.
    --padding N      Border kept around the subject when trimming (default 16).
    --max-size N     Downscale so the longer side is at most N pixels.
    --no-removal     Skip rembg (input is already transparent); only
                     --trim / --max-size are applied.
    --overwrite      Replace existing files in <output_dir>.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image
from rembg import new_session, remove

IMAGE_SUFFIXES = {".jpg", ".jpeg", ".png", ".webp"}


def collect_inputs(paths: list[str]) -> list[Path]:
    files: list[Path] = []
    for raw in paths:
        path = Path(raw)
        if path.is_dir():
            files.extend(
                sorted(
                    p
                    for p in path.iterdir()
                    if p.is_file() and p.suffix.lower() in IMAGE_SUFFIXES
                )
            )
        elif path.is_file() and path.suffix.lower() in IMAGE_SUFFIXES:
            files.append(path)
        else:
            print(f"Atlandi (desteklenmeyen ya da bulunamadi): {path}", file=sys.stderr)
    return files


TRIM_ALPHA_THRESHOLD = 16


def trim_transparent(image: Image.Image, padding: int) -> Image.Image:
    # Near-invisible shadow pixels (alpha just above 0) would otherwise keep
    # the bounding box at the full canvas, so they don't count as subject.
    alpha = image.getchannel("A").point(
        lambda value: 255 if value > TRIM_ALPHA_THRESHOLD else 0
    )
    bbox = alpha.getbbox()
    if bbox is None:
        return image
    left, top, right, bottom = bbox
    return image.crop(
        (
            max(left - padding, 0),
            max(top - padding, 0),
            min(right + padding, image.width),
            min(bottom + padding, image.height),
        )
    )


def process(
    source: Path,
    target: Path,
    session,
    trim: bool,
    padding: int,
    max_size: int | None,
) -> None:
    with Image.open(source) as original:
        rgba = original.convert("RGBA")
        result = rgba if session is None else remove(rgba, session=session)
    if trim:
        result = trim_transparent(result, padding)
    if max_size and max(result.size) > max_size:
        result.thumbnail((max_size, max_size), Image.Resampling.LANCZOS)
    result.save(target, format="PNG", optimize=True)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Ek malzeme fotograflarinin arka planini seffaf PNG'ye cevirir."
    )
    parser.add_argument("inputs", nargs="+", help="Gorsel dosyalari veya klasorler")
    parser.add_argument("-o", "--output", required=True, help="Cikti klasoru")
    parser.add_argument("--model", default="isnet-general-use")
    parser.add_argument("--trim", action="store_true")
    parser.add_argument("--padding", type=int, default=16)
    parser.add_argument("--max-size", type=int, default=None)
    parser.add_argument("--overwrite", action="store_true")
    parser.add_argument("--no-removal", action="store_true")
    args = parser.parse_args()

    files = collect_inputs(args.inputs)
    if not files:
        print("Islenecek gorsel bulunamadi.", file=sys.stderr)
        return 1

    output_dir = Path(args.output)
    output_dir.mkdir(parents=True, exist_ok=True)
    session = None if args.no_removal else new_session(args.model)

    failures = 0
    for source in files:
        target = output_dir / f"{source.stem}.png"
        if target.resolve() == source.resolve():
            print(f"Atlandi (girdi uzerine yazilmaz): {source}", file=sys.stderr)
            failures += 1
            continue
        if target.exists() and not args.overwrite:
            print(f"Atlandi (zaten var, --overwrite kullanin): {target}", file=sys.stderr)
            continue
        try:
            process(source, target, session, args.trim, args.padding, args.max_size)
            print(f"OK  {source.name} -> {target}")
        except Exception as error:  # keep going for the rest of the batch
            failures += 1
            print(f"HATA {source.name}: {error}", file=sys.stderr)

    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
