#!/usr/bin/env python3
"""Chroma-key a subject shot over a flat green or magenta plate -> true-alpha RGBA.

Keys on channel DOMINANCE (not raw brightness) so white highlights and the
candy orbs' blue snow-globe domes survive:
  green key:   dom = G - max(R, B)   (use for non-green subjects)
  magenta key: dom = min(R, B) - G   (use for green subjects, e.g. the jellybean orb)
A soft alpha ramp feathers the edge, spill is pulled back toward the kept
channels, and the result is cropped to the subject bbox.

Usage: python3 scripts/chroma_key.py in.png out.png green|magenta [lo] [hi]
"""
import sys
import numpy as np
from PIL import Image

src, out, key = sys.argv[1], sys.argv[2], sys.argv[3]
lo = float(sys.argv[4]) if len(sys.argv) > 4 else 30.0
hi = float(sys.argv[5]) if len(sys.argv) > 5 else 75.0

rgb = np.asarray(Image.open(src).convert("RGB")).astype(np.float32)
r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
if key == "green":
    dom = g - np.maximum(r, b)
elif key == "magenta":
    dom = np.minimum(r, b) - g
else:
    sys.exit("key must be 'green' or 'magenta'")

alpha = np.clip((hi - dom) / (hi - lo), 0.0, 1.0)  # 1 opaque .. 0 keyed
# Despill: pull the keyed channel back toward the others on partly-keyed pixels.
spill = np.clip(dom / hi, 0.0, 1.0)
if key == "green":
    g = g - (g - np.maximum(r, b)) * spill
else:
    avg = (r + b) * 0.5
    r = r - (r - g) * spill * (r > g)
    b = b - (b - g) * spill * (b > g)
rgba = np.dstack([r, g, b, alpha * 255.0]).astype(np.uint8)
img = Image.fromarray(rgba, "RGBA")

ys, xs = np.where(alpha > 0.1)
if len(xs):
    pad = 6
    img = img.crop((max(0, xs.min() - pad), max(0, ys.min() - pad),
                    min(img.width, xs.max() + 1 + pad), min(img.height, ys.max() + 1 + pad)))
img.save(out)
print(f"wrote {out} {img.size} (keyed {(alpha < 0.5).mean() * 100:.0f}%)")
