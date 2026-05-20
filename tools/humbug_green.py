#!/usr/bin/env python3
"""Composite professor_humbug.png onto a 720x1280 (9:16) chroma-green
canvas — the start frame fed to tools/veo_render.sh for the level-select
flourish clips. Matching Veo's 9:16 output aspect avoids any reframing,
and the flat green lets the game chroma-key the resulting .ogv.

Run: python3 tools/humbug_green.py   ->   /tmp/humbug_green.png
"""
from PIL import Image

SRC = "godot/assets/sprites/professor_humbug.png"
OUT = "/tmp/humbug_green.png"
CANVAS = (720, 1280)
GREEN = (0, 255, 0)
TARGET_H = 1150  # ~90% of canvas height

def main() -> None:
    fig = Image.open(SRC).convert("RGBA")
    w = round(fig.width * TARGET_H / fig.height)
    fig = fig.resize((w, TARGET_H), Image.Resampling.LANCZOS)
    canvas = Image.new("RGB", CANVAS, GREEN)
    x = (CANVAS[0] - w) // 2
    y = (CANVAS[1] - TARGET_H) // 2
    canvas.paste(fig, (x, y), fig)  # fig's own alpha is the paste mask
    canvas.save(OUT)
    print("wrote %s  (%dx%d, humbug %dx%d at %d,%d)"
          % (OUT, CANVAS[0], CANVAS[1], w, TARGET_H, x, y))

if __name__ == "__main__":
    main()
