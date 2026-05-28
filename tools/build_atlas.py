#!/usr/bin/env python3
"""Build one sprite-sheet atlas from a video clip or a folder of frames.

Usage:
  build_atlas.py --clip path/to/clip.ogv --out godot/assets/sprites/atlases/cowboy_idle_a
  build_atlas.py --frames path/to/frames_dir --fps 24 --out .../name
  build_atlas.py --clip ... --scale 0.25 --out ...   # ¼-resolution atlas

Produces <out>.png (the grid atlas, RGBA with transparent background) and
<out>.atlas.json ({cols, rows, frame_count, fps}).

Pipeline per frame:
  1. Optional scale: resize each frame by --scale (default 1.0) using
     LANCZOS before any other work. The shipped APK should run from the
     device-locked render resolution (see Task 10 in the SP1 plan), not
     from the source-res 7200×12800 atlases that live in git.
  2. Letterbox strip: if Veo's input start frame wasn't 9:16, Veo padded
     the output with solid pure-black bands top/bottom. Detect those and
     mark their pixels fully transparent.
  3. Chroma-key Veo's green to transparent (vectorized numpy distance,
     ~50x faster than per-pixel Python loop).
  4. Zero out the RGB channels wherever alpha became 0 — keeps the file
     small and shows real transparency in viewers that don't honour alpha.
"""
import argparse
import json
import math
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image

# Allow the big atlas writes (the source-resolution sheets are >89MP).
Image.MAX_IMAGE_PIXELS = None

# Chroma test: pixel must look GREEN (G high, R+B low). Replaces the old
# Manhattan-distance-to-(0,177,64) test which over-matched dark grey/shadow
# pixels (punched holes through Pete's red shirt). The first attempt of
# this revision used |G - 177| < 50, which excluded pure (0, 255, 0) —
# Veo's chroma in many clips IS pure green, so most of the figure surround
# survived. Final version: G must be above GREEN_G_MIN AND R+B must each
# be below their thresholds. Covers both (0, 177, 64) chroma and (0, 255, 0)
# chroma without catching greys/shadows (G is always low for shadows).
GREEN_G_MIN = 110           # G must be at least this — captures both chroma
                            # green shades Veo emits without catching dark
                            # figure pixels (G < ~90 for typical shadows).
GREEN_R_MAX = 90            # R must be below this
GREEN_B_MAX = 110           # B must be below this
LETTERBOX_ROW_THRESHOLD = 0.80  # fraction of near-black pixels needed to call a row letterbox
                                # (relaxed from 0.95 — prospector_death has a transition zone
                                # between bar and figure at ~80-93% blackness that the stricter
                                # threshold missed, leaving a visible inner strip on-device)
LETTERBOX_BLACK_SUM = 15    # rgb-sum <= this counts as "near-black" (catches Veo's
                            # (1,1,1)-ish compression noise around true (0,0,0) bands)


def extract_frames(clip: Path, dst: Path) -> float:
    """ffmpeg-extract every frame. Returns the clip's fps."""
    probe = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0",
         "-show_entries", "stream=r_frame_rate", "-of", "csv=p=0", str(clip)],
        capture_output=True, text=True, check=True).stdout.strip()
    num, den = (int(x) for x in probe.split("/"))
    fps = num / den
    subprocess.run(["ffmpeg", "-y", "-i", str(clip),
                    str(dst / "f_%04d.png")], capture_output=True, check=True)
    return fps


def key_frame(img: Image.Image) -> Image.Image:
    """Strip Veo letterbox bands + chroma-key the green to transparent.

    Vectorized via numpy. Pixels that end up transparent also get their RGB
    zeroed so the saved PNG compresses tighter and renders cleanly in
    viewers that don't honour alpha.
    """
    arr = np.array(img.convert("RGBA"))
    H = arr.shape[0]
    rgb = arr[..., :3]

    # 1. Letterbox: rows / columns near the edges that are ≥95% near-black.
    # Veo's letterbox bands aren't always pure (0,0,0) — JPEG-like noise in
    # the OGV encoding makes them (1,1,1)-ish, so allow a small tolerance.
    # Walk INWARD from each edge so we never zero a dark interior band.
    near_black = (rgb.sum(axis=-1) <= LETTERBOX_BLACK_SUM)
    row_blackness = near_black.mean(axis=1)
    col_blackness = near_black.mean(axis=0)
    W = arr.shape[1]
    top = 0
    while top < H and row_blackness[top] >= LETTERBOX_ROW_THRESHOLD:
        top += 1
    bottom = H
    while bottom > top and row_blackness[bottom - 1] >= LETTERBOX_ROW_THRESHOLD:
        bottom -= 1
    left = 0
    while left < W and col_blackness[left] >= LETTERBOX_ROW_THRESHOLD:
        left += 1
    right = W
    while right > left and col_blackness[right - 1] >= LETTERBOX_ROW_THRESHOLD:
        right -= 1
    if top > 0:
        arr[:top] = 0
    if bottom < H:
        arr[bottom:] = 0
    if left > 0:
        arr[:, :left] = 0
    if right < W:
        arr[:, right:] = 0

    # 2. Chroma-key the green: per-channel "true green" test, not Manhattan
    # distance. The pixel's G must be close to chroma-green's 177 AND its R
    # and B must each be below their thresholds. Catches Veo's slightly-
    # varying chroma without false-matching on dark/grey pixels.
    rgb_i = arr[..., :3].astype(np.int16)
    r_ch = rgb_i[..., 0]
    g_ch = rgb_i[..., 1]
    b_ch = rgb_i[..., 2]
    chroma_mask = (
        (g_ch > GREEN_G_MIN)
        & (r_ch < GREEN_R_MAX)
        & (b_ch < GREEN_B_MAX)
    )
    arr[chroma_mask] = 0

    return Image.fromarray(arr)


