#!/usr/bin/env python3
"""Composite pusher_melee.png onto a 720x1280 (9:16) chroma-green
canvas — the start frame fed to tools/veo_render.sh for the pusher
run_forward clip. The melee sprite faces the camera, making it the
best existing source for a forward-running start frame.

Following the same pattern as tools/humbug_green.py.

Run: python3 tools/gen_pusher_forward.py
"""
from PIL import Image

SRC = "godot/assets/sprites/props/pusher_melee.png"
OUT = "godot/assets/sprites/props/pusher_forward.png"
CANVAS = (720, 1280)
GREEN = (0, 177, 64)   # chroma green per project spec (vs pure 0,255,0)
TARGET_H = 1100  # Scale to fill most of the canvas height. The source sprite
                 # is 1408x768 (landscape) with internal transparent padding;
                 # at this height the character body fills ~50% of the frame.
                 # Width will exceed the 720px canvas — crop/clip is fine as
                 # PIL paste clips out-of-bounds pixels automatically.

def main() -> None:
    fig = Image.open(SRC).convert("RGBA")
    ar = fig.width / fig.height
    h = TARGET_H
    w = round(h * ar)
    fig = fig.resize((w, h), Image.Resampling.LANCZOS)
    canvas = Image.new("RGB", CANVAS, GREEN)
    x = (CANVAS[0] - w) // 2
    y = (CANVAS[1] - h) // 2
    canvas.paste(fig, (x, y), fig)  # fig's own alpha is the paste mask
    canvas.save(OUT)
    print("wrote %s  (%dx%d, pusher %dx%d at %d,%d)"
          % (OUT, CANVAS[0], CANVAS[1], w, h, x, y))

if __name__ == "__main__":
    main()
