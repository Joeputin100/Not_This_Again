# tools/winflow_assets.py — one-shot. Green-keys + autocrops the staged
# NB-Pro winflow renders into clean transparent game sprites.
#   python3 tools/winflow_assets.py
import numpy as np
from PIL import Image, ImageFilter
from pathlib import Path

SRC = Path("docs/superpowers/assets/winflow_2026-06-04")
DST = Path("godot/assets/sprites/ui/winflow"); DST.mkdir(parents=True, exist_ok=True)
# staged filename -> output sprite name
MAP = {
    "g_pepper": "star_pepper", "g_hard": "star_gold", "g_gummy": "star_gummy",
    "g_sugar": "star_sugar", "td_oval": "dish_oval",
    "heart_full": "heart_full", "heart_empty": "heart_empty",
    "cutout_taffy": "cutout_taffy",
}

def greenkey(src, low=12, high=46):
    a = np.array(Image.open(src).convert("RGBA")).astype(np.float32)
    R, G, B = a[:, :, 0], a[:, :, 1], a[:, :, 2]
    g = G - np.maximum(R, B)
    alpha = np.clip((high - g) / (high - low), 0, 1) * 255.0
    G2 = G - np.maximum(0, G - np.maximum(R, B)) * 0.9   # despill
    out = a.copy(); out[:, :, 1] = G2; out[:, :, 3] = alpha
    out = np.clip(out, 0, 255).astype(np.uint8)
    al = Image.fromarray(out[:, :, 3]).filter(ImageFilter.GaussianBlur(0.6))
    out[:, :, 3] = np.array(al)
    im = Image.fromarray(out); bb = im.getbbox()
    return im.crop(bb) if bb else im

for stem, name in MAP.items():
    src = SRC / f"{stem}.png"
    if not src.exists():
        raise SystemExit(f"missing staged asset: {src}")
    greenkey(src).save(DST / f"{name}.png")
    print("wrote", DST / f"{name}.png")