def _normalize_figures(imgs: list[Image.Image], fraction: float) -> list[Image.Image]:
    """Scale every frame so the clip's figure fills `fraction` of the cell
    height, with feet anchored near the bottom and centred horizontally.

    Uses ONE transform (from the union bbox of non-transparent pixels across
    all frames) applied to every frame, so the figure's animation motion is
    preserved — only the overall size/placement is normalised. This is what
    makes e.g. the pusher clips (which Veo rendered at inconsistent sizes)
    match each other so a single blob-shadow size fits them all.
    """
    fw, fh = imgs[0].size
    union = None
    for im in imgs:
        a = np.array(im)
        ys, xs = np.where(a[..., 3] > 16)
        if len(ys) == 0:
            continue
        bb = [int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())]
        if union is None:
            union = bb
        else:
            union = [min(union[0], bb[0]), min(union[1], bb[1]),
                     max(union[2], bb[2]), max(union[3], bb[3])]
    if union is None:
        return imgs
    fig_h = max(1, union[3] - union[1])
    s = (fraction * fh) / float(fig_h)
    union_cx = (union[0] + union[2]) * 0.5
    feet_y = float(union[3])
    target_feet_y = 0.94 * fh
    out: list[Image.Image] = []
    for im in imgs:
        scaled = im.resize((max(1, int(round(fw * s))), max(1, int(round(fh * s)))),
                           Image.Resampling.LANCZOS)
        canvas = Image.new("RGBA", (fw, fh), (0, 0, 0, 0))
        ox = int(round(fw * 0.5 - union_cx * s))
        oy = int(round(target_feet_y - feet_y * s))
        canvas.alpha_composite(scaled, (ox, oy))
        out.append(canvas)
    return out


def build(frames: list[Path], fps: float, out: Path, scale: float = 1.0,
          normalize: float = 0.0) -> None:
    imgs: list[Image.Image] = []
    for f in sorted(frames):
        img = Image.open(f)
        if scale != 1.0:
            new_size = (max(1, int(round(img.width * scale))),
                        max(1, int(round(img.height * scale))))
            img = img.resize(new_size, Image.Resampling.LANCZOS)
        imgs.append(key_frame(img))
    if normalize > 0.0:
        imgs = _normalize_figures(imgs, normalize)
    n = len(imgs)
    cols = math.ceil(math.sqrt(n))
    rows = math.ceil(n / cols)
    fw, fh = imgs[0].size
    sheet = Image.new("RGBA", (cols * fw, rows * fh), (0, 0, 0, 0))
    for i, im in enumerate(imgs):
        sheet.paste(im, ((i % cols) * fw, (i // cols) * fh))
    out.with_suffix(".png").parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out.with_suffix(".png"))
    out.with_suffix(".atlas.json").write_text(json.dumps(
        {"cols": cols, "rows": rows, "frame_count": n, "fps": fps}, indent=2))
    print(f"wrote {out}.png  {cols}x{rows} grid, {n} frames @ {fps:.1f}fps")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--clip")
    ap.add_argument("--frames")
    ap.add_argument("--fps", type=float, default=24.0)
    ap.add_argument("--scale", type=float, default=1.0,
                    help="resize each frame by this factor (LANCZOS) before composition")
    ap.add_argument("--normalize", type=float, default=0.0,
                    help="scale the figure to this fraction of cell height "
                         "(0=off); feet-anchored + centred. Use to match clip "
                         "sizes, e.g. --normalize 0.7 for the pusher set.")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    out = Path(a.out)
    if a.clip:
        with tempfile.TemporaryDirectory() as td:
            fps = extract_frames(Path(a.clip), Path(td))
            build(sorted(Path(td).glob("f_*.png")), fps, out, scale=a.scale,
                  normalize=a.normalize)
    elif a.frames:
        build(sorted(Path(a.frames).glob("*.png")), a.fps, out, scale=a.scale,
              normalize=a.normalize)
    else:
        sys.exit("need --clip or --frames")


if __name__ == "__main__":
    main()
