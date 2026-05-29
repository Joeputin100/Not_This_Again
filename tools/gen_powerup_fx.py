#!/usr/bin/env python3
"""Generate the two power-up flourish sprites for the posse-join "deputized"
beat (iter 335): a powdered-sugar puff and a glossy candy sheriff-star.

Procedural (PIL) rather than Imagen — these are small transient FX elements, so
a clean drawn look is enough and stays reliable/reproducible. RGBA, transparent
background, 256x256.

Run: python3 tools/gen_powerup_fx.py
Outputs:
  godot/assets/sprites/fx/sugar_puff.png
  godot/assets/sprites/fx/candy_sheriff_star.png
"""
import math
import os
import random
from PIL import Image, ImageDraw, ImageFilter

OUT_DIR = "godot/assets/sprites/fx"
N = 256
CX = CY = N / 2.0


def _save(img: Image.Image, name: str) -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, name)
    img.save(path)
    print("wrote", path)


def sugar_puff() -> None:
    """Soft white powdered-sugar cloud: gaussian-falloff alpha + sugar speckle."""
    img = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    px = img.load()
    sigma = N * 0.30
    for y in range(N):
        for x in range(N):
            d2 = (x - CX) ** 2 + (y - CY) ** 2
            a = math.exp(-d2 / (2 * sigma * sigma))
            if a < 0.01:
                continue
            # warm-white powdered sugar
            px[x, y] = (255, 252, 245, int(a * 235))
    # Sugar grain: scattered brighter/softer specks inside the puff.
    rnd = random.Random(335)
    speck = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    sd = ImageDraw.Draw(speck)
    for _ in range(260):
        ang = rnd.uniform(0, math.tau)
        r = rnd.uniform(0, N * 0.34) * math.sqrt(rnd.random())
        x = CX + math.cos(ang) * r
        y = CY + math.sin(ang) * r
        rr = rnd.uniform(1.5, 4.0)
        sd.ellipse([x - rr, y - rr, x + rr, y + rr], fill=(255, 255, 255, rnd.randint(60, 140)))
    speck = speck.filter(ImageFilter.GaussianBlur(1.2))
    img = Image.alpha_composite(img, speck)
    img = img.filter(ImageFilter.GaussianBlur(1.5))
    _save(img, "sugar_puff.png")


def _star_points(cx, cy, outer, inner, n=5, rot=-math.pi / 2):
    pts = []
    for i in range(n * 2):
        r = outer if i % 2 == 0 else inner
        a = rot + i * math.pi / n
        pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
    return pts


def _tip_centers(cx, cy, outer, n=5, rot=-math.pi / 2):
    return [(cx + math.cos(rot + i * 2 * math.pi / n) * outer,
             cy + math.sin(rot + i * 2 * math.pi / n) * outer) for i in range(n)]


def candy_sheriff_star() -> None:
    """Glossy gold 5-point sheriff star with ball tips, dark candy outline,
    and a soft white gloss highlight — reads as a shiny candy badge."""
    ss = 4  # supersample for clean edges
    S = N * ss
    cx = cy = S / 2.0
    outer = S * 0.40
    inner = S * 0.165
    ball_r = S * 0.052

    # 1) shape mask (star + tip balls)
    mask = Image.new("L", (S, S), 0)
    md = ImageDraw.Draw(mask)
    md.polygon(_star_points(cx, cy, outer, inner), fill=255)
    for (tx, ty) in _tip_centers(cx, cy, outer):
        md.ellipse([tx - ball_r, ty - ball_r, tx + ball_r, ty + ball_r], fill=255)

    # 2) vertical gold gradient (bright top → deep amber bottom)
    grad = Image.new("RGB", (S, S))
    gp = grad.load()
    top = (255, 240, 150)
    bot = (216, 150, 40)
    for y in range(S):
        t = y / (S - 1)
        gp_row = (int(top[0] + (bot[0] - top[0]) * t),
                  int(top[1] + (bot[1] - top[1]) * t),
                  int(top[2] + (bot[2] - top[2]) * t))
        for x in range(S):
            gp[x, y] = gp_row
    star = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    star.paste(grad, (0, 0), mask)

    # 3) dark candy outline drawn along the star + ball edges
    ring = Image.new("L", (S, S), 0)
    rd = ImageDraw.Draw(ring)
    rd.polygon(_star_points(cx, cy, outer, inner), outline=255, width=int(S * 0.018))
    for (tx, ty) in _tip_centers(cx, cy, outer):
        rd.ellipse([tx - ball_r, ty - ball_r, tx + ball_r, ty + ball_r],
                   outline=255, width=int(S * 0.018))
    dark = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    dark.paste((110, 64, 14, 255), (0, 0), ring)
    star = Image.alpha_composite(star, dark)

    # 4) gloss highlight — soft white blob upper-left, clipped to the star
    gloss = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    gd = ImageDraw.Draw(gloss)
    gd.ellipse([cx - outer * 0.5, cy - outer * 0.72, cx + outer * 0.18, cy - outer * 0.05],
               fill=(255, 255, 255, 150))
    gloss = gloss.filter(ImageFilter.GaussianBlur(S * 0.02))
    gloss.putalpha(Image.composite(gloss.split()[3], Image.new("L", (S, S), 0), mask))
    star = Image.alpha_composite(star, gloss)

    star = star.resize((N, N), Image.LANCZOS)
    _save(star, "candy_sheriff_star.png")


if __name__ == "__main__":
    sugar_puff()
    candy_sheriff_star()
