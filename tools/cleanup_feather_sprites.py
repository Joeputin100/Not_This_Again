#!/usr/bin/env python3
"""Drop matte-artifact components from RGBA sprites and centre the result.

Connected-component analysis on the alpha mask. Any component smaller than
`MIN_RELATIVE_SIZE` * largest_component is dropped (its alpha is zeroed).
What remains is then translated so the bounding box centres in the canvas.

With `--fit MARGIN` (e.g. --fit 0.1), the remaining content is additionally
cropped to its bbox and scaled down (preserving aspect ratio) so a margin of
that proportion is left on each side of the canvas — useful when Gemini
generated subject content that extends past the canvas edges.

This is for cleaning up Gemini + diff-matte outputs where the matte preserved
small accents that the model composed alongside the main subject, or where
thin 1-pixel residue lines survived along the canvas edges. Run AFTER you
have a feather you mostly like; this is a polish pass, not a generator.

Usage:
    python3 tools/cleanup_feather_sprites.py [--fit 0.1] path1.png [path2.png ...]

Overwrites each input in place. Back up first if you want.
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy.ndimage import label


ALPHA_THRESHOLD = 8           # alpha > this counts as "opaque enough"
MIN_RELATIVE_SIZE = 0.05      # drop components < 5% of the largest


def cleanup(path: Path, fit_margin: float | None = None) -> None:
    img = Image.open(path).convert("RGBA")
    arr = np.array(img)
    H, W = arr.shape[:2]
    mask = arr[..., 3] > ALPHA_THRESHOLD

    labeled, ncomp = label(mask)  # type: ignore[misc]
    if ncomp == 0:
        print(f"  {path.name}: empty image, nothing to do")
        return

    sizes = np.bincount(labeled.ravel())
    sizes[0] = 0  # background label
    largest = int(sizes.max())
    threshold = MIN_RELATIVE_SIZE * largest
    keep_labels = np.where(sizes >= threshold)[0]
    keep_mask = np.isin(labeled, keep_labels)

    dropped_px = int(mask.sum() - keep_mask.sum())
    arr[..., 3] = np.where(keep_mask, arr[..., 3], 0)

    ys, xs = np.where(keep_mask)
    if len(ys) == 0:
        print(f"  {path.name}: nothing kept, refusing to overwrite")
        return

    if fit_margin is not None:
        y0, y1 = int(ys.min()), int(ys.max()) + 1
        x0, x1 = int(xs.min()), int(xs.max()) + 1
        cropped = arr[y0:y1, x0:x1]
        ch, cw = cropped.shape[:2]

        target_h = int(H * (1 - 2 * fit_margin))
        target_w = int(W * (1 - 2 * fit_margin))
        scale = min(target_h / ch, target_w / cw, 1.0)
        new_h = max(1, int(round(ch * scale)))
        new_w = max(1, int(round(cw * scale)))

        if scale < 1.0:
            resized = np.array(Image.fromarray(cropped).resize((new_w, new_h), Image.Resampling.LANCZOS))
        else:
            resized = cropped

        out = np.zeros_like(arr)
        cy = (H - new_h) // 2
        cx = (W - new_w) // 2
        out[cy:cy + new_h, cx:cx + new_w] = resized
        Image.fromarray(out).save(path)
        print(
            f"  {path.name}: kept {len(keep_labels)}/{ncomp} components, "
            f"dropped {dropped_px}px; fit-scaled by {scale:.3f} into "
            f"{new_w}x{new_h} with margin={fit_margin}"
        )
        return

    cy = (int(ys.min()) + int(ys.max())) // 2
    cx = (int(xs.min()) + int(xs.max())) // 2
    dy = H // 2 - cy
    dx = W // 2 - cx
    rolled = np.roll(arr, (dy, dx), axis=(0, 1))
    Image.fromarray(rolled).save(path)
    print(
        f"  {path.name}: kept {len(keep_labels)}/{ncomp} components, "
        f"dropped {dropped_px}px; centred via dy={dy} dx={dx}"
    )


def main() -> None:
    args = sys.argv[1:]
    fit_margin: float | None = None
    if args and args[0] == "--fit":
        fit_margin = float(args[1])
        args = args[2:]
    if not args:
        raise SystemExit("Usage: cleanup_feather_sprites.py [--fit MARGIN] path1.png [path2.png ...]")
    for p in args:
        path = Path(p)
        print(f"Cleaning {path}...")
        cleanup(path, fit_margin)
    print("Done.")


if __name__ == "__main__":
    main()
