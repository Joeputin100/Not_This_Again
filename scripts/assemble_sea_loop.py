#!/usr/bin/env python3
"""Assemble the baked Seascape frames into a seamless looping sprite-sheet for
the level-select orb water halo.

  in:  godot/.shader_render/frames/sea_000..071.png  (256^2 opaque water)
  out: godot/assets/sprites/props/sea_halo_sheet.png  (8x6 grid, 48 frames,
       each a soft round water disc with alpha, RGBA)

- crossfades render frames into a seamless L=48 loop (tail folds into head),
- masks each frame to a soft-edged disc (alpha) so it reads as a halo,
- packs into an 8x6 sheet; the game flips frames via StandardMaterial3D
  uv1_offset (no per-frame files, no runtime shader).

Seascape is CC BY-NC-SA (NonCommercial) → prototype asset; recreate before
any commercial release (see project memory).
"""
import math
import numpy as np
from PIL import Image
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "godot" / ".shader_render" / "frames"
OUT = ROOT / "godot" / "assets" / "sprites" / "props" / "sea_halo_sheet.png"
CELL = 160      # per-frame size in the sheet
L = 48          # loop length
C = 16          # crossfade length
COLS, ROWS = 8, 6   # 8*6 = 48

def load(i):
    return np.asarray(Image.open(SRC / ("sea_%03d.png" % i)).convert("RGB").resize((CELL, CELL), Image.LANCZOS)).astype(np.float32)

# soft-edged circular alpha mask (opaque interior, fade 0.66 -> 1.0 to 0)
yy, xx = np.mgrid[0:CELL, 0:CELL]
r = np.sqrt((xx - CELL / 2 + 0.5) ** 2 + (yy - CELL / 2 + 0.5) ** 2) / (CELL / 2)
mask = np.clip(1.0 - (r - 0.66) / (1.0 - 0.66), 0.0, 1.0)
mask = mask * mask  # smoother falloff

sheet = Image.new("RGBA", (COLS * CELL, ROWS * CELL), (0, 0, 0, 0))
for i in range(L):
    if i < C:
        w = i / float(C)
        rgb = load(L + i) * (1.0 - w) + load(i) * w   # fold the tail into the head
    else:
        rgb = load(i)
    rgb = np.clip(rgb * 1.12, 0, 255)  # slight brighten so it reads on the candy scene
    a = (mask * 255.0)
    cell = np.dstack([rgb, a]).astype(np.uint8)
    im = Image.fromarray(cell, "RGBA")
    col, row = i % COLS, i // COLS
    sheet.paste(im, (col * CELL, row * CELL))

OUT.parent.mkdir(parents=True, exist_ok=True)
sheet.save(OUT)
print("wrote", OUT, sheet.size, "(%d frames, %dx%d grid)" % (L, COLS, ROWS))
