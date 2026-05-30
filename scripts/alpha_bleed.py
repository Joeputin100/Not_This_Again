#!/usr/bin/env python3
"""Alpha-bleed: extend a sprite's edge colors outward into its transparent
pixels, so mipmap/linear filtering can't bleed a foreign background color
(gray/green matte ghost) into the silhouette. Alpha is preserved exactly;
only the RGB of transparent pixels changes.

Usage: python3 scripts/alpha_bleed.py path1.png [path2.png ...] [--iters N]
"""
import sys
import numpy as np
from PIL import Image

paths = [a for a in sys.argv[1:] if not a.startswith("--")]
iters = 16
if "--iters" in sys.argv:
    iters = int(sys.argv[sys.argv.index("--iters") + 1])

for path in paths:
    im = Image.open(path).convert("RGBA")
    arr = np.asarray(im).astype(np.float32)
    rgb = arr[..., :3].copy()
    alpha = arr[..., 3].copy()
    filled = alpha > 16.0
    for _ in range(iters):
        if filled.all():
            break
        acc = np.zeros_like(rgb)
        cnt = np.zeros_like(alpha)
        f = filled.astype(np.float32)
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            acc += np.roll(np.roll(rgb * f[..., None], dy, 0), dx, 1)
            cnt += np.roll(np.roll(f, dy, 0), dx, 1)
        grow = (~filled) & (cnt > 0)
        rgb[grow] = acc[grow] / cnt[grow, None]
        filled = filled | grow
    out = np.dstack([rgb, alpha]).astype(np.uint8)
    Image.fromarray(out, "RGBA").save(path)
    print(f"bled {path}")
