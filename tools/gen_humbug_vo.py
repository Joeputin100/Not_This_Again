#!/usr/bin/env python3
"""Generate Professor Humbug's level-selector voice lines via ElevenLabs.

Renders one MP3 per tip / thought / easter-joke line so the SPOKEN line
matches the speech-bubble text exactly. The line text is read straight
from godot/assets/text/en.json (the single source of truth) — keep this
script and en.json in sync by re-running after editing the humbug lines.

Voice: ElevenLabs "Roger" — the same voice as the existing humbug_menu
clips, so menu-Humbug and selector-Humbug sound like one character.

Run with the roguelike ElevenLabs venv (it has the SDK + the key):
  /home/projects/roguelike/.venv-eleven/bin/python tools/gen_humbug_vo.py

Key lookup: $ELEVENLABS_API_KEY / $ELEVEN_LABS_API_KEY, else a secrets.env
(this repo's, else the roguelike project's).

Output: godot/assets/audio/characters/humbug_{tip,thought,joke}_<n>.mp3
"""
import json
import os
import re
import subprocess
import sys
from pathlib import Path

from elevenlabs.client import ElevenLabs

ROOT = Path(__file__).resolve().parents[1]
EN_JSON = ROOT / "godot" / "assets" / "text" / "en.json"
OUT_DIR = ROOT / "godot" / "assets" / "audio" / "characters"
HUMBUG_VOICE = "CwhRBWXzGAHq8TQ4Fs17"   # ElevenLabs "Roger" — Humbug's menu voice
MODEL = "eleven_flash_v2_5"
OUTPUT_FMT = "mp3_44100_128"
# en.json  humbug.<key>  array  ->  humbug_<slug>_<n>.mp3
GROUPS = {"tips": "tip", "thoughts": "thought", "easter_jokes": "joke"}


def read_api_key() -> str:
    for env in ("ELEVENLABS_API_KEY", "ELEVEN_LABS_API_KEY"):
        val = os.getenv(env)
        if val:
            return val
    # Google Secret Manager — the key lives at secret ELEVENLABS_API_KEY.
    try:
        out = subprocess.run(
            ["gcloud", "secrets", "versions", "access", "latest",
             "--secret=ELEVENLABS_API_KEY"],
            capture_output=True, text=True, timeout=30)
        if out.returncode == 0 and out.stdout.strip():
            return out.stdout.strip()
    except (OSError, subprocess.SubprocessError):
        pass
    for path in (ROOT / "secrets.env",
                 Path("/home/projects/roguelike/secrets.env")):
        if path.exists():
            for line in path.read_text().splitlines():
                m = re.match(r'\s*ELEVEN_?LABS_API_?key\s*=\s*"?([^"\n]+)"?',
                             line, re.I)
                if m:
                    return m.group(1).strip()
    sys.exit("FATAL: no ElevenLabs API key (env / GSM / secrets.env)")


def for_speech(text: str) -> str:
    """Bubble glyphs the TTS shouldn't read literally."""
    return (text.replace("×", "multiplying")   # ×
                .replace("÷", "dividing")       # ÷
                .replace(" — ", ", ")           # spaced em-dash → pause
                .replace("—", ", "))


def main() -> None:
    humbug = json.loads(EN_JSON.read_text())["humbug"]
    client = ElevenLabs(api_key=read_api_key())
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for key, slug in GROUPS.items():
        for i, line in enumerate(humbug[key]):
            dst = OUT_DIR / ("humbug_%s_%d.mp3" % (slug, i))
            audio = client.text_to_speech.convert(
                voice_id=HUMBUG_VOICE,
                text=for_speech(line),
                model_id=MODEL,
                output_format=OUTPUT_FMT,
            )
            with open(dst, "wb") as f:
                for chunk in audio:
                    f.write(chunk)
            print("wrote %-22s  %s" % (dst.name, line[:48]))


if __name__ == "__main__":
    main()
