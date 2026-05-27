#!/usr/bin/env python3
"""Generate one of six candy-tap SFX variants via the ElevenLabs SFX API.

Usage:
  python3 scripts/gen_candy_tap_sfx.py --variant sun_a_chime
  python3 scripts/gen_candy_tap_sfx.py --all   # generate all 6 in one run

Re-run only if the prompt or output settings change — the .ogg files
are committed to the repo, not regenerated each build. Requires
ELEVENLABS_API_KEY in env (or pulled from gcloud secret
`elevenlabs-api-key` per reference_elevenlabs_vo memory).
"""
import argparse
import os
import subprocess
import sys
import time
from pathlib import Path

VARIANTS = {
    "sun_a_chime": {
        "prompt": ("Short bright hard candy chime, ~300ms, single clean "
                   "high-pitched ting like tapping a glass-clear lollipop, "
                   "gentle decay"),
        "duration": 0.5,
    },
    "sun_b_stick": {
        "prompt": ("Short woody tap on caramel candy stick, ~300ms, lower "
                   "pitched with a soft thunk attack, like flicking a "
                   "sucker stick"),
        "duration": 0.5,
    },
    "sun_c_sparkle": {
        "prompt": ("Tiny crystalline butterscotch sparkle, ~250ms, very "
                   "short bright shimmery ting with quick decay, sugar-"
                   "glass crystal feel"),
        "duration": 0.5,
    },
    "moon_a_squish": {
        "prompt": ("Soft padded marshmallow squish, ~350ms, low gentle "
                   "thud with subtle airy puff, like pressing into a "
                   "marshmallow"),
        "duration": 0.5,
    },
    "moon_b_crunch": {
        "prompt": ("Short dry cookie crunch, ~300ms, single crisp brittle "
                   "crack, like biting into a white chocolate cookie"),
        "duration": 0.5,
    },
    "moon_c_tink": {
        "prompt": ("Gentle white chocolate tink, ~350ms, mellow bell-like "
                   "tone slightly damped, smooth and creamy"),
        "duration": 0.5,
    },
}
OUT_DIR = Path("godot/assets/sfx/sky_taps")
PROMPT_INFLUENCE = 0.5


def fetch_api_key() -> str:
    key = os.environ.get("ELEVENLABS_API_KEY")
    if key:
        return key
    proc = subprocess.run(
        ["gcloud", "secrets", "versions", "access", "latest",
         "--secret=ELEVENLABS_API_KEY", "--format=get(payload.data)"],
        capture_output=True, text=True, check=True,
    )
    import base64
    return base64.b64decode(
        proc.stdout.strip().replace("_", "/").replace("-", "+")
    ).decode()


def generate(variant_name: str, api_key: str) -> None:
    import requests
    spec = VARIANTS[variant_name]
    out_path = OUT_DIR / f"{variant_name}.ogg"
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    r = requests.post(
        "https://api.elevenlabs.io/v1/sound-generation",
        headers={"xi-api-key": api_key, "Content-Type": "application/json"},
        json={
            "text": spec["prompt"],
            "duration_seconds": spec["duration"],
            "prompt_influence": PROMPT_INFLUENCE,
            "output_format": "mp3_22050_32",
        },
        timeout=60,
    )
    r.raise_for_status()
    mp3_path = out_path.with_suffix(".mp3")
    mp3_path.write_bytes(r.content)
    subprocess.run(
        ["ffmpeg", "-y", "-i", str(mp3_path),
         "-c:a", "libvorbis", "-q:a", "3", str(out_path)],
        check=True, capture_output=True,
    )
    mp3_path.unlink()
    print(f"wrote {out_path} ({out_path.stat().st_size} bytes)")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--variant", choices=list(VARIANTS.keys()))
    ap.add_argument("--all", action="store_true")
    args = ap.parse_args()
    if not args.all and not args.variant:
        sys.exit("specify --variant <name> or --all")
    api_key = fetch_api_key()
    names = list(VARIANTS.keys()) if args.all else [args.variant]
    for n in names:
        generate(n, api_key)
        time.sleep(1.0)


if __name__ == "__main__":
    main()
