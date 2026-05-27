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

GREEN = (0, 177, 64)        # Veo chroma-green; tune if a clip differs
# Chroma test: require G near 177 AND R/B both below their thresholds.
# Previous version used Manhattan distance to GREEN with tolerance 210,
# which incidentally also keyed mid-grey shadow pixels (e.g. (50,50,50)
# has Manhattan-diff 191) — that punched holes through Pete's red shirt
# wherever he had a dark fold/shadow. The "true green" check below
# requires the pixel to actually look green, not just have a Manhattan
# distance that happens to round into range.
GREEN_G_TOLERANCE = 50      # how far G can drift from 177
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
        (np.abs(g_ch - GREEN[1]) < GREEN_G_TOLERANCE)
        & (r_ch < GREEN_R_MAX)
        & (b_ch < GREEN_B_MAX)
    )
    arr[chroma_mask] = 0

    return Image.fromarray(arr)


def build(frames: list[Path], fps: float, out: Path, scale: float = 1.0) -> None:
    imgs: list[Image.Image] = []
    for f in sorted(frames):
        img = Image.open(f)
        if scale != 1.0:
            new_size = (max(1, int(round(img.width * scale))),
                        max(1, int(round(img.height * scale))))
            img = img.resize(new_size, Image.Resampling.LANCZOS)
        imgs.append(key_frame(img))
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
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    out = Path(a.out)
    if a.clip:
        with tempfile.TemporaryDirectory() as td:
            fps = extract_frames(Path(a.clip), Path(td))
            build(sorted(Path(td).glob("f_*.png")), fps, out, scale=a.scale)
    elif a.frames:
        build(sorted(Path(a.frames).glob("*.png")), a.fps, out, scale=a.scale)
    else:
        sys.exit("need --clip or --frames")


if __name__ == "__main__":
    main()
