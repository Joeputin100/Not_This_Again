#!/usr/bin/env python3
"""Blue-dominance key: subject shot over a flat blue plate -> true-alpha RGBA.

The discriminator is blue-DOMINANCE, d = B - max(R, G), not raw blue. That's
what lets a cyan/blue background key out while white highlights (B == R == G,
d ~= 0) and warm candy colors (gold/red, d < 0) survive untouched. A soft
alpha ramp feathers the edge, blue spill is pulled back toward max(R, G), and
the result is cropped to the subject's bounding box.

Usage: python3 scripts/blue_key.py in.png out.png [lo] [hi]
  lo/hi: dominance thresholds (default 14/46). d>=hi -> transparent, d<=lo -> opaque.
"""
import sys
import numpy as np
from PIL import Image

src = sys.argv[1]
out = sys.argv[2]
lo = float(sys.argv[3]) if len(sys.argv) > 3 else 14.0
hi = float(sys.argv[4]) if len(sys.argv) > 4 else 46.0

rgb = np.asarray(Image.open(src).convert("RGB")).astype(np.float32)
r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
# Blue dominance = blue-vs-red. Works for a pure-blue OR a cyan plate (both
# have B >> R), while white highlights (B ~= R) and warm candy (R > B) survive.
dom = b - r

alpha = np.clip((hi - dom) / (hi - lo), 0.0, 1.0)  # 1 opaque .. 0 keyed

# Despill: where the pixel leans blue, pull B down to max(R,G) so edges don't
# fringe cyan. Scaled by how keyed the pixel is.
spill = np.clip(dom / hi, 0.0, 1.0)
b2 = b - (b - np.maximum(r, g)) * spill
rgb_out = np.stack([r, g, b2], axis=-1)

rgba = np.dstack([rgb_out, alpha * 255.0]).astype(np.uint8)
img = Image.fromarray(rgba, "RGBA")

# Crop to content (alpha > ~10%).
ys, xs = np.where(alpha > 0.1)
if len(xs):
    pad = 6
    x0, x1 = max(0, xs.min() - pad), min(img.width, xs.max() + 1 + pad)
    y0, y1 = max(0, ys.min() - pad), min(img.height, ys.max() + 1 + pad)
    img = img.crop((x0, y0, x1, y1))

img.save(out)
print(f"wrote {out} {img.size} (keyed {(alpha < 0.5).mean() * 100:.0f}% of pixels)")
