#!/usr/bin/env python3
"""Generate seamless tileable ground albedo + derived normal per terrain theme."""
import subprocess, sys, pathlib, numpy as np
from PIL import Image
OUT = pathlib.Path("godot/assets/textures")
PROMPTS = {
  "frontier": "top-down seamless tileable photo of dry sun-baked desert dirt ground, scattered small pebbles, fine cracks, patches of pale sand, natural earthy browns, even overhead light, no shadows no objects",
  "mine":     "top-down seamless tileable photo of dusty grey mine gravel and crushed ore rock, coal flecks, compacted dirt, even overhead light, no shadows",
  "farm":     "top-down seamless tileable photo of rich brown farm soil with sparse short grass flecks and tiny weeds, moist earthy tones, even overhead light, no shadows",
  "mountain": "top-down seamless tileable photo of snow over grey mountain rock, packed snow drifts, exposed frosted stone, icy patches, even overhead light, no shadows",
}
def make_seamless(img):
    a = np.asarray(img.convert("RGB")).astype(np.float32); h,w,_ = a.shape
    off = np.roll(np.roll(a, h//2, 0), w//2, 1)
    bx = np.ones((h,w,1), np.float32)
    fade = np.linspace(0,1,w//8).reshape(1,-1,1)
    bx[:, :w//8] = fade; bx[:, w-w//8:] = fade[:, ::-1]
    by = np.ones((h,w,1), np.float32)
    fy = np.linspace(0,1,h//8).reshape(-1,1,1)
    by[:h//8] = fy; by[h-h//8:] = fy[::-1]
    m = np.minimum(bx, by)
    out = a*m + off*(1-m)
    return Image.fromarray(out.astype(np.uint8))
def normal_from(img, strength=2.0):
    g = np.asarray(img.convert("L")).astype(np.float32)/255.0
    gx = np.gradient(g, axis=1)*strength; gy = np.gradient(g, axis=0)*strength
    n = np.dstack([-gx, -gy, np.ones_like(g)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return Image.fromarray(((n*0.5+0.5)*255).astype(np.uint8))
def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for terr, prompt in PROMPTS.items():
        raw = f"/tmp/ground_{terr}_raw.png"
        subprocess.run([sys.executable, "tools/nb_pro_render.py",
                        "--prompt", prompt,
                        "--aspect", "1:1", "--out", raw], check=True)
        base = Image.open(raw).resize((1024,1024))
        seam = make_seamless(base)
        seam.save(OUT / f"ground_{terr}.png")
        normal_from(seam).save(OUT / f"ground_{terr}_n.png")
        print("wrote", terr)
if __name__ == "__main__": main()
