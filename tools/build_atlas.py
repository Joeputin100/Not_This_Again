#!/usr/bin/env python3
"""Build one sprite-sheet atlas from a video clip or a folder of frames.

Usage:
  build_atlas.py --clip path/to/clip.ogv --out godot/assets/sprites/atlases/cowboy_idle_a
  build_atlas.py --frames path/to/frames_dir --fps 24 --out .../name

Produces <out>.png (the grid atlas, RGBA with transparent background) and
<out>.atlas.json ({cols, rows, frame_count, fps}).

Pipeline per frame:
  1. Letterbox strip: if Veo's input start frame wasn't 9:16, Veo padded
     the output with solid pure-black bands top/bottom. Detect those and
     mark their pixels fully transparent.
  2. Chroma-key Veo's green to transparent (vectorized numpy distance,
     ~50x faster than per-pixel Python loop).
  3. Zero out the RGB channels wherever alpha became 0 — keeps the file
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
KEY_TOLERANCE = 70          # per-channel summed distance (×3) treated as background
LETTERBOX_ROW_THRESHOLD = 0.99  # fraction of pure-black pixels needed to call a row "letterbox"


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

    # 1. Letterbox: rows that are ≥99% pure black at the very top / bottom.
    # We only walk inward from the edges so we never zero a black interior
    # row that happens to be dim.
    row_blackness = (rgb.sum(axis=-1) == 0).mean(axis=1)
    top = 0
    while top < H and row_blackness[top] >= LETTERBOX_ROW_THRESHOLD:
        top += 1
    bottom = H
    while bottom > top and row_blackness[bottom - 1] >= LETTERBOX_ROW_THRESHOLD:
        bottom -= 1
    if top > 0:
        arr[:top] = 0
    if bottom < H:
        arr[bottom:] = 0

    # 2. Chroma-key the green: same per-channel summed distance threshold as
    # before, just vectorized.
    rgb_i = arr[..., :3].astype(np.int16)
    g_diff = (np.abs(rgb_i[..., 0] - GREEN[0])
              + np.abs(rgb_i[..., 1] - GREEN[1])
              + np.abs(rgb_i[..., 2] - GREEN[2]))
    chroma_mask = g_diff < KEY_TOLERANCE * 3
    arr[chroma_mask] = 0

    return Image.fromarray(arr)


def build(frames: list[Path], fps: float, out: Path) -> None:
    imgs = [key_frame(Image.open(f)) for f in sorted(frames)]
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
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    out = Path(a.out)
    if a.clip:
        with tempfile.TemporaryDirectory() as td:
            fps = extract_frames(Path(a.clip), Path(td))
            build(sorted(Path(td).glob("f_*.png")), fps, out)
    elif a.frames:
        build(sorted(Path(a.frames).glob("*.png")), a.fps, out)
    else:
        sys.exit("need --clip or --frames")


if __name__ == "__main__":
    main()
