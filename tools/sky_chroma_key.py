#!/usr/bin/env python3
"""Chroma-key the magenta/pink Imagen background to alpha=0.

Vectorized — detects pink (R > 150, B > 110, G < 130) and sets those
pixels' alpha to 0, also zeros their RGB so half-transparent edges
don't carry pink tint.

Usage:
  python3 tools/sky_chroma_key.py godot/assets/sprites/sky/sun_daylight_raw.png \
                                  godot/assets/sprites/sky/sun_daylight.png
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

D_OPAQUE = 90   # color distance above which pixel is fully opaque (kept)
D_TRANSPARENT = 20  # color distance below which pixel is fully transparent (background)


def key(in_path: Path, out_path: Path) -> None:
    arr = np.array(Image.open(in_path).convert("RGBA"))
    h, w = arr.shape[:2]
    corners = np.stack([
        arr[10, 10, :3], arr[10, w - 11, :3],
        arr[h - 11, 10, :3], arr[h - 11, w - 11, :3],
    ]).astype(np.int16)
    bg = np.median(corners, axis=0).astype(np.int16)
    rgb = arr[..., :3].astype(np.int16)
    # Euclidean color distance — smoother than max-channel for halos.
    dist = np.sqrt(np.sum((rgb - bg) ** 2, axis=-1))
    # Smooth ramp 0..255: transparent below D_TRANSPARENT, opaque above D_OPAQUE.
    alpha = np.clip((dist - D_TRANSPARENT) / (D_OPAQUE - D_TRANSPARENT), 0.0, 1.0) * 255.0
    arr[..., 3] = alpha.astype(np.uint8)
    # Zero RGB where alpha is 0 so half-transparent edges don't carry bg tint.
    mask_zero = arr[..., 3] == 0
    arr[mask_zero, :3] = 0
    Image.fromarray(arr).save(out_path)
    print(f"{in_path.name} -> {out_path.name}: bg={tuple(bg.tolist())} ({int(mask_zero.sum())} fully transparent)")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("usage: sky_chroma_key.py <in> <out>")
    key(Path(sys.argv[1]), Path(sys.argv[2]))
