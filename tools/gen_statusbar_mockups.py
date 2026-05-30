#!/usr/bin/env python3
"""Mockup of the candy-Western Quake-style bottom status bar — Layout A.

iter339 design, refined per user feedback (2nd pass):
  - WEAPON IMAGE is the hero (big six-shooter, left); name beside it; the
    bullet type is a small FOOTNOTE under the name.
  - AMMO clip shows the 4 real jelly-bean colors (candy_red/green/blue/amber,
    the default gummy set in bullet.gd), alpha-clean and fit to the slots.
  - Top strip = the LEVEL NAME over a progress bar, capped left by the POSSE
    counter (gold star + ×N, with a glow hinting the pulse-on-change) and
    right by a static PNG badge of THIS LEVEL'S BOSS (Slippery Pete for L1).
  - Hearts on the right are LIVES (GameState, max 5).

Mockup only (not wired into the game). The live status line will drive the
level name, boss PNG, ammo colors and posse-count pulse dynamically.

Run: python3 tools/gen_statusbar_mockups.py  -> /tmp/statusbar_A.png
"""
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageChops

W, H = 1080, 270
PROP = "godot/assets/sprites/props/"
CANDY = "godot/assets/sprites/candy/"
FX = "godot/assets/sprites/fx/"
FONT = "godot/assets/fonts/Rye-Regular.ttf"

WOOD_TOP = (96, 60, 30)
WOOD_BOT = (60, 36, 18)
GOLD = (240, 200, 90)
CREAM = (250, 240, 215)
INK = (40, 20, 8)
FILL = (120, 210, 120)

# The default Jelly Bean Six-Shooter fires these 4 gummy colors (bullet.gd).
GUMMY = ["candy_red.png", "candy_green.png", "candy_blue.png", "candy_amber.png"]
LEVEL_NAME = "FRONTIER TOWN"
BOSS_PNG = "godot/assets/sprites/slippery_pete.png"


def font(sz):
    return ImageFont.truetype(FONT, sz)


def png_fit(path, w, h):
    """Load RGBA, crop to the opaque bbox (drop transparent margins), then
    scale to CONTAIN the (w, h) box preserving aspect."""
    im = Image.open(path).convert("RGBA")
    bb = im.split()[3].getbbox()
    if bb:
        im = im.crop(bb)
    s = min(w / im.width, h / im.height)
    return im.resize((max(1, int(im.width * s)), max(1, int(im.height * s))), Image.LANCZOS)


