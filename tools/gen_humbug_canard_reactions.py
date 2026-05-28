#!/usr/bin/env python3
"""Generate the short Candy-Crush-style tap reactions for Humbug + Canard.

These are the SINGLE-TAP reactions on the splash screen + level selector
(one-syllable, non-verbal). The existing verbal lines (humbug_menu_*,
humbug_tip_*, humbug_thought_*) stay as the rapid-tap "annoyed" response.

Humbug reactions: King Candy voice (eleven_v3 audio tags), short utterances.
Canard reactions: ElevenLabs SFX sound-generation (duck-toy sounds).

Run with the roguelike eleven venv:
  /home/projects/roguelike/.venv-eleven/bin/python tools/gen_humbug_canard_reactions.py
"""
import os
import subprocess
import sys
from pathlib import Path

from elevenlabs.client import ElevenLabs

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "godot/assets/audio/characters"
HUMBUG_VOICE = "PRZec1rpHH9FRamLcdLq"   # King Candy voice
MODEL = "eleven_v3"                     # required for audio tags
OUTPUT_FMT = "mp3_44100_128"

# Short tagged utterances — eleven_v3 performs the bracketed tag.
HUMBUG_REACTIONS = {
    "humbug_react_harumph": "[gruffly] Harrumph!",
    "humbug_react_snort":   "[snorts] Hmph!",
    "humbug_react_hmm":     "[thoughtful] Hmmm?",
    "humbug_react_huff":    "[huffs] Bah.",
    "humbug_react_tut":     "[disapproving] Tut, tut!",
}

# Canard SFX prompts — sound-generation endpoint (min duration 0.5s).
CANARD_REACTIONS = {
    "canard_react_quack":   "single short cute cartoon rubber duck quack",
    "canard_react_giggle":  "short bright squeaky cartoon giggle, toy duck",
    "canard_react_squeak":  "single rubber duck squeeze toy squeak",
    "canard_react_honk":    "short playful cartoon party-horn honk",
    "canard_react_chitter": "quick playful duck chatter burst, cartoon",
}


def read_api_key() -> str:
    for env in ("ELEVENLABS_API_KEY", "ELEVEN_LABS_API_KEY"):
        val = os.getenv(env)
        if val:
            return val
    out = subprocess.run(
        ["gcloud", "secrets", "versions", "access", "latest",
         "--secret=ELEVENLABS_API_KEY"],
        capture_output=True, text=True, timeout=30)
    if out.returncode == 0 and out.stdout.strip():
        return out.stdout.strip()
    sys.exit("FATAL: no ElevenLabs API key")


def render_humbug(client: ElevenLabs, name: str, spoken: str) -> None:
    audio = client.text_to_speech.convert(
        voice_id=HUMBUG_VOICE, text=spoken, model_id=MODEL,
        output_format=OUTPUT_FMT)
    dst = OUT_DIR / f"{name}.mp3"
    with open(dst, "wb") as f:
        for chunk in audio:
            f.write(chunk)
    print(f"wrote {dst.name:28} {spoken}")


def render_canard(api_key: str, name: str, prompt: str) -> None:
    import requests
    r = requests.post(
        "https://api.elevenlabs.io/v1/sound-generation",
        headers={"xi-api-key": api_key, "Content-Type": "application/json"},
        json={"text": prompt, "duration_seconds": 0.5, "prompt_influence": 0.5,
              "output_format": "mp3_44100_128"},
        timeout=60)
    r.raise_for_status()
    dst = OUT_DIR / f"{name}.mp3"
    dst.write_bytes(r.content)
    print(f"wrote {dst.name:28} {prompt}")


def main() -> None:
    key = read_api_key()
    client = ElevenLabs(api_key=key)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for name, spoken in HUMBUG_REACTIONS.items():
        render_humbug(client, name, spoken)
    for name, prompt in CANARD_REACTIONS.items():
        render_canard(key, name, prompt)


if __name__ == "__main__":
    main()
