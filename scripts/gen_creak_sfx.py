#!/usr/bin/env python3
"""Generate the wooden sign-creak SFX via the ElevenLabs SFX API.

Played when the player taps a wooden prop (the OLE CANDY WEST sign, etc.) on
the level selector. Committed to the repo, not regenerated each build.
Requires ELEVENLABS_API_KEY in env or gcloud secret `ELEVENLABS_API_KEY`
(see reference_elevenlabs_vo). Modeled on gen_candy_tap_sfx.py.

  python3 scripts/gen_creak_sfx.py
"""
import base64
import subprocess
from pathlib import Path

PROMPT = ("A short dry wooden creak, about 600 milliseconds: a single old "
          "weathered timber sign groaning and creaking as it sways on its "
          "posts, rope-and-wood stress, no music, no reverb tail")
DURATION = 0.8
OUT = Path("godot/assets/sfx/sign_creak.ogg")


def api_key() -> str:
    import os
    if os.environ.get("ELEVENLABS_API_KEY"):
        return os.environ["ELEVENLABS_API_KEY"]
    p = subprocess.run(
        ["gcloud", "secrets", "versions", "access", "latest",
         "--secret=ELEVENLABS_API_KEY", "--format=get(payload.data)"],
        capture_output=True, text=True, check=True)
    return base64.b64decode(p.stdout.strip().replace("_", "/").replace("-", "+")).decode()


def main() -> None:
    import requests
    OUT.parent.mkdir(parents=True, exist_ok=True)
    r = requests.post(
        "https://api.elevenlabs.io/v1/sound-generation",
        headers={"xi-api-key": api_key(), "Content-Type": "application/json"},
        json={"text": PROMPT, "duration_seconds": DURATION,
              "prompt_influence": 0.55, "output_format": "mp3_22050_32"},
        timeout=60)
    r.raise_for_status()
    mp3 = OUT.with_suffix(".mp3")
    mp3.write_bytes(r.content)
    subprocess.run(["ffmpeg", "-y", "-i", str(mp3), "-c:a", "libvorbis",
                    "-q:a", "3", str(OUT)], check=True, capture_output=True)
    mp3.unlink()
    print(f"wrote {OUT} ({OUT.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
