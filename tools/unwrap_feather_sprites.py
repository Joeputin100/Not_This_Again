#!/usr/bin/env python3
"""Re-centre RGBA sprites by torus-rolling wrapped edge content into frame.

Gemini sometimes emits images where part of the subject is clipped at one
edge and re-appears on the opposite edge (a torus-padding artifact). For
each axis independently, this script finds the longest fully-transparent
run circularly and rolls the canvas so that gap sits split across the
edges — reuniting any wrapped piece with the main subject and centring
the result in the original canvas size.

Pure translation, no resize. If the content is already contiguous and
centred, the shift is small or zero.

Usage:
    python3 tools/unwrap_feather_sprites.py path1.png [path2.png ...]

Overwrites each input in place. Make a backup first if you want one.
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image


ALPHA_THRESHOLD = 8  # alpha > this counts as "opaque enough" to be subject


def longest_zero_run_circular(mask_1d: np.ndarray) -> tuple[int, int]:
    """In a circular 0/1 array, find the longest run of zeros.

    Returns (start_index, length). If the array is all-zeros, returns
    (0, n). If all-ones, returns (0, 0).
    """
    n = len(mask_1d)
    if not mask_1d.any():
        return 0, n
    if mask_1d.all():
        return 0, 0
    doubled = np.concatenate([mask_1d, mask_1d])
    best_start, best_len = 0, 0
    i = 0
    while i < 2 * n:
        if doubled[i] == 0:
            j = i
            while j < 2 * n and doubled[j] == 0:
                j += 1
            run_len = min(j - i, n)  # a run longer than n means all-zeros
            if run_len > best_len:
                best_len = run_len
                best_start = i % n
            i = j
        else:
            i += 1
    return best_start, best_len


def axis_roll_to_centre(has_content_1d: np.ndarray) -> int:
    """Roll amount that places the longest transparent gap centred on the
    array edges (so content becomes contiguous and roughly centred)."""
    n = len(has_content_1d)
    gap_start, gap_len = longest_zero_run_circular(has_content_1d)
    if gap_len == 0 or gap_len == n:
        return 0
    gap_mid = (gap_start + gap_len // 2) % n
    return -gap_mid % n  # roll so gap_mid moves to index 0


def unwrap(path: Path) -> None:
    img = Image.open(path).convert("RGBA")
    arr = np.array(img)
    alpha = arr[..., 3]
    mask = alpha > ALPHA_THRESHOLD

    row_has = np.asarray(mask.any(axis=1))
    col_has = np.asarray(mask.any(axis=0))

    dy = axis_roll_to_centre(row_has)
    dx = axis_roll_to_centre(col_has)

    if dy == 0 and dx == 0:
        print(f"  {path.name}: no shift needed (content already centred)")
        return

    rolled = np.roll(arr, (dy, dx), axis=(0, 1))
    Image.fromarray(rolled).save(path)
    print(f"  {path.name}: rolled dy={dy} dx={dx}")


def main() -> None:
    if len(sys.argv) < 2:
        raise SystemExit("Usage: unwrap_feather_sprites.py path1.png [path2.png ...]")
    for p in sys.argv[1:]:
        path = Path(p)
        print(f"Unwrapping {path}...")
        unwrap(path)
    print("Done.")


if __name__ == "__main__":
    main()
