#!/usr/bin/env python3
"""Slice the raw chroma-keyed spritesheets into individual frame PNGs
with transparent backgrounds. Output goes to godot/assets/sprites/.

The artist used pure-green (0, 255, 0) backgrounds. We detect dominant-
green pixels and zero their alpha. Yellow muzzle-flash highlights have
high R+G so they survive — only pixels with g >> r and g >> b get keyed.
"""
import os
import numpy as np
from PIL import Image

SRC_DIR = "/home/projects/Not_This_Again/godot/raw spritesheets"
OUT_DIR = "/home/projects/Not_This_Again/godot/assets/sprites"
os.makedirs(OUT_DIR, exist_ok=True)


def chroma_to_alpha(img: Image.Image) -> Image.Image:
    """Replace dominant-green pixels with transparent. Anti-aliased edges
    get partial alpha based on green dominance."""
    img = img.convert("RGBA")
    arr = np.array(img)
    r = arr[:, :, 0].astype(np.int16)
    g = arr[:, :, 1].astype(np.int16)
    b = arr[:, :, 2].astype(np.int16)
    # Dominant-green test: green channel meaningfully higher than both
    # red and blue, AND green is bright. Threshold tuned so:
    #   pure green (0, 255, 0)         → keyed (transparent)
    #   chroma-edge bleed (60, 230, 60) → keyed
    #   bright yellow (255, 255, 0)     → kept (r==g, fails dominance)
    #   sprite orange (255, 150, 0)     → kept (r > g)
    green_dominance = g - np.maximum(r, b)
    green_mask = (green_dominance > 60) & (g > 150)
    arr[green_mask, 3] = 0
    # Edge feather: pixels where green is somewhat dominant but not pure
    # get partial alpha so the sprite edges don't ring.
    edge_mask = (green_dominance > 20) & (green_dominance <= 60) & (g > 120) & ~green_mask
    # Scale alpha down based on how green they are
    edge_amount = ((green_dominance[edge_mask] - 20) / 40.0 * 200).clip(0, 200).astype(np.uint8)
    arr[edge_mask, 3] = (255 - edge_amount).astype(np.uint8)
    return Image.fromarray(arr)


def slice_grid(img: Image.Image, cols: int, rows: int, out_prefix: str,
               frame_order: list[int] | None = None, tight_crop: bool = True) -> int:
    """Slice img into cols*rows cells, save as <out_prefix>_NN.png. If
    frame_order given, reindex frames in that order. If tight_crop, crop
    each frame to its content bounding box (saves disk space, simplifies
    pivot logic since the visible sprite fills the texture)."""
    cell_w = img.width // cols
    cell_h = img.height // rows
    if frame_order is None:
        frame_order = list(range(cols * rows))
    for out_idx, src_idx in enumerate(frame_order):
        row = src_idx // cols
        col = src_idx % cols
        frame = img.crop((col * cell_w, row * cell_h,
                          (col + 1) * cell_w, (row + 1) * cell_h))
        if tight_crop:
            bbox = frame.getbbox()
            if bbox:
                # Add 4px padding so edge anti-aliasing isn't clipped
                pad = 4
                bbox = (max(0, bbox[0] - pad), max(0, bbox[1] - pad),
                        min(frame.width, bbox[2] + pad), min(frame.height, bbox[3] + pad))
                frame = frame.crop(bbox)
        out_path = f"{OUT_DIR}/{out_prefix}_{out_idx:02d}.png"
        frame.save(out_path, "PNG", optimize=True)
        print(f"  {out_prefix}_{out_idx:02d}.png: {frame.size}")
    return len(frame_order)


def process_sheet(filename: str, cols: int, rows: int, out_prefix: str,
                  frame_order: list[int] | None = None,
                  top_crop: int = 0, tight_crop: bool = True) -> None:
    """top_crop strips the top N pixels from the source before slicing.
    tight_crop crops each frame to its content bbox; disable for animation
    frames where the character moves within a fixed cell — uniform frames
    keep the AnimatedSprite2D origin stable across frames so the figure
    doesn't jitter."""
    print(f"Processing {filename}...")
    img = Image.open(f"{SRC_DIR}/{filename}")
    img = chroma_to_alpha(img)
    if top_crop > 0:
        img = img.crop((0, top_crop, img.width, img.height))
    count = slice_grid(img, cols, rows, out_prefix, frame_order,
                       tight_crop=tight_crop)
    print(f"  → {count} frames saved\n")


if __name__ == "__main__":
    # Muzzle flash: 6 frames. Reverse order so animation plays from
    # peak burst (frame 5 in sheet, bottom-right) → small spark (frame
    # 0, top-left). One-shot effect — tight crop is fine; jitter
    # between frames is invisible at 30fps over 200ms.
    process_sheet("spritesheet muzzle flash.png", 3, 2, "muzzle_flash",
                  frame_order=[5, 4, 3, 2, 1, 0], tight_crop=True)

    # Posse animations use fixed-grid slicing (tight_crop=False) so the
    # cowboy stays anchored at the same texture origin across all frames.
    # Per-frame tight crop would shift the origin (different bboxes per
    # pose), making the figure jitter in AnimatedSprite2D playback.

    # Idle tapping: 6-frame foot-tap loop. Title banner cropped off the
    # top of the source first.
    process_sheet("spritesheet posse idle tapping.png", 3, 2, "posse_idle",
                  top_crop=130, tight_crop=False)

    # Running + shooting: 8-frame cycle, 4 cols × 2 rows.
    process_sheet("spritesheet posse running shooting.png", 4, 2, "posse_run_shoot",
                  tight_crop=False)

    # Dying: top row is 3 running frames (redundant), bottom row is the
    # hit→stumble→dead sequence. Extract only the bottom row.
    process_sheet("spritesheet posse dying.png", 3, 2, "posse_die",
                  frame_order=[3, 4, 5], tight_crop=False)

    print("Done.")
