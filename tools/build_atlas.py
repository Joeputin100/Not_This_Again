#!/usr/bin/env python3
"""Build one sprite-sheet atlas from a video clip or a folder of frames.

Usage:
  build_atlas.py --clip path/to/clip.ogv --out godot/assets/sprites/atlases/cowboy_idle_a
  build_atlas.py --frames path/to/frames_dir --fps 24 --out .../name

Produces <out>.png (the grid atlas, RGBA, chroma-keyed transparent) and
<out>.atlas.json ({cols, rows, frame_count, fps}).
"""
import argparse, json, math, subprocess, sys, tempfile
from pathlib import Path
from PIL import Image

GREEN = (0, 177, 64)        # Veo chroma-green; tune if a clip differs
KEY_TOLERANCE = 70          # per-channel distance treated as background

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
    """Chroma-key Veo green to transparent."""
    img = img.convert("RGBA")
    px = img.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = px[x, y]
            if (abs(r - GREEN[0]) + abs(g - GREEN[1]) + abs(b - GREEN[2])
                    < KEY_TOLERANCE * 3):
                px[x, y] = (r, g, b, 0)
    return img

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
    ap.add_argument("--clip"); ap.add_argument("--frames")
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
