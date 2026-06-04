#!/usr/bin/env python3
"""Generate creature sound effects (chicken coop bust, bull charge/death) via
ElevenLabs text-to-sound-effects. Offline; the MP3s are committed and played at
runtime by AudioBus.play_sfx(slug). Mirrors the VO generators' key lookup.

Run with the ElevenLabs venv:
  /home/projects/roguelike/.venv-eleven/bin/python tools/gen_creature_sfx.py
"""
from __future__ import annotations
import os, re, sys, subprocess
from pathlib import Path
from elevenlabs.client import ElevenLabs

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "godot" / "assets" / "sfx" / "creatures"
SFX_OUTPUT = "mp3_22050_32"
SFX_MODEL = "eleven_text_to_sound_v2"

# slug -> (prompt, duration_seconds)
SFX: dict[str, tuple[str, float]] = {
    "chicken_bust": (
        "a flock of panicked cartoon chickens suddenly bursting out, frantic "
        "clucking and squawking, flapping wings, brief and chaotic, comedic",
        2.2),
    "bull_snort": (
        "an angry bull snorting and huffing aggressively, short nostril blast, "
        "ready to charge, cartoon western",
        1.0),
    "bull_bellow": (
        "a big bull bellowing and groaning as it is knocked down, heavy thud, "
        "cartoon western, defeated",
        1.6),
}


def read_api_key() -> str:
    for env in ("ELEVENLABS_API_KEY", "ELEVEN_LABS_API_KEY"):
        val = os.getenv(env)
        if val:
            return val
    try:
        out = subprocess.run(
            ["gcloud", "secrets", "versions", "access", "latest",
             "--secret=ELEVENLABS_API_KEY"],
            capture_output=True, text=True, timeout=30)
        if out.returncode == 0 and out.stdout.strip():
            return out.stdout.strip()
    except (OSError, subprocess.SubprocessError):
        pass
    for path in (ROOT / "secrets.env", Path("/home/projects/roguelike/secrets.env")):
        if path.exists():
            for line in path.read_text().splitlines():
                m = re.match(r'\s*ELEVEN_?LABS_API_?key\s*=\s*"?([^"\n]+)"?', line, re.I)
                if m:
                    return m.group(1).strip()
    sys.exit("FATAL: no ElevenLabs API key (env / GSM / secrets.env)")


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    client = ElevenLabs(api_key=read_api_key())
    for slug, (prompt, dur) in SFX.items():
        path = OUT_DIR / f"{slug}.mp3"
        print(f"generating {slug} ({dur}s) ...")
        audio = client.text_to_sound_effects.convert(
            text=prompt, duration_seconds=dur,
            output_format=SFX_OUTPUT, model_id=SFX_MODEL)
        with open(path, "wb") as fh:
            for chunk in audio:
                if chunk:
                    fh.write(chunk)
        print(f"  wrote {path} ({path.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
