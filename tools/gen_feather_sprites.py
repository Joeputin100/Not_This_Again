#!/usr/bin/env python3
"""Generate 3 transparent-background loose-feather sprites (SP1 Task 4).

Uses the project's 2-pass NB2 alpha-matte pipeline (scripts/diff_matte.py):
  1. Generate each feather on a white background
  2. Generate each feather on a black background
  3. Run diff_matte.py white.png black.png out.png  → true-alpha RGBA

Key from GSM: GEMINI_API_KEY.

Run: python3 tools/gen_feather_sprites.py
Outputs (RGBA, transparent background):
  godot/assets/sprites/fx/feather_0.png   -- brown/red-brown contour feather (RIR)
  godot/assets/sprites/fx/feather_1.png   -- pure white contour feather (Leghorn)
  godot/assets/sprites/fx/feather_2.png   -- small fluffy down feather, white+grey speckle (Silkie)
"""
import base64
import json
import os
import subprocess
import sys
import tempfile
import urllib.request

API_URL = (
    "https://generativelanguage.googleapis.com/v1beta/models/"
    "gemini-3.1-flash-image-preview:generateContent"
)

OUT_DIR = "godot/assets/sprites/fx"

FEATHERS = {
    "feather_0": {
        "desc": "brown/red-brown contour feather (Rhode Island Red)",
        "white_prompt": (
            "ONE single solitary chicken contour feather, brown and red-brown in "
            "colour, centred on a pure white background. ONLY ONE FEATHER — do not "
            "include a second feather, do not arrange multiple feathers, no "
            "decorative pattern, no tiling. Just one feather, shown at a slight "
            "angle, filling most of the frame. Realistic-ish cartoon style, no "
            "shadows."
        ),
        "black_prompt": (
            "ONE single solitary chicken contour feather, brown and red-brown in "
            "colour, centred on a pure black background. ONLY ONE FEATHER — do not "
            "include a second feather, do not arrange multiple feathers, no "
            "decorative pattern, no tiling. Just one feather, shown at a slight "
            "angle, filling most of the frame. Realistic-ish cartoon style, no "
            "shadows."
        ),
    },
    "feather_1": {
        "desc": "cream/ivory contour feather with darker tips (White Leghorn)",
        # Pure white on white can't be isolated by diff-matte (subject - white = 0).
        # Cream/ivory with darker tips gives the matte enough contrast while still
        # reading as a Leghorn feather on screen. Sized smaller than feathers 0/2
        # because the previous roll extended past the top edge and got clipped.
        "white_prompt": (
            "ONE single solitary chicken contour feather in CREAM and IVORY tones "
            "with subtle darker beige tips and a soft grey shaft, centred on a "
            "pure white background. ONLY ONE FEATHER — do not include a second "
            "feather, do not arrange multiple feathers, no decorative pattern, no "
            "tiling. The ENTIRE feather must be fully visible inside the frame "
            "with clear empty margin on all four sides — do NOT clip or crop the "
            "feather at any edge. The feather occupies roughly 60% of the frame, "
            "shown at a slight angle. Clean cartoon style with a visible dark "
            "outline, no shadows."
        ),
        "black_prompt": (
            "ONE single solitary chicken contour feather in CREAM and IVORY tones "
            "with subtle darker beige tips and a soft grey shaft, centred on a "
            "pure black background. ONLY ONE FEATHER — do not include a second "
            "feather, do not arrange multiple feathers, no decorative pattern, no "
            "tiling. The ENTIRE feather must be fully visible inside the frame "
            "with clear empty margin on all four sides — do NOT clip or crop the "
            "feather at any edge. The feather occupies roughly 60% of the frame, "
            "shown at a slight angle. Clean cartoon style, no shadows."
        ),
    },
    "feather_2": {
        "desc": "small fluffy down feather, white with grey speckle (Silkie)",
        "white_prompt": (
            "A single small fluffy down feather — wispy, round and soft — "
            "white with grey speckles, isolated on a pure white background. "
            "The feather is centred and fills most of the frame. "
            "Cartoon style, no shadows. Nothing else in the image."
        ),
        "black_prompt": (
            "A single small fluffy down feather — wispy, round and soft — "
            "white with grey speckles, isolated on a pure black background. "
            "The feather is centred and fills most of the frame. "
            "Cartoon style, no shadows. Nothing else in the image."
        ),
    },
}


def get_api_key() -> str:
    result = subprocess.run(
        ["gcloud", "secrets", "versions", "access", "latest", "--secret=GEMINI_API_KEY"],
        capture_output=True, text=True, check=True
    )
    return result.stdout.strip()


def generate_image(prompt: str, api_key: str) -> bytes:
    """Call Gemini image-gen API and return raw PNG bytes."""
    body = json.dumps({
        "contents": [{"parts": [{"text": prompt}]}],
        "generationConfig": {"responseModalities": ["IMAGE"]}
    }).encode()

    req = urllib.request.Request(
        API_URL,
        data=body,
        headers={
            "Content-Type": "application/json",
            "x-goog-api-key": api_key,
        },
        method="POST"
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        data = json.loads(resp.read())

    parts = data["candidates"][0]["content"]["parts"]
    for part in parts:
        if "inlineData" in part:
            b64 = part["inlineData"]["data"]
            return base64.b64decode(b64)

    raise RuntimeError(f"No inlineData in response: {json.dumps(data)[:500]}")


def run_diff_matte(white_path: str, black_path: str, out_path: str) -> None:
    result = subprocess.run(
        [sys.executable, "scripts/diff_matte.py", white_path, black_path, out_path],
        capture_output=True, text=True
    )
    print(result.stdout)
    if result.returncode != 0:
        print(result.stderr)
        raise RuntimeError(f"diff_matte.py failed with code {result.returncode}")


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    api_key = get_api_key()
    print(f"API key fetched ({len(api_key)} chars)")

    # Optional positional args restrict the run to a subset of feathers (e.g.
    # `python3 tools/gen_feather_sprites.py feather_0 feather_1` to re-roll only
    # the two broken ones).
    requested = sys.argv[1:]
    if requested:
        unknown = [n for n in requested if n not in FEATHERS]
        if unknown:
            raise SystemExit(f"Unknown feather names: {unknown}. Known: {list(FEATHERS)}")
        targets = {n: FEATHERS[n] for n in requested}
    else:
        targets = FEATHERS

    with tempfile.TemporaryDirectory() as tmpdir:
        for name, spec in targets.items():
            out_path = f"{OUT_DIR}/{name}.png"
            print(f"\n==> Generating {name} ({spec['desc']}) ...")

            white_path = os.path.join(tmpdir, f"{name}_white.png")
            black_path = os.path.join(tmpdir, f"{name}_black.png")

            print("    Generating white-background pass...")
            white_bytes = generate_image(spec["white_prompt"], api_key)
            with open(white_path, "wb") as f:
                f.write(white_bytes)
            print(f"    White pass: {len(white_bytes)} bytes -> {white_path}")

            print("    Generating black-background pass...")
            black_bytes = generate_image(spec["black_prompt"], api_key)
            with open(black_path, "wb") as f:
                f.write(black_bytes)
            print(f"    Black pass: {len(black_bytes)} bytes -> {black_path}")

            print("    Running diff_matte.py to extract alpha...")
            run_diff_matte(white_path, black_path, out_path)
            print(f"    Saved {out_path}")

    print("\nDone — 3 feather sprites written.")


if __name__ == "__main__":
    main()
