#!/usr/bin/env python3
"""Generate Slippery Pete's voice lines (angry) via ElevenLabs.

Pete's dialog text lives in en.json (boss.slippery_pete_dialog_*). Until now
the game reused pete_intro.mp3 for every line; this records the full set so
he actually speaks his written dialog. Also generates short tap-reaction
grunts for the main-menu splash.

Voice: OYWwCdDHouzDwiZJWOOu, model eleven_v3 (angry audio tags).
Run with the roguelike eleven venv:
  /home/projects/roguelike/.venv-eleven/bin/python tools/gen_pete_vo.py
"""
import os
import subprocess
import sys
from pathlib import Path

from elevenlabs.client import ElevenLabs

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "godot/assets/audio/characters"
PETE_VOICE = "OYWwCdDHouzDwiZJWOOu"
MODEL = "eleven_v3"
OUTPUT_FMT = "mp3_44100_128"

# Lines mirror en.json boss.slippery_pete_dialog_*; tagged angry for eleven_v3.
LINES = {
    "pete_intro":    "[furious] WELL IF IT AIN'T THE POSSE! YER IN FER IT NOW!",
    "pete_taunt_0":  "[shouting, furious] WAAAAGH! YOU LILY-LIVERED SADDLE-TRAMPS!",
    "pete_taunt_1":  "[angry] GIT OFFA MY TRAIL, VARMINTS!",
    "pete_taunt_2":  "[angry] I'LL LEARN YA SOMETHIN'!",
    "pete_taunt_3":  "[furious] RAA-SSAA-FRACKIN' POSSE!",
    "pete_hit_0":    "[pained, angry] OW! MY BACKSIDE!",
    "pete_hit_1":    "[angry] DAGNABBIT!",
    "pete_hit_2":    "[angry] CONSARN IT!",
    "pete_hit_3":    "[furious] YOU FOUL VARMINT!",
    "pete_dying_0":  "[anguished] AAAAUGH! NOT LIKE THIS!",
    "pete_dying_1":  "[weakly] REMEMBER ME...",
    "pete_dying_2":  "[muttering] RA-SSAA-FRACKIN'...",
    "pete_dying_3":  "[furious] WHY I OUGHTA-",
    # Short tap-reaction grunts for the splash.
    "pete_react_0":  "[gruff, angry] BAH!",
    "pete_react_1":  "[furious] GRRRAH!",
    "pete_react_2":  "[annoyed] HMPH! VARMINT.",
}


def read_api_key() -> str:
    for env in ("ELEVENLABS_API_KEY", "ELEVEN_LABS_API_KEY"):
        v = os.getenv(env)
        if v:
            return v
    out = subprocess.run(
        ["gcloud", "secrets", "versions", "access", "latest",
         "--secret=ELEVENLABS_API_KEY"],
        capture_output=True, text=True, timeout=30)
    if out.returncode == 0 and out.stdout.strip():
        return out.stdout.strip()
    sys.exit("FATAL: no ElevenLabs API key")


def main() -> None:
    client = ElevenLabs(api_key=read_api_key())
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for slug, text in LINES.items():
        audio = client.text_to_speech.convert(
            voice_id=PETE_VOICE, text=text, model_id=MODEL, output_format=OUTPUT_FMT,
            apply_text_normalization="on")  # ElevenLabs best-practice: force text normalization
        dst = OUT_DIR / f"{slug}.mp3"
        with open(dst, "wb") as f:
            for chunk in audio:
                f.write(chunk)
        print(f"wrote {dst.name:18} {text}")


if __name__ == "__main__":
    main()
