#!/usr/bin/env python3
"""Remove a baked-in transparency checkerboard (and any soft drop-shadow)
from a PNG by alpha-keying the connected, low-saturation background.

The checkerboard squares and a grey drop-shadow are all near-grey — very
low HSV saturation — while the subject art is colored. We mark low-sat
pixels as candidates, label connected components, and zero the alpha of
the component(s) that touch the image border. A stray grey pixel walled
in by colored subject forms its own non-border component, so it is kept.

Usage: python3 tools/decheckerboard.py <in.png> <out.png> [sat_threshold]
"""
import sys

import numpy as np
from PIL import Image
from scipy import ndimage


def main() -> None:
    src, dst = sys.argv[1], sys.argv[2]
    thr = float(sys.argv[3]) if len(sys.argv) > 3 else 0.13
    im = Image.open(src).convert("RGBA")
    arr = np.asarray(im).astype(np.float32)
    rgb = arr[:, :, :3]
    alpha = arr[:, :, 3]
    mx = rgb.max(axis=2)
    mn = rgb.min(axis=2)
    sat = np.where(mx > 1.0, (mx - mn) / np.maximum(mx, 1.0), 0.0)

    candidate = (sat < thr) | (alpha < 8.0)
    labels = ndimage.label(candidate)[0]
    border = np.concatenate(
        [labels[0, :], labels[-1, :], labels[:, 0], labels[:, -1]])
    bg_labels = sorted(set(np.unique(border)) - {0})
    bg_mask = np.isin(labels, bg_labels)

    out = arr.copy()
    out[:, :, 3] = np.where(bg_mask, 0.0, alpha)
    Image.fromarray(out.astype(np.uint8), "RGBA").save(dst)
    keyed = int(bg_mask.sum())
    print("decheckerboard %s -> %s : keyed %d px (%.1f%%), thr=%.2f"
          % (src, dst, keyed, 100.0 * keyed / bg_mask.size, thr))


if __name__ == "__main__":
    main()
