"""
Green-screen chromakey for NB2 output.
- Detect green by HSV-style channel dominance (G high, R low, B low)
- Set alpha=0 on green pixels
- Despill: reduce green in edge pixels where G > max(R, B) by spill amount,
  clamped to 60 so we don't grey out genuine bright candy yellows
- 1px alpha-feather on the boundary to soften edges
"""
import sys
from PIL import Image
import numpy as np

inp = sys.argv[1]
out = sys.argv[2]

arr = np.array(Image.open(inp).convert("RGBA"))
r = arr[..., 0].astype(np.int16)
g = arr[..., 1].astype(np.int16)
b = arr[..., 2].astype(np.int16)
a = arr[..., 3]

# Green-screen mask: high green, low red+blue
is_green = (g > 180) & (g - r > 50) & (g - b > 50)
print(f"green pixels: {is_green.sum()} / {is_green.size} ({100*is_green.sum()/is_green.size:.1f}%)")
a[is_green] = 0

# Despill: anywhere green is still dominant but pixel is opaque,
# pull green down to max(red, blue) to remove green halo on edges.
opaque = a > 0
spillable = opaque & (g > r) & (g > b)
spill = np.minimum(g - np.maximum(r, b), 60)
new_g = g.copy()
new_g[spillable] = (g[spillable] - spill[spillable])
arr[..., 1] = np.clip(new_g, 0, 255).astype(np.uint8)
print(f"despilled: {spillable.sum()} pixels")

# 1px feather: opaque pixels with any transparent 8-neighbor → 50% alpha
from scipy.ndimage import binary_dilation
transparent = a == 0
boundary = binary_dilation(transparent) & opaque
arr[..., 3][boundary] = 128
print(f"feathered: {boundary.sum()} pixels")

Image.fromarray(arr).save(out, "PNG")
print(f"saved {out}: {arr.shape}")