def text(d, xy, s, sz, col=CREAM, anchor="lm", sw=None):
    d.text(xy, s, font=font(sz), fill=col, anchor=anchor,
           stroke_width=sw if sw is not None else max(2, sz // 14), stroke_fill=INK)


def draw_heart(d, cx, cy, r, col):
    import math
    pts = []
    for s in range(28):
        t = math.tau * s / 28
        x = 16 * math.sin(t) ** 3
        y = -(13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t))
        pts.append((cx + x * r / 16, cy + y * r / 16))
    d.polygon(pts, fill=col, outline=(80, 20, 20), width=3)


def bar_bg():
    img = Image.new("RGBA", (W, H))
    px = img.load()
    for y in range(H):
        t = y / H
        c = tuple(int(WOOD_TOP[i] + (WOOD_BOT[i] - WOOD_TOP[i]) * t) for i in range(3))
        for x in range(W):
            px[x, y] = c + (255,)
    d = ImageDraw.Draw(img)
    for x in (480, 760):
        d.line([(x, 84), (x, H)], fill=(40, 24, 12, 160), width=3)
    stripe = 26
    for i in range(-1, W // stripe + 1):
        x0 = i * stripe
        col = (235, 70, 80) if i % 2 == 0 else (250, 245, 240)
        d.polygon([(x0, 0), (x0 + stripe, 0), (x0 + stripe - 14, 16), (x0 - 14, 16)], fill=col)
    d.line([(0, 17), (W, 17)], fill=(150, 110, 40, 255), width=3)
    return img


def clip(img, x, y, loaded, total):
    """Ammo clip: `total` slots; the loaded ones cycle the 4 gummy colors."""
    d = ImageDraw.Draw(img)
    sw, sh, gap = 42, 52, 44
    for i in range(total):
        bx = x + i * gap
        d.rounded_rectangle([bx, y, bx + sw, y + sh], 8, fill=(30, 18, 8, 255), outline=(150, 110, 40), width=2)
        if i < loaded:
            ic = png_fit(CANDY + GUMMY[i % len(GUMMY)], sw - 8, sh - 8)
            img.alpha_composite(ic, (bx + (sw - ic.width) // 2, y + (sh - ic.height) // 2))


def boss_badge(img, cx, cy, r, path):
    """This level's boss as a round PNG badge at the end of the trail."""
    d = ImageDraw.Draw(img)
    boss = Image.open(path).convert("RGBA")
    bb = boss.split()[3].getbbox()
    if bb:
        boss = boss.crop(bb)
    side = min(boss.width, boss.height)        # top square = head + shoulders
    ox = max(0, (boss.width - side) // 2)
    boss = boss.crop((ox, 0, ox + side, side)).resize((2 * r, 2 * r), Image.LANCZOS)
    mask = Image.new("L", (2 * r, 2 * r), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, 2 * r, 2 * r], fill=255)
    mask = ImageChops.multiply(mask, boss.split()[3])
    d.ellipse([cx - r - 3, cy - r - 3, cx + r + 3, cy + r + 3], fill=(58, 38, 22), outline=GOLD, width=4)
    img.paste(boss, (cx - r, cy - r), mask)


def trail(img, level_name):
    """Top strip: POSSE counter (left, glowing) -> level-name progress bar
    -> boss badge (right)."""
    d = ImageDraw.Draw(img)
    frac = 0.4
    bx0, bx1, by = 248, 952, 50
    # posse badge with a soft glow (hints the pulse-on-change)
    glow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([2, by - 40, 96, by + 40], fill=(255, 210, 110, 130))
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(9)))
    img.alpha_composite(png_fit(FX + "candy_sheriff_star.png", 56, 56), (16, by - 28))
    text(d, (84, by), "×47", 34, CREAM, "lm")
    # progress bar + position marker
    d.rounded_rectangle([bx0, by - 13, bx1, by + 13], 13, fill=(30, 18, 8), outline=(150, 110, 40), width=2)
    d.rounded_rectangle([bx0 + 3, by - 10, bx0 + 3 + int((bx1 - bx0 - 6) * frac), by + 10], 10, fill=FILL)
    mx = bx0 + 3 + int((bx1 - bx0 - 6) * frac)
    d.ellipse([mx - 11, by - 11, mx + 11, by + 11], fill=(250, 240, 215), outline=INK, width=2)
    text(d, ((bx0 + bx1) // 2, by - 30), level_name, 22, GOLD, "mm", 2)
    boss_badge(img, bx1 + 42, by, 30, BOSS_PNG)


def layout_A():
    img = bar_bg()
    d = ImageDraw.Draw(img)
    trail(img, LEVEL_NAME)

    # ── WEAPON (hero) — zone 0..480 ──────────────────────────────────────
    gun = png_fit(PROP + "weapon_six_shooter.png", 230, 150)
    img.alpha_composite(gun, (16, 150 - gun.height // 2 + 30))
    nx = 30 + gun.width
    text(d, (nx, 150), "JELLY BEAN", 30, GOLD, "lm")
    text(d, (nx, 188), "SIX-SHOOTER", 30, GOLD, "lm")
    img.alpha_composite(png_fit(CANDY + "candy_red.png", 26, 26), (nx, 214))
    text(d, (nx + 34, 228), "JELLY BEANS", 18, (210, 195, 170), "lm", 2)

    # ── AMMO — zone 480..760 ─────────────────────────────────────────────
    text(d, (620, 110), "AMMO", 20, GOLD, "mm", 2)
    clip(img, 488, 140, 4, 6)

    # ── LIVES (hearts) — zone 760..1080 ──────────────────────────────────
    for i in range(5):
        draw_heart(d, 812 + i * 56, 175, 24, (235, 70, 90) if i < 4 else (90, 55, 55))

    img.save("/tmp/statusbar_A.png")
    print("wrote /tmp/statusbar_A.png")


if __name__ == "__main__":
    layout_A()
