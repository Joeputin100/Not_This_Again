# tools/kimmy_assets.py — one-shot. Green-keys the staged kimmy art into sprites.
#   python3 tools/kimmy_assets.py
import numpy as np
from PIL import Image, ImageFilter
from pathlib import Path

SRC = Path("docs/superpowers/assets/kimmy_2026-06-05")
DST = Path("godot/assets/sprites/props")
# green-screen sources -> green-keyed game sprite names
MAP = {"kimmy_caged": "kimmy_caged", "kimmy_rainbow": "kimmy_rainbow",
       "crate_rainbow": "bonus_crate_rainbow", "bullet_rainbow": "candy_rainbow",
       "cage_back": "kimmy_cage_back", "cage_front": "kimmy_cage_front",
       "weapon_rainbow_icon": "weapon_rainbow", "kimmy_explosion_bomb": "kimmy_bomb"}
# black-bg premium VFX -> copied AS-IS (used with ADDITIVE blend in-engine, black drops out; do NOT green-key)
VFX = {"vfx_rainbow_chain": "vfx_rainbow_chain", "vfx_rainbow_shock": "vfx_rainbow_shock"}

def greenkey(src, low=14, high=52):
    a = np.array(Image.open(src).convert("RGBA")).astype(np.float32)
    R, G, B = a[:, :, 0], a[:, :, 1], a[:, :, 2]
    g = G - np.maximum(R, B)
    alpha = np.clip((high - g) / (high - low), 0, 1) * 255.0
    G2 = G - np.maximum(0, G - np.maximum(R, B)) * 0.9  # despill
    out = a.copy(); out[:, :, 1] = G2; out[:, :, 3] = alpha
    out = np.clip(out, 0, 255).astype(np.uint8)
    al = Image.fromarray(out[:, :, 3]).filter(ImageFilter.GaussianBlur(0.7))
    out[:, :, 3] = np.array(al)
    im = Image.fromarray(out); bb = im.getbbox()
    return im.crop(bb) if bb else im

for stem, name in MAP.items():
    src = SRC / f"{stem}.png"
    if not src.exists(): raise SystemExit(f"missing {src}")
    greenkey(src).save(DST / f"{name}.png"); print("wrote", DST / f"{name}.png")
import shutil
for stem, name in VFX.items():
    src = SRC / f"{stem}.png"
    if not src.exists(): raise SystemExit(f"missing {src}")
    shutil.copyfile(src, DST / f"{name}.png"); print("copied(VFX additive)", DST / f"{name}.png")
