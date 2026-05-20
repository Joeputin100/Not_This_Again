"""Difference matting: subject over white + over black → true-alpha RGBA.
  C_white - C_black = (1-alpha)  (independent of subject colour)
Auto-aligns the black image to the white one via edge-map phase correlation,
normalises for non-pure backgrounds, un-premultiplies colour from the black
image, and reports a drift metric (high = the two gens diverged → ghosting)."""
import sys
import numpy as np
from PIL import Image

white = Image.open(sys.argv[1]).convert("RGB")
black = Image.open(sys.argv[2]).convert("RGB")
out_path = sys.argv[3]

if black.size != white.size:
    black = black.resize(white.size, Image.LANCZOS)

W = np.asarray(white).astype(np.float64) / 255.0
B = np.asarray(black).astype(np.float64) / 255.0

def edges(img):
    g = img.mean(axis=2)
    gy, gx = np.gradient(g)
    return np.hypot(gx, gy)

ew, eb = edges(W), edges(B)
F = np.fft.fft2(ew)
G = np.fft.fft2(eb)
R = F * np.conj(G)
R /= (np.abs(R) + 1e-8)
corr = np.fft.ifft2(R).real
dy, dx = np.unravel_index(np.argmax(corr), corr.shape)
if dy > W.shape[0] // 2:
    dy -= W.shape[0]
if dx > W.shape[1] // 2:
    dx -= W.shape[1]
B = np.roll(B, (dy, dx), axis=(0, 1))
print(f"alignment shift: dy={dy} dx={dx}")

def corner_avg(arr):
    c = np.concatenate([arr[:10, :10], arr[:10, -10:],
                        arr[-10:, :10], arr[-10:, -10:]])
    return float(c.mean())

bw, bb = corner_avg(W), corner_avg(B)
span = max(bw - bb, 0.5)
print(f"bg levels: white~{bw:.3f} black~{bb:.3f} span={span:.3f}")

diff = (W - B).mean(axis=2)
alpha = np.clip(1.0 - diff / span, 0.0, 1.0)

a3 = alpha[:, :, None]
fg = np.where(a3 > 0.02, B / np.maximum(a3, 1e-3), 0.0)
fg = np.clip(fg, 0.0, 1.0)

interior = alpha > 0.9
if interior.sum() > 0:
    fg_w = np.clip((W - (1.0 - a3)) / np.maximum(a3, 1e-3), 0.0, 1.0)
    drift = float(np.abs(fg[interior] - fg_w[interior]).mean())
    pct = 100.0 * interior.sum() / alpha.size
    print(f"opaque interior: {pct:.1f}% of canvas")
    print(f"DRIFT METRIC: {drift:.4f}  (<0.05 great, 0.05-0.10 ok, >0.10 ghosting)")

Image.fromarray((np.dstack([fg, alpha]) * 255).astype(np.uint8), "RGBA").save(out_path)
print(f"saved {out_path}  ({white.size[0]}x{white.size[1]})")
