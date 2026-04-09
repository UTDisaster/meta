#!/usr/bin/env python3
"""
Convert xBD geotiff Hurricane Florence images (int16 RGB) to PNG (uint8 RGB).

The xBD geotiff archive ships .tif files but the corresponding label JSONs
reference .png filenames. This script bridges the gap so the backend's
parse_step.py can find each pair.

Usage:
    python convert_tif_to_png.py [--src-dir DIR]

Default --src-dir: ./florence_complete/images
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
import tifffile
from PIL import Image


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--src-dir",
        default="./florence_complete/images",
        help="Directory containing hurricane-florence_*.tif files",
    )
    args = parser.parse_args()

    src_dir = Path(args.src_dir).resolve()
    if not src_dir.is_dir():
        print(f"ERROR: not a directory: {src_dir}", file=sys.stderr)
        return 1

    tif_files = sorted(src_dir.glob("hurricane-florence_*.tif"))
    total = len(tif_files)
    if total == 0:
        print("No TIFs to convert")
        return 0

    print(f"Converting {total} TIF files in {src_dir}")
    failed: list[tuple[Path, str]] = []
    for i, tif_path in enumerate(tif_files, 1):
        png_path = tif_path.with_suffix(".png")
        try:
            arr = tifffile.imread(tif_path)
            arr_u8 = np.clip(arr, 0, 255).astype(np.uint8)
            Image.fromarray(arr_u8, mode="RGB").save(png_path, optimize=False)
            tif_path.unlink()
        except Exception as exc:
            failed.append((tif_path, str(exc)))
        if i % 50 == 0 or i == total:
            print(f"  [{i}/{total}] last: {tif_path.name}", flush=True)

    print(f"\nDONE. converted={total - len(failed)}, failed={len(failed)}")
    if failed:
        print("FAILED:")
        for p, msg in failed[:10]:
            print(f"  {p.name}: {msg}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
